import Foundation
import TelegramCore
import WGCore

/// The part of WGMessages that the extensions (notification service, share) also link: settings with
/// `.extensions`, NSE handlers, attribute declarations. Owner: W2-3.
public enum WGMessagesShared {
    /// Called from `WGFeaturesShared.registerForApp()` and `.registerForExtension()`; check
    /// `WGCore.environment?.process` for what only one of them needs.
    public static func register() {
        WGMessagesSettings.declare()
        // The verbatim marker can reach Postbox on paths that skip the outgoing transformer: every
        // process that opens an account must be able to decode it.
        WGMessageAttributeHooks.declareEncodables.register({
            wgDeclareMessagesEncodables()
        })
        // SG-H1 (pinned / mention pushes): the decision is `WGNotificationFilter.decision`.
        WGNotificationServiceHooks.content.register({ content, context in
            guard let mode = WGNotificationFilter.decision(isPinnedMessage: context.isPinnedMessage, isMentionOrReply: context.isMentionOrReply, accountId: context.accountId, peerId: context.peerId) else {
                return
            }
            switch mode {
            case .disabled:
                content.isHidden = true
            case .silent:
                content.isSilent = true
            case .standard:
                break
            }
        })
    }
}
