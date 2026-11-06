import Foundation
import WGCore

// Settings of the «Сообщения» zone (W2-3). Declared here, in the light shared module, because
// upstream modules below the feature layer (TranslateUI, ChatPresentationInterfaceState, the chat
// nodes, TelegramUI) and the notification service read some of them. Each is declared once.
// Toggles default to off; `messageMenu.*` children only matter while their master is on.

public enum WGTranslationServiceKind: String {
    case telegram
    case google
    case system
}

public enum WGNotificationDeliveryMode: String {
    case standard = "default"
    case silent
    case disabled
}

public enum WGMessagesSettings {
    // MARK: Restrictions («Обходы ограничений»)
    public static let copyProtectionBypass = WGSetting<Bool>("restrictions.copyProtectionBypass", default: false)
    public static let forwardAttribution = WGSetting<Bool>("restrictions.forwardAttribution", default: false)
    public static let keepSelfDestructingMedia = WGSetting<Bool>("restrictions.keepSelfDestructingMedia", default: false)
    public static let screenshotBypass = WGSetting<Bool>("restrictions.screenshotBypass", default: false)
    public static let blockAds = WGSetting<Bool>("restrictions.blockAds", default: false)
    public static let contentRestrictionsBypass = WGSetting<Bool>("restrictions.contentRestrictionsBypass", default: false)
    public static let revealSpoilers = WGSetting<Bool>("restrictions.revealSpoilers", default: false)

    // MARK: Sending («Отправка»)
    public static let wordReplacement = WGSetting<Bool>("sending.wordReplacement", default: false)
    public static let antiCaps = WGSetting<Bool>("sending.antiCaps", default: false)
    public static let hyperlinkSpoof = WGSetting<Bool>("sending.hyperlinkSpoof", default: false)
    /// The profile every outgoing text links to; per account (a peer of that account).
    public static let hyperlinkTarget = WGAccountSetting<WGPeerKey?>("sending.hyperlinkTarget", default: nil)
    public static let autoQuoteReply = WGSetting<Bool>("sending.autoQuoteReply", default: false)
    /// Sub-option of the quote: comments under channel posts are answered without a quote.
    public static let autoQuoteSkipComments = WGSetting<Bool>("sending.autoQuoteSkipComments", default: true)
    public static let anonymousStickers = WGSetting<Bool>("sending.anonymousStickers", default: false)
    public static let sendWithoutViaBot = WGSetting<Bool>("sending.sendWithoutViaBot", default: false)
    /// Sub-option: keep the bot's caption when the result is re-sent as a normal message.
    public static let keepInlineBotCaption = WGSetting<Bool>("sending.keepInlineBotCaption", default: true)
    public static let sendOnReturn = WGSetting<Bool>("sending.sendOnReturn", default: false)
    public static let hideSendAsButton = WGSetting<Bool>("sending.hideSendAsButton", default: false)

    // MARK: Translation («Перевод»)
    public static let translationService = WGSetting<String>("translation.service", default: WGTranslationServiceKind.telegram.rawValue)
    /// The user saw and accepted the notice that texts go to a third-party service.
    public static let translationThirdPartyAccepted = WGSetting<Bool>("translation.thirdPartyAccepted", default: false, flags: [.noExport])
    public static let quickTranslateButton = WGSetting<Bool>("translation.quickButton", default: false)
    public static let translateBeforeSending = WGSetting<Bool>("translation.beforeSending", default: false)
    public static let translateBeforeSendingLanguage = WGSetting<String>("translation.beforeSendingLanguage", default: "en")
    /// Outgoing language per chat (peer key → language code); per account.
    public static let outgoingLanguages = WGAccountSetting<[String: String]>("translation.outgoingLanguages", default: [:])
    public static let photoTranslation = WGSetting<Bool>("translation.photo", default: false)

    // MARK: Message menu and gestures («Меню и жесты»)
    // Defaults follow Swiftgram (W6-SGD, owner's decision 2026-10-29): its menu always has «В Избранное»,
    // «Без автора» and «Ограничить» (`contextShow…` = true), so the custom menu and these items are on;
    // Telegram's own items stay shown. Turned-off items are hidden — no «Wraithgram» submenu, and no
    // «Выбрать от автора» (both removed by the owner, 2026-10-29).
    public static let customMessageMenu = WGSetting<Bool>("messageMenu.custom", default: true)
    public static let menuShowReply = WGSetting<Bool>("messageMenu.reply", default: true)
    public static let menuShowPin = WGSetting<Bool>("messageMenu.pin", default: true)
    public static let menuShowReport = WGSetting<Bool>("messageMenu.report", default: true)
    public static let menuShowRestrict = WGSetting<Bool>("messageMenu.restrict", default: true)
    public static let menuShowSaveMedia = WGSetting<Bool>("messageMenu.saveMedia", default: true)
    public static let menuShowReplies = WGSetting<Bool>("messageMenu.replies", default: true)
    public static let menuSaveToCloud = WGSetting<Bool>("messageMenu.saveToCloud", default: true)
    public static let menuForwardWithoutAuthor = WGSetting<Bool>("messageMenu.forwardWithoutAuthor", default: true)
    public static let doubleTapToEdit = WGSetting<Bool>("gestures.doubleTapToEdit", default: false)
    public static let disableVideoPipSwipe = WGSetting<Bool>("gestures.disableVideoPipSwipe", default: false)

    // MARK: Chats («Чаты»)
    // «Безлимитные закрепы» have no setting: always on (owner's decision 2026-10-22); their per-account
    // state lives in the account's Postbox (WGMessages, `WGPinnedTailStore`).
    public static let unlimitedSearchHistory = WGSetting<Bool>("chats.unlimitedSearchHistory", default: false)
    public static let hideGreetingSticker = WGSetting<Bool>("chats.hideGreetingSticker", default: false)
    public static let keywordFilter = WGSetting<Bool>("chats.keywordFilter", default: false)
    public static let keywords = WGSetting<[String]>("chats.keywords", default: [])
    public static let hideChannelBottomButton = WGSetting<Bool>("chats.hideChannelBottomButton", default: false)
    /// «Без перехода к следующему каналу и теме»: one switch since 2026-10-27 (was one per channel / topic).
    public static let disableScrollToNext = WGSetting<Bool>("chats.disableScrollToNext", default: false)
    public static let disableDeleteEffect = WGSetting<Bool>("chats.disableDeleteEffect", default: false)
    public static let hideRecordButton = WGSetting<Bool>("chats.hideRecordButton", default: false)
    /// Channels shown as if the user created them («локальный режим»); per account.
    public static let localCreatorChannels = WGAccountSetting<Set<WGPeerKey>>("chats.localCreatorChannels", default: [])

    // MARK: Notifications («Уведомления», read by the notification service)
    public static let pinnedNotifications = WGSetting<String>("notifications.pinned", default: WGNotificationDeliveryMode.standard.rawValue, scope: .appGroup, flags: [.extensions])
    public static let mentionNotifications = WGSetting<String>("notifications.mentions", default: WGNotificationDeliveryMode.standard.rawValue, scope: .appGroup, flags: [.extensions])
    /// Per chat (peer key → mode), per account.
    public static let pinnedNotificationExceptions = WGAccountSetting<[String: String]>("notifications.pinnedExceptions", default: [:], flags: [.extensions])
    public static let mentionNotificationExceptions = WGAccountSetting<[String: String]>("notifications.mentionExceptions", default: [:], flags: [.extensions])

    /// Touches every declaration so the registry knows them before export, search and migrations.
    static func declare() {
        let _ = WGMessagesSettings.copyProtectionBypass
        let _ = WGMessagesSettings.forwardAttribution
        let _ = WGMessagesSettings.keepSelfDestructingMedia
        let _ = WGMessagesSettings.screenshotBypass
        let _ = WGMessagesSettings.blockAds
        let _ = WGMessagesSettings.contentRestrictionsBypass
        let _ = WGMessagesSettings.revealSpoilers
        let _ = WGMessagesSettings.wordReplacement
        let _ = WGMessagesSettings.antiCaps
        let _ = WGMessagesSettings.hyperlinkSpoof
        let _ = WGMessagesSettings.hyperlinkTarget
        let _ = WGMessagesSettings.autoQuoteReply
        let _ = WGMessagesSettings.autoQuoteSkipComments
        let _ = WGMessagesSettings.anonymousStickers
        let _ = WGMessagesSettings.sendWithoutViaBot
        let _ = WGMessagesSettings.keepInlineBotCaption
        let _ = WGMessagesSettings.sendOnReturn
        let _ = WGMessagesSettings.hideSendAsButton
        let _ = WGMessagesSettings.translationService
        let _ = WGMessagesSettings.translationThirdPartyAccepted
        let _ = WGMessagesSettings.quickTranslateButton
        let _ = WGMessagesSettings.translateBeforeSending
        let _ = WGMessagesSettings.translateBeforeSendingLanguage
        let _ = WGMessagesSettings.outgoingLanguages
        let _ = WGMessagesSettings.photoTranslation
        let _ = WGMessagesSettings.customMessageMenu
        let _ = WGMessagesSettings.menuShowReply
        let _ = WGMessagesSettings.menuShowPin
        let _ = WGMessagesSettings.menuShowReport
        let _ = WGMessagesSettings.menuShowRestrict
        let _ = WGMessagesSettings.menuShowSaveMedia
        let _ = WGMessagesSettings.menuShowReplies
        let _ = WGMessagesSettings.menuSaveToCloud
        let _ = WGMessagesSettings.menuForwardWithoutAuthor
        let _ = WGMessagesSettings.doubleTapToEdit
        let _ = WGMessagesSettings.disableVideoPipSwipe
        let _ = WGMessagesSettings.unlimitedSearchHistory
        let _ = WGMessagesSettings.hideGreetingSticker
        let _ = WGMessagesSettings.keywordFilter
        let _ = WGMessagesSettings.keywords
        let _ = WGMessagesSettings.hideChannelBottomButton
        let _ = WGMessagesSettings.disableScrollToNext
        let _ = WGMessagesSettings.disableDeleteEffect
        let _ = WGMessagesSettings.hideRecordButton
        let _ = WGMessagesSettings.localCreatorChannels
        let _ = WGMessagesSettings.pinnedNotifications
        let _ = WGMessagesSettings.mentionNotifications
        let _ = WGMessagesSettings.pinnedNotificationExceptions
        let _ = WGMessagesSettings.mentionNotificationExceptions
    }
}
