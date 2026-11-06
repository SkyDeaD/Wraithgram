import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import WGCore
import WGHooks
import WGFeaturesShared

/// «Обходы ограничений»: every predicate is answered once at its source point (copy protection,
/// platform restrictions, capture protection, screenshot notices, sponsored messages, content
/// consumption), so all screens that ask the same question get the same answer. Each handler is a
/// snapshot read; with the toggle off it answers nil and upstream decides.
enum WGRestrictionHandlers {
    static func register() {
        WGRestrictionHooks.copyProtection.register({ subject in
            return WGRestrictionHandlers.copyProtection(subject)
        })
        WGStoryHooks.forwardingDisabled.register({ _ in
            return WGMessagesSettings.copyProtectionBypass.value ? false : nil
        })

        // Forced protection (a feature that hides a chat from screenshots) registers with a lower
        // order and wins; this one only lifts what the server imposed.
        WGChatScreenHooks.captureProtection.register({ request in
            if request.upstreamValue && WGMessagesSettings.screenshotBypass.value {
                return false
            }
            return nil
        }, order: 900)
        WGRestrictionHooks.reportScreenshot.register({ _ in
            return WGMessagesSettings.screenshotBypass.value ? false : nil
        })
        // A screenshot in the viewer of kept view-once / timer media tells the sender that it was
        // opened: with «Не сжигать» the sender learns that only from «Отметить открытым».
        WGRestrictionHooks.reportMediaScreenshot.register({ message in
            if WGMessagesSettings.keepSelfDestructingMedia.value && WGRestrictionHandlers.isSelfDestructing(message) {
                return false
            }
            return nil
        })

        // View-once / timer media: not consumed at all — no "opened" flag, no countdown, nothing
        // sent to the other side (the explicit «Прочитать» of the ghost mode is a separate action).
        WGPresenceHooks.consumeContent.register({ request in
            guard WGMessagesSettings.keepSelfDestructingMedia.value else {
                return nil
            }
            return WGRestrictionHandlers.isSelfDestructing(request.message) ? false : nil
        })
        // …and shown as ordinary media, as the old client did: no blur, the regular gallery, save
        // and forward (a forward goes as a copy, WGForwardCopy — the server refuses to forward
        // self-destructing media). Asked only for self-destructing media; the fire mark beside the
        // time (WGMessageDecorations) still tells it apart.
        WGRestrictionHooks.secretMediaDisplay.register({ _ in
            return WGMessagesSettings.keepSelfDestructingMedia.value ? false : nil
        })
        // Forwards the server refuses (protected content with the bypass, kept self-destructing media)
        // go as copies on every path: the share sheet of a channel post, profile media, search, the
        // forward panel. The chat's own forward flow converts before it gets here (with its alerts).
        WGOutgoingHooks.forwardCopies.register({ account, messages in
            return WGRestrictionHandlers.forwardCopies(account: account, messages: messages)
        })

        WGChatScreenHooks.showsAdMessages.register({ _, _ in
            return WGMessagesSettings.blockAds.value ? false : nil
        })

        WGRestrictionHooks.peerRestriction.register({ _ in
            return WGMessagesSettings.contentRestrictionsBypass.value ? false : nil
        })
        WGRestrictionHooks.messageRestriction.register({ _ in
            return WGMessagesSettings.contentRestrictionsBypass.value ? false : nil
        })
    }

    /// nil when no setting can make a forward a copy; otherwise the batch with the forwards that need it
    /// replaced by copies (`WGForwardCopy`), the others as they are.
    static func forwardCopies(account: Account, messages: [EnqueueMessage]) -> Signal<[EnqueueMessage], NoError>? {
        guard WGMessagesSettings.copyProtectionBypass.value || WGMessagesSettings.keepSelfDestructingMedia.value else {
            return nil
        }
        var sourceIds: [MessageId] = []
        var options: ForwardOptionsMessageAttribute?
        for message in messages {
            if case let .forward(source, _, _, attributes, _) = message {
                sourceIds.append(source)
                if options == nil {
                    options = attributes.first(where: { $0 is ForwardOptionsMessageAttribute }) as? ForwardOptionsMessageAttribute
                }
            }
        }
        if sourceIds.isEmpty {
            return nil
        }
        let hideNames = options?.hideNames ?? false
        let hideCaptions = options?.hideCaptions ?? false
        return account.postbox.transaction { transaction -> [Message] in
            return sourceIds.compactMap { transaction.getMessage($0) }
        }
        |> mapToSignal { sources -> Signal<[EnqueueMessage], NoError> in
            guard WGForwardCopy.needsCopy(sources) else {
                return .single(messages)
            }
            return WGForwardCopy.convert(messages, sources: sources, account: account, hideNames: hideNames, hideCaptions: hideCaptions)
            |> map { result -> [EnqueueMessage] in
                return result.messages
            }
        }
    }

    static func copyProtection(_ subject: WGCopyProtectionSubject) -> Bool? {
        guard WGMessagesSettings.copyProtectionBypass.value else {
            return nil
        }
        // Admins and owners too: their settings screens read the raw flag
        // (`ChannelVisibilityController`), so the bypass never hides the real state there.
        switch subject {
        case .peer, .message, .peerData:
            return false
        }
    }

    /// View-once and short-timer media — photo, video, voice, round video — in cloud and secret
    /// chats (`containsSecretMedia`: a timer of a minute or less, or view once). Long chat-wide
    /// timers of secret chats are not «исчезающие медиа» and keep working. The raw answer: with
    /// the toggle on, `containsSecretMedia` itself says false (`secretMediaDisplay` above).
    static func isSelfDestructing(_ message: Message) -> Bool {
        return message.wgRawContainsSecretMedia
    }
}
