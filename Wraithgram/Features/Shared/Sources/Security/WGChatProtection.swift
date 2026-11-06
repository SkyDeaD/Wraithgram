import Foundation
import Postbox
import TelegramCore
import WGCore

/// Which chats are protected — configuration only (the app's unlock state is WGSecurity's). One
/// answer for every place that must not show a protected chat's content: the chat list preview and
/// the search (app), the push text (notification service), in-app banners, the widget and Siri.
public enum WGChatProtection {
    /// The chat is protected by «Пароль на чаты» or belongs to the locked-away secret folder.
    /// Snapshot reads only: layout paths, signal maps, the extensions.
    public static func isProtected(account: WGAccountID, peerId: PeerId) -> Bool {
        let key = peerId.wgKey
        if WGSecuritySharedSettings.chatLockEnabled.value {
            if WGSecuritySharedSettings.chatLockAllChats.value {
                return WGChatProtection.isLockable(peerId)
            }
            if WGSecuritySharedSettings.chatLockPeers.value(for: account).contains(key) {
                return true
            }
        }
        return WGSecuritySharedSettings.secretFolderPeers.value(for: account).contains(key)
    }

    /// «Все чаты» means every chat except Telegram's service notifications (777000): login codes must
    /// stay readable in their pushes.
    public static func isLockable(_ peerId: PeerId) -> Bool {
        if peerId.namespace == Namespaces.Peer.CloudUser && peerId.id._internalGetInt64Value() == 777000 {
            return false
        }
        return true
    }

    /// Notification service, Siri, in-app banners, widget (WGContentPrivacyHooks.hidesContent) and the
    /// push text (WGNotificationServiceHooks.content).
    static func register() {
        WGContentPrivacyHooks.hidesContent.register({ accountId, peerId in
            return WGChatProtection.isProtected(account: accountId.wg, peerId: peerId)
        })
        WGNotificationServiceHooks.content.register({ content, context in
            guard let accountId = context.accountId, let peerId = context.peerId, !content.isHidden else {
                return
            }
            if !WGChatProtection.isProtected(account: accountId.wg, peerId: peerId) {
                return
            }
            WGChatProtection.adoptAppLanguage()
            content.body = WGStrings.Security.Notifications.hiddenText
            content.hidesAttachments = true
        }, order: 10000)
    }

    /// The extension does not learn Telegram's language from a PresentationData; the app leaves it in
    /// `extensionLanguage` (the user's manual Wraithgram language still wins inside WGLocalization).
    private static func adoptAppLanguage() {
        if WGCore.environment?.process.isApp ?? true {
            return
        }
        let code = WGSecuritySharedSettings.extensionLanguage.value
        if !code.isEmpty {
            WGLocalization.shared.setTelegramLanguageCode(code)
        }
    }
}
