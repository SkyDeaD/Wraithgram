import Foundation
import Postbox
import TelegramCore
import WGCore

/// SG-H1: pushes about pinned messages and about mentions / replies — «как обычно / без звука /
/// не присылать», with per-chat exceptions (the old client read the exceptions in the extension but
/// nothing ever wrote them; the menu now does, see WGNotificationExceptionsScreen in WGMessages).
///
/// Runs in the notification service extension: settings are App Group / account scoped with
/// `.extensions`. `WGMessagesShared.register()` applies it on `WGNotificationServiceHooks.content`
/// (`WGNotificationContext.isPinnedMessage` / `.isMentionOrReply`, `WGNotificationContent.isSilent`).
public enum WGNotificationFilter {
    public enum Kind {
        case pinnedMessage
        case mentionOrReply
    }

    /// The mode for this push: the chat's exception first, then the global choice.
    public static func mode(kind: Kind, accountId: AccountRecordId?, peerId: PeerId?) -> WGNotificationDeliveryMode {
        let globalValue: String
        let exceptions: [String: String]
        switch kind {
        case .pinnedMessage:
            globalValue = WGMessagesSettings.pinnedNotifications.value
            exceptions = accountId.flatMap { WGMessagesSettings.pinnedNotificationExceptions.value(for: $0.wg) } ?? [:]
        case .mentionOrReply:
            globalValue = WGMessagesSettings.mentionNotifications.value
            exceptions = accountId.flatMap { WGMessagesSettings.mentionNotificationExceptions.value(for: $0.wg) } ?? [:]
        }
        if let peerId, let value = exceptions[peerId.wgKey.stringValue], let mode = WGNotificationDeliveryMode(rawValue: value) {
            return mode
        }
        return WGNotificationDeliveryMode(rawValue: globalValue) ?? .standard
    }

    /// What to do with a push of the given kinds: `nil` = deliver unchanged.
    public static func decision(isPinnedMessage: Bool, isMentionOrReply: Bool, accountId: AccountRecordId?, peerId: PeerId?) -> WGNotificationDeliveryMode? {
        var result: WGNotificationDeliveryMode?
        if isPinnedMessage {
            result = WGNotificationFilter.mode(kind: .pinnedMessage, accountId: accountId, peerId: peerId)
        }
        if isMentionOrReply {
            let mode = WGNotificationFilter.mode(kind: .mentionOrReply, accountId: accountId, peerId: peerId)
            result = WGNotificationFilter.stricter(result, mode)
        }
        if result == .standard {
            return nil
        }
        return result
    }

    /// The same decision for the banner the app shows itself while it is open (no push involved):
    /// a «pinned» service message, a mention or a reply to the account (the message carries a
    /// personal-mention mark, the in-app counterpart of the push's `mention`).
    public static func inAppDecision(message: Message, accountId: AccountRecordId) -> WGNotificationDeliveryMode? {
        var isPinnedMessage = false
        for media in message.media {
            if let action = media as? TelegramMediaAction, case .pinnedMessageUpdated = action.action {
                isPinnedMessage = true
            }
        }
        let isMentionOrReply = message.attributes.contains(where: { $0 is ConsumablePersonalMentionMessageAttribute })
        if !isPinnedMessage && !isMentionOrReply {
            return nil
        }
        return WGNotificationFilter.decision(isPinnedMessage: isPinnedMessage, isMentionOrReply: isMentionOrReply, accountId: accountId, peerId: message.id.peerId)
    }

    private static func stricter(_ lhs: WGNotificationDeliveryMode?, _ rhs: WGNotificationDeliveryMode) -> WGNotificationDeliveryMode {
        guard let lhs else {
            return rhs
        }
        func rank(_ mode: WGNotificationDeliveryMode) -> Int {
            switch mode {
            case .standard:
                return 0
            case .silent:
                return 1
            case .disabled:
                return 2
            }
        }
        return rank(lhs) >= rank(rhs) ? lhs : rhs
    }
}
