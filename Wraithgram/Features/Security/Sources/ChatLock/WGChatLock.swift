import Foundation
import UIKit
import SwiftSignalKit
import Display
import Postbox
import TelegramCore
import AccountContext
import WGCore
import WGHooks
import WGFeaturesShared

/// «Пароль на чаты» at run time. Per account (one unlock never opens another account's chats), in
/// memory only (a cold start locks everything), timed with a monotonic clock that keeps running while
/// the device sleeps and that the user can not wind back (`CLOCK_MONOTONIC_RAW`).
///
/// Two modes:
/// - «Автоблокировка» off: a chat is open for as long as a chat screen of it is alive; leaving it
///   (the screen goes away) locks it again. The grant is tied to the screens, not to a clock.
/// - «Автоблокировка» on: one check opens every protected chat of the account until the app has been
///   in the background for the chosen time; «0» also closes an open protected chat.
///
/// Chats of a locked secret folder with «Защищать чаты папки» are protected the same way, but only a
/// check for that very chat (or unlocking the folder) opens them.
///
/// Lists (preview, media thumbnails, author line, search) hide protected chats' content whatever the
/// unlock state: they are not a place where a chat was «opened». Main thread only.
final class WGChatLock {
    static let shared = WGChatLock()

    private struct GrantKey: Hashable {
        let account: WGAccountID
        let peer: WGPeerKey
    }

    /// A screen a grant lives with: a chat screen or a profile (its shared media).
    private final class WeakOwner {
        weak var value: AnyObject?

        init(_ value: AnyObject) {
            self.value = value
        }
    }

    private final class Grant {
        var controllers: [WeakOwner] = []
        /// A check passed and the chat screen is about to be created (`navigateToChatController`).
        var pendingUntil: UInt64 = 0

        func isAlive(now: UInt64) -> Bool {
            self.controllers.removeAll(where: { $0.value == nil })
            return !self.controllers.isEmpty || now < self.pendingUntil
        }
    }

    private final class Screen {
        weak var controller: ChatController?
        let context: AccountContext
        let peerId: EnginePeer.Id
        var isPreview: Bool
        var cover: WGLockCoverView?

        init(controller: ChatController, context: AccountContext, peerId: EnginePeer.Id, isPreview: Bool) {
            self.controller = controller
            self.context = context
            self.peerId = peerId
            self.isPreview = isPreview
        }
    }

    private var grants: [GrantKey: Grant] = [:]
    private var unlockedAccounts = Set<WGAccountID>()
    private var screens: [ObjectIdentifier: Screen] = [:]
    private var backgroundedAt: UInt64?
    /// Secret chat → its user, learned from peers seen in rows and in opened chats: a protected
    /// person's secret chat is protected too.
    private let secretChatUsers = Atomic<[EnginePeer.Id: EnginePeer.Id]>(value: [:])

    static func now() -> UInt64 {
        return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
    }

    // MARK: Protection

    /// The chat lock covers this chat (configuration only). Any thread.
    func isChatLockProtected(account: WGAccountID, peerId: EnginePeer.Id) -> Bool {
        if !WGSecuritySharedSettings.chatLockEnabled.value {
            return false
        }
        if WGSecuritySharedSettings.chatLockAllChats.value {
            return WGChatProtection.isLockable(peerId)
        }
        let peers = WGSecuritySharedSettings.chatLockPeers.value(for: account)
        if peers.contains(peerId.wgKey) {
            return true
        }
        if let user = self.secretChatUser(peerId), peers.contains(user.wgKey) {
            return true
        }
        return false
    }

    /// The chat belongs to the account's secret folder and the folder is locked. Any thread.
    func isFolderProtected(account: WGAccountID, peerId: EnginePeer.Id) -> Bool {
        if !WGSecuritySharedSettings.secretFolderPeers.value(for: account).contains(peerId.wgKey) {
            return false
        }
        return !WGSecretFolder.shared.isUnlocked(account: account)
    }

    /// Rows and search: the chat's content is hidden. Layout paths, any thread.
    func hidesContentInLists(account: WGAccountID, peerId: EnginePeer.Id) -> Bool {
        if self.isChatLockProtected(account: account, peerId: peerId) {
            return true
        }
        return self.isFolderProtected(account: account, peerId: peerId)
    }

    func notePeer(_ peer: EnginePeer?) {
        guard let peer, case let .secretChat(secretChat) = peer else {
            return
        }
        if self.secretChatUsers.with({ $0[peer.id] == secretChat.regularPeerId }) {
            return
        }
        let _ = self.secretChatUsers.modify { current in
            var current = current
            current[peer.id] = secretChat.regularPeerId
            return current
        }
    }

    private func secretChatUser(_ peerId: EnginePeer.Id) -> EnginePeer.Id? {
        if peerId.namespace != Namespaces.Peer.SecretChat {
            return nil
        }
        return self.secretChatUsers.with { $0[peerId] }
    }

    // MARK: Unlock state (main thread)

    /// Whether opening this chat now needs a check. `controller` — the screen asking (a chat screen,
    /// a profile); a grant found for the chat starts living with it.
    func needsUnlock(account: WGAccountID, peerId: EnginePeer.Id, controller: AnyObject?) -> Bool {
        let chatLock = self.isChatLockProtected(account: account, peerId: peerId)
        let folder = self.isFolderProtected(account: account, peerId: peerId)
        if !chatLock && !folder {
            return false
        }
        if let grant = self.grants[GrantKey(account: account, peer: peerId.wgKey)], grant.isAlive(now: WGChatLock.now()) {
            if let controller, !grant.controllers.contains(where: { $0.value === controller }) {
                // The screen the check was for exists now: from here the grant lives with it.
                grant.controllers.append(WeakOwner(controller))
                grant.pendingUntil = 0
            }
            return false
        }
        if folder {
            return true
        }
        if WGSecuritySettings.chatLockAutolock.value && self.unlockedAccounts.contains(account) {
            return false
        }
        return true
    }

    /// A check for this chat passed.
    func grant(account: WGAccountID, peerId: EnginePeer.Id, controller: AnyObject?) {
        let key = GrantKey(account: account, peer: peerId.wgKey)
        let grant = self.grants[key] ?? Grant()
        if let controller {
            grant.controllers.append(WeakOwner(controller))
        } else {
            grant.pendingUntil = WGChatLock.now() + 15 * 1_000_000_000
        }
        self.grants[key] = grant
        if WGSecuritySettings.chatLockAutolock.value && self.isChatLockProtected(account: account, peerId: peerId) {
            self.unlockedAccounts.insert(account)
        }
        self.pruneGrants()
    }

    private func pruneGrants() {
        let now = WGChatLock.now()
        for (key, grant) in self.grants where !grant.isAlive(now: now) {
            self.grants.removeValue(forKey: key)
        }
    }

    /// «Автоблокировка» ran out: every chat of every account asks again, open ones included.
    private func lockEverything() {
        self.unlockedAccounts.removeAll()
        self.grants.removeAll()
    }

    // MARK: Chat screens

    func screenEvent(_ event: WGChatScreenEvent, screen: WGChatScreen) {
        guard let controller = screen.controller, let peerId = screen.chatLocation.peerId else {
            return
        }
        let account = screen.context.account.id.wg
        let id = ObjectIdentifier(controller)
        switch event {
        case .willAppear:
            self.pruneScreens()
            // Only screens of protected chats are tracked (a folder's chats too: the folder locks
            // on every trip to the background).
            let isProtected = self.isChatLockProtected(account: account, peerId: peerId) || WGSecuritySharedSettings.secretFolderPeers.value(for: account).contains(peerId.wgKey)
            if !isProtected {
                if let entry = self.screens.removeValue(forKey: id) {
                    self.uncover(entry)
                }
                return
            }
            let entry = self.screens[id] ?? Screen(controller: controller, context: screen.context, peerId: peerId, isPreview: screen.isPreview)
            entry.isPreview = screen.isPreview
            self.screens[id] = entry
            // A peek never opens a chat, even an unlocked one in «автоблокировка».
            if screen.isPreview {
                if self.hidesContentInLists(account: account, peerId: peerId) {
                    self.cover(entry)
                }
            } else if self.needsUnlock(account: account, peerId: peerId, controller: controller) {
                self.cover(entry)
            } else {
                self.uncover(entry)
            }
        case .didAppear:
            guard let entry = self.screens[id] else {
                return
            }
            entry.isPreview = screen.isPreview
            if entry.cover != nil && !entry.isPreview {
                if !self.needsUnlock(account: account, peerId: peerId, controller: controller) {
                    self.uncover(entry)
                } else if UIApplication.shared.applicationState == .active {
                    self.ask(entry)
                }
            }
        case .willDisappear:
            break
        }
    }

    private func pruneScreens() {
        for (key, screen) in self.screens where screen.controller == nil {
            self.screens.removeValue(forKey: key)
        }
    }

    private func cover(_ screen: Screen) {
        guard let controller = screen.controller else {
            return
        }
        controller.canReadHistory.set(false)
        if let cover = screen.cover {
            controller.view.bringSubviewToFront(cover)
            return
        }
        let presentationData = screen.context.sharedContext.currentPresentationData.with { $0 }
        let cover = WGLockCoverView(theme: presentationData.theme, title: WGStrings.Security.ChatLock.coverTitle, unlockTitle: screen.isPreview ? nil : WGStrings.Security.ChatLock.coverUnlock, closeTitle: screen.isPreview ? nil : WGStrings.Security.ChatLock.coverClose)
        cover.unlock = { [weak self, weak screen] in
            guard let self, let screen else {
                return
            }
            self.ask(screen)
        }
        cover.close = { [weak screen] in
            guard let controller = screen?.controller else {
                return
            }
            WGChatLock.close(controller)
        }
        cover.frame = controller.view.bounds
        controller.view.addSubview(cover)
        screen.cover = cover
    }

    private func uncover(_ screen: Screen) {
        if let cover = screen.cover {
            screen.cover = nil
            cover.removeFromSuperview()
            screen.controller?.canReadHistory.set(true)
        }
    }

    private func ask(_ screen: Screen) {
        guard let controller = screen.controller else {
            return
        }
        let account = screen.context.account.id.wg
        let peerId = screen.peerId
        WGLocalAuthGate.shared.authenticate(context: screen.context, reason: WGStrings.Security.Auth.reasonChat, completion: { [weak self, weak controller] granted in
            guard let self, let controller, granted else {
                return
            }
            self.grant(account: account, peerId: peerId, controller: controller)
            if let entry = self.screens[ObjectIdentifier(controller)] {
                self.uncover(entry)
            }
        })
    }

    static func close(_ controller: ChatController) {
        if let navigationController = controller.navigationController as? NavigationController, navigationController.viewControllers.contains(where: { $0 === controller }) {
            navigationController.filterController(controller, animated: true)
        } else {
            controller.dismiss()
        }
    }

    // MARK: Opening a chat (WGChatScreenHooks.openChat)

    /// `true` = the check took the navigation over.
    func interceptOpen(_ params: NavigateToChatControllerParams, proceed: @escaping () -> Void) -> Bool {
        let account = params.context.account.id.wg
        if case let .peer(peer) = params.chatLocation {
            self.notePeer(peer)
        }
        let peerId = params.chatLocation.peerId
        if !self.needsUnlock(account: account, peerId: peerId, controller: nil) {
            return false
        }
        WGLocalAuthGate.shared.authenticate(context: params.context, reason: WGStrings.Security.Auth.reasonChat, completion: { [weak self] granted in
            guard let self, granted else {
                return
            }
            self.grant(account: account, peerId: peerId, controller: nil)
            proceed()
        })
        return true
    }

    // MARK: App lifecycle

    /// Main thread, after the secret folder has locked.
    func applicationDidEnterBackground() {
        self.backgroundedAt = WGChatLock.now()
        let autolock = WGSecuritySettings.chatLockAutolock.value
        let immediately = autolock && WGSecuritySettings.chatLockAutolockSeconds <= 0.0
        if immediately {
            self.lockEverything()
        } else {
            // The folder's chats follow the folder: it locks on every trip to the background.
            for key in Array(self.grants.keys) where self.isFolderProtected(account: key.account, peerId: PeerId(wgKey: key.peer)) {
                self.grants.removeValue(forKey: key)
            }
        }
        self.pruneScreens()
        for screen in self.screens.values {
            guard let controller = screen.controller, controller.view.window != nil else {
                continue
            }
            let account = screen.context.account.id.wg
            let chatLock = self.isChatLockProtected(account: account, peerId: screen.peerId)
            let folder = self.isFolderProtected(account: account, peerId: screen.peerId)
            if !chatLock && !folder {
                continue
            }
            // The app switcher's snapshot is taken after this: show the cover, not the chat.
            if autolock || folder || screen.isPreview {
                self.cover(screen)
            }
            if immediately && chatLock && !screen.isPreview {
                WGChatLock.close(controller)
            }
        }
    }

    /// Main thread. Only a return from the background counts — a system prompt (Face ID, the device
    /// passcode) also makes the app inactive and active again, and must not ask once more.
    func applicationDidBecomeActive() {
        guard let backgroundedAt = self.backgroundedAt else {
            return
        }
        self.backgroundedAt = nil
        let elapsed = Double(WGChatLock.now() &- backgroundedAt) / 1_000_000_000.0
        if WGSecuritySettings.chatLockAutolock.value && elapsed >= WGSecuritySettings.chatLockAutolockSeconds {
            self.lockEverything()
        }
        self.pruneScreens()
        for screen in self.screens.values where screen.cover != nil {
            guard let controller = screen.controller else {
                continue
            }
            let account = screen.context.account.id.wg
            if screen.isPreview {
                continue
            }
            if !self.needsUnlock(account: account, peerId: screen.peerId, controller: controller) {
                self.uncover(screen)
            } else if controller.view.window != nil {
                self.ask(screen)
            }
        }
    }
}
