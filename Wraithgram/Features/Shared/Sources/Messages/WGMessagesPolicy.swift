import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import WGCore

/// Ready answers for upstream modules that sit below the feature layer (the chat nodes,
/// ChatPresentationInterfaceState, TranslateUI, TelegramUI's own files). Every answer is a snapshot
/// read (WGCore), safe on any thread and in layout; the call sites are one-line `// WRAITH:` forks.
public enum WGMessagesPolicy {
    // MARK: Chats

    /// Empty private chats show the plain «no messages here» placeholder (and nothing is preloaded).
    public static var hidesGreetingSticker: Bool {
        return WGMessagesSettings.hideGreetingSticker.value
    }

    /// The Mute / Unmute button at the bottom of a broadcast channel the user is subscribed to.
    public static var hidesChannelBottomButton: Bool {
        return WGMessagesSettings.hideChannelBottomButton.value
    }

    /// «Pull up for the next unread channel». One switch with the topics since 2026-10-27; the two
    /// answers stay apart because their call sites in the chat are apart.
    public static var allowsScrollToNextChannel: Bool {
        return !WGMessagesSettings.disableScrollToNext.value
    }

    /// «Pull up for the next topic» in forums (the same switch as the channels).
    public static var allowsScrollToNextTopic: Bool {
        return !WGMessagesSettings.disableScrollToNext.value
    }

    /// The «Send as» avatar button in the composer.
    public static var hidesSendAsButton: Bool {
        return WGMessagesSettings.hideSendAsButton.value
    }

    /// The channel is in the local creator mode on this account: the composer opens, messages stay
    /// on this device (see WGLocalCreatorMode in WGMessages).
    public static func isLocalCreatorMode(accountId: AccountRecordId, peerId: PeerId) -> Bool {
        let channels = WGMessagesSettings.localCreatorChannels.value(for: accountId.wg)
        if channels.isEmpty {
            return false
        }
        return channels.contains(peerId.wgKey)
    }

    // MARK: Restrictions

    /// «Анти-спойлер» for places that are not message cells (input panels, notifications, shared
    /// media); cells get it from the message decoration.
    public static var revealsSpoilers: Bool {
        return WGMessagesSettings.revealSpoilers.value
    }

    /// `entities` without spoilers when the anti-spoiler is on.
    public static func visibleEntities(_ entities: [MessageTextEntity]) -> [MessageTextEntity] {
        if !WGMessagesSettings.revealSpoilers.value {
            return entities
        }
        return entities.filter { entity in
            if case .Spoiler = entity.type {
                return false
            }
            return true
        }
    }

    public static var bypassesCopyProtection: Bool {
        return WGMessagesSettings.copyProtectionBypass.value
    }

    // MARK: Translation

    public static var translationService: WGTranslationServiceKind {
        let kind = WGTranslationServiceKind(rawValue: WGMessagesSettings.translationService.value) ?? .telegram
        switch kind {
        case .telegram:
            return .telegram
        case .google:
            // A third-party service is used only after the user accepted the notice.
            return WGMessagesSettings.translationThirdPartyAccepted.value ? .google : .telegram
        case .system:
            if #available(iOS 18.0, *) {
                return .system
            } else {
                return .telegram
            }
        }
    }

    /// Chat translation (the bar, «Translate entire chat», the Translate button) works without
    /// Telegram Premium. Always, as in Swiftgram (W6-SGD, owner's decision 2026-10-29): with Google /
    /// the system service the providers of WGMessages translate; with Telegram's server a chat of an
    /// account without Premium goes through Telegram's text translation
    /// (`translateChatWithoutPremium`), never through a third party.
    public static var translatesChatsWithoutPremium: Bool {
        return true
    }

    /// The chat translation bar's request (`translateMessageIds`, TranslateUI) for an account without
    /// Premium when Telegram's server is the service: Telegram translates whole chats (by message ids)
    /// for Premium only, so the messages are sent as texts (`messages.translateText` with `text`, which
    /// Telegram serves without Premium), up to 20 per request, one request after another — what
    /// Swiftgram does (`translateMessagesViaText`). nil: upstream's request (Premium, or Google / the
    /// system service, which `WGTranslationHooks.translateMessages` answers).
    public static func translateChatWithoutPremium(account: Account, isPremium: Bool, messageIds: [MessageId], toLang: String) -> Signal<Never, NoError>? {
        if isPremium || messageIds.isEmpty || WGMessagesPolicy.translationService != .telegram {
            return nil
        }
        let messages = TelegramEngine(account: account).messages
        return WGStoredMessagesTranslation.translate(postbox: account.postbox, messageIds: messageIds, toLang: toLang, maxTextsPerCall: 20, translateTexts: { texts in
            return messages.translate(texts: texts, toLang: toLang)
        })
        |> ignoreValues
        |> `catch` { _ -> Signal<Never, NoError> in
            return .complete()
        }
    }

    /// The language outgoing messages of this chat are translated to, if the user set one.
    public static func outgoingLanguage(accountId: AccountRecordId, peerId: PeerId) -> String? {
        let values = WGMessagesSettings.outgoingLanguages.value(for: accountId.wg)
        if values.isEmpty {
            return nil
        }
        return values[peerId.wgKey.stringValue]
    }

    public static func setOutgoingLanguage(_ language: String?, accountId: AccountRecordId, peerId: PeerId) {
        var values = WGMessagesSettings.outgoingLanguages.value(for: accountId.wg)
        values[peerId.wgKey.stringValue] = language
        WGMessagesSettings.outgoingLanguages.set(values, for: accountId.wg)
    }
}
