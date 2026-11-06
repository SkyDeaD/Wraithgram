import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import AvatarNode
import WGCore
import WGHooks

// Uses `WGSettingsTabDynamicRow`, `WGSettingsTabHooks.dynamicRows`, `.itemOrder`, `.invalidate()`
// (WGHooks/UI/Settings).

/// Shortcuts in Telegram's Settings tab (chats, mini apps, sites) and the order of its rows.
/// The tab is rebuilt from cached values only: peers, avatars and favicons arrive through one
/// subscription per account and call `invalidate()` when something visible changed.
enum WGSettingsTabPending {
    private static var peerCaches: [WGAccountID: [EnginePeer.Id: EnginePeer]] = [:]
    private static var iconCache: [String: UIImage] = [:]
    private static var iconDisposables: [String: Disposable] = [:]
    private static var peerDisposables: [WGAccountID: Disposable] = [:]
    private static var listDisposables: [WGAccountID: Disposable] = [:]
    /// The avatar shape the cached peer icons were drawn with; a change drops them.
    private static var iconShape: WGAvatarShape?

    static func register() {
        WGSettingsTabHooks.dynamicRows.register({ context, presentationData in
            return WGSettingsTabPending.rows(context: context, presentationData: presentationData)
        })

        // A logged-out account's subscriptions, peers and icons go with it: nothing here may keep its
        // `Account` (Postbox, network) alive until the process ends.
        WGAccountHooks.accountWillBeRemoved.register({ id in
            let accountID = id.wg
            Queue.mainQueue().async {
                WGSettingsTabPending.dropAccount(accountID)
            }
        })

        WGSettingsTabHooks.itemOrder.register({ section, ids, _ in
            let order = InterfaceSnapshots.shared.current.settingsItemsOrder
            if order.isEmpty {
                return ids
            }
            let ordered = WGSettingsTabLayout.orderedItems(section: section, order: order)
            if ordered.isEmpty {
                return ids
            }
            var result: [AnyHashable] = []
            for item in ordered {
                if let itemId = item.itemId, ids.contains(AnyHashable(itemId)) {
                    result.append(AnyHashable(itemId))
                }
            }
            for id in ids where !result.contains(id) {
                result.append(id)
            }
            return result
        })

        InterfaceSnapshots.shared.settingsTabChanged = {
            WGSettingsTabHooks.invalidate()
        }
    }

    private static func rows(context: AccountContext, presentationData: PresentationData) -> [WGSettingsTabDynamicRow] {
        assert(Thread.isMainThread)
        let accountID = context.account.id.wg
        WGSettingsTabPending.ensureSubscriptions(context: context)
        let shortcuts = InterfaceSettings.settingsShortcuts.value(for: accountID)
        if shortcuts.isEmpty {
            return []
        }
        let peers = WGSettingsTabPending.peerCaches[accountID] ?? [:]
        // «Скругление углов» changes how the icons are drawn: drop the ones drawn with another shape.
        let shape = WGAvatarHooks.currentShape()
        if WGSettingsTabPending.iconShape != shape {
            if WGSettingsTabPending.iconShape != nil {
                WGSettingsTabPending.dropIcons(prefix: "peer:")
            }
            WGSettingsTabPending.iconShape = shape
        }
        var result: [WGSettingsTabDynamicRow] = []
        for shortcut in shortcuts {
            let action: (AccountContext, NavigationController?) -> Void = { context, navigationController in
                WGShortcutActions.open(shortcut, context: context, navigationController: navigationController)
            }
            switch shortcut.kind {
            case .chat, .miniApp:
                guard let peerKey = shortcut.peer, let peer = peers[EnginePeer.Id(wgKey: peerKey)] else {
                    continue
                }
                let iconKey = "peer:\(accountID)|\(peer.id.toInt64())|\(peer.smallProfileImage?.resource.id.stringRepresentation ?? "")|\(shape.squareAvatars)-\(shape.cornerFraction)-\(shape.roundForums)"
                WGSettingsTabPending.loadIcon(key: iconKey, signal: peerAvatarCompleteImage(account: context.account, peer: peer, size: CGSize(width: 30.0, height: 30.0)))
                result.append(WGSettingsTabDynamicRow(
                    id: shortcut.id,
                    title: peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder),
                    label: shortcut.kind == .miniApp ? WGStrings.Interface.SettingsTab.miniAppBadge : nil,
                    icon: WGSettingsTabPending.iconCache[iconKey],
                    action: action
                ))
            case .site:
                guard let url = shortcut.url else {
                    continue
                }
                let host = WGSiteShortcut.displayHost(of: url)
                let iconKey = "site:" + url
                WGSettingsTabPending.loadIcon(key: iconKey, signal: WGFaviconStore.shared.icon(url: url, size: 30.0))
                result.append(WGSettingsTabDynamicRow(
                    id: shortcut.id,
                    title: shortcut.title.flatMap { $0.isEmpty ? nil : $0 } ?? host,
                    label: WGStrings.Interface.SettingsTab.siteBadge,
                    icon: WGSettingsTabPending.iconCache[iconKey] ?? WGFaviconStore.monogram(for: host, size: 30.0),
                    action: action
                ))
            }
        }
        return result
    }

    /// Starts loading an icon once per key; its arrival rebuilds the tab.
    private static func loadIcon(key: String, signal: Signal<UIImage?, NoError>) {
        if WGSettingsTabPending.iconCache[key] != nil || WGSettingsTabPending.iconDisposables[key] != nil {
            return
        }
        WGSettingsTabPending.iconDisposables[key] = (signal
        |> deliverOnMainQueue).start(next: { image in
            guard let image else {
                return
            }
            WGSettingsTabPending.iconCache[key] = image
            WGSettingsTabHooks.invalidate()
        })
    }

    private static func dropIcons(prefix: String) {
        for key in Array(WGSettingsTabPending.iconDisposables.keys) where key.hasPrefix(prefix) {
            WGSettingsTabPending.iconDisposables.removeValue(forKey: key)?.dispose()
        }
        for key in Array(WGSettingsTabPending.iconCache.keys) where key.hasPrefix(prefix) {
            WGSettingsTabPending.iconCache.removeValue(forKey: key)
        }
    }

    private static func dropAccount(_ accountID: WGAccountID) {
        WGSettingsTabPending.peerDisposables.removeValue(forKey: accountID)?.dispose()
        WGSettingsTabPending.listDisposables.removeValue(forKey: accountID)?.dispose()
        WGSettingsTabPending.peerCaches.removeValue(forKey: accountID)
        WGSettingsTabPending.dropIcons(prefix: "peer:\(accountID)|")
    }

    /// One subscription per account: shortcuts → their peers; the list itself rebuilds the tab.
    /// The engine is held weakly: an account without shortcuts is not kept by the subscription at all,
    /// and the peer subscription of one with shortcuts ends at its logout (`dropAccount`).
    private static func ensureSubscriptions(context: AccountContext) {
        let accountID = context.account.id.wg
        if WGSettingsTabPending.peerDisposables[accountID] != nil {
            return
        }
        let engine = context.engine
        let signal = InterfaceSettings.settingsShortcuts.signal(for: accountID)
        |> map { shortcuts -> [EnginePeer.Id] in
            return shortcuts.compactMap { shortcut -> EnginePeer.Id? in
                guard shortcut.kind != .site, let peerKey = shortcut.peer else {
                    return nil
                }
                return EnginePeer.Id(wgKey: peerKey)
            }
        }
        |> distinctUntilChanged
        |> mapToSignal { [weak engine] peerIds -> Signal<[EnginePeer.Id: EnginePeer], NoError> in
            guard let engine, !peerIds.isEmpty else {
                return .single([:])
            }
            return engine.data.subscribe(EngineDataMap(peerIds.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) }))
            |> map { peers -> [EnginePeer.Id: EnginePeer] in
                var result: [EnginePeer.Id: EnginePeer] = [:]
                for (id, maybePeer) in peers {
                    if let peer = maybePeer {
                        result[id] = peer
                    }
                }
                return result
            }
        }
        |> deliverOnMainQueue
        WGSettingsTabPending.peerDisposables[accountID] = signal.start(next: { peers in
            let previous = WGSettingsTabPending.peerCaches[accountID]
            WGSettingsTabPending.peerCaches[accountID] = peers
            if let previous, Set(previous.keys) == Set(peers.keys), WGSettingsTabPending.sameTitles(previous, peers) {
                return
            }
            WGSettingsTabHooks.invalidate()
        })
        // Shortcut list changes (add, remove, rename a site) rebuild the tab too.
        WGSettingsTabPending.listDisposables[accountID] = (InterfaceSettings.settingsShortcuts.signal(for: accountID)
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { _ in
            WGSettingsTabHooks.invalidate()
        })
    }

    private static func sameTitles(_ lhs: [EnginePeer.Id: EnginePeer], _ rhs: [EnginePeer.Id: EnginePeer]) -> Bool {
        for (id, peer) in lhs {
            guard let other = rhs[id] else {
                return false
            }
            if peer.compactDisplayTitle != other.compactDisplayTitle || peer.smallProfileImage?.resource.id != other.smallProfileImage?.resource.id {
                return false
            }
        }
        return true
    }
}
