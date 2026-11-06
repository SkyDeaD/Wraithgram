import Foundation
import WGCore

// Settings of the Swiftgram-parity features (W5-SG). Declared in the light shared module because the
// upstream modules below the feature layer read them in their WRAITH call sites (WGExtrasPolicy) and
// the notification service reads `hideAccountInNotifications`. Off = upstream behaviour.
// Defaults follow Swiftgram (owner's decision 2026-10-29, W6-SGD): what Swiftgram does always (or by a
// server flag that is on by default: `ytPip`, `qrLogin`) is on here too, the switch stays; what Swiftgram
// keeps off (`forceSystemSharing`, `hideAccountInNotifications`, the «В историю» tile shown) stays off.
public enum WGExtrasSettings {
    // MARK: Сообщения › Уведомления
    /// 4 h, 8 h and 1 day in the profile's «Уведомления» sheet, besides 1 h and 2 days.
    public static let extraMuteDurations = WGSetting<Bool>("extras.extraMuteDurations", default: true)
    /// A push never names the account it was delivered to, even with several accounts.
    public static let hideAccountInNotifications = WGSetting<Bool>("extras.hideAccountInNotifications", default: false, scope: .appGroup, flags: [.extensions])

    // MARK: Сообщения › Чаты
    /// An in-chat search the server found nothing for looks for the text inside words of the
    /// messages already on this device.
    public static let searchPartialWords = WGSetting<Bool>("extras.searchPartialWords", default: true)

    // MARK: Отправка › Ввод
    /// A long press on a mention suggestion inserts it followed by « @», so the next list opens.
    public static let mentionChain = WGSetting<Bool>("extras.mentionChain", default: true)
    /// No «Удерживайте, чтобы записать» tooltip after a tap on the microphone / camera button.
    public static let noRecordTooltip = WGSetting<Bool>("extras.noRecordTooltip", default: true)

    // MARK: Меню и жесты › Ссылки и «Поделиться»
    /// A tap on the picture of a link preview opens the picture, not the link.
    public static let linkPreviewOpensMedia = WGSetting<Bool>("extras.linkPreviewOpensMedia", default: true)
    /// «Переслать» and «Поделиться» in the menu of a long-pressed link.
    public static let linkMenuShare = WGSetting<Bool>("extras.linkMenuShare", default: true)
    /// Links in the description of a profile are tappable without Premium.
    public static let bioLinks = WGSetting<Bool>("extras.bioLinks", default: true)
    /// «Safari в приложении» and «Системный браузер» in Telegram's «Браузер» settings.
    public static let moreBrowsers = WGSetting<Bool>("extras.moreBrowsers", default: true)
    /// Every «Поделиться» opens the iOS share sheet at once (where the content may leave the app).
    public static let systemShareSheet = WGSetting<Bool>("extras.systemShareSheet", default: false)
    /// No «В историю» tile in the share sheet.
    public static let hideRepostToStory = WGSetting<Bool>("extras.hideRepostToStory", default: false)

    // MARK: Меню и жесты › Меню и выделение
    // «Данные сообщения (JSON)» was removed (owner, 2026-10-29); its stored value goes
    // (`extras.messageJson.removed.v1`).
    /// «В Избранное» and «Переслать без автора» on the selection panel.
    public static let selectionPanelButtons = WGSetting<Bool>("extras.selectionPanelButtons", default: true)

    // MARK: Сообщения › Группы и каналы
    /// «Администраторы» and «Подписчики» for every admin of a channel, «Администраторы» and
    /// «Участники» for every admin of a group (Telegram asks for the right to ban).
    public static let adminListsForAllAdmins = WGSetting<Bool>("extras.adminListsForAllAdmins", default: true)
    /// «Недавние действия» in a channel's profile and in the «…» menu of groups and channels.
    public static let recentActionsShortcut = WGSetting<Bool>("extras.recentActionsShortcut", default: true)
    /// «Администраторы» in the «…» menu of every group, for every member.
    public static let administratorsMenuItem = WGSetting<Bool>("extras.administratorsMenuItem", default: true)
    /// «Показать закреп» in the «…» menu: brings back a pinned message bar that was closed.
    public static let hiddenPinnedMenuItem = WGSetting<Bool>("extras.hiddenPinnedMenuItem", default: true)
    /// A custom restriction («Ограничить до…») picks a date and a time, not just a day.
    public static let restrictUntilTime = WGSetting<Bool>("extras.restrictUntilTime", default: true)
    /// The text of a restricted chat or message ends with its code («porn-ios»).
    public static let restrictionReasonCode = WGSetting<Bool>("extras.restrictionReasonCode", default: true)
    /// «Обсуждение» in the header of a channel with direct messages, next to «Сообщение» (upstream
    /// shows only «Сообщение» there).
    public static let discussionButton = WGSetting<Bool>("extras.discussionButton", default: true)

    // MARK: Оформление
    /// «Архивировать» / «Вернуть из архива» in the menu of a long-pressed chat.
    public static let archiveInChatMenu = WGSetting<Bool>("extras.archiveInChatMenu", default: true)
    /// No Premium offers (gift, upgrade, annual price) above the chat list.
    public static let hidePremiumOffers = WGSetting<Bool>("extras.hidePremiumOffers", default: true)
    /// Community translations of Telegram (Chinese variants, Japanese, Vietnamese, Hindi, Armenian)
    /// in the language list.
    public static let extraLanguages = WGSetting<Bool>("extras.extraLanguages", default: true)

    // MARK: Медиа › Загрузки и качество
    /// YouTube videos may go to picture-in-picture even when the server turns it off.
    public static let youTubePictureInPicture = WGSetting<Bool>("extras.youTubePictureInPicture", default: true)
    /// 1 GB cache limit and «1 час» for keeping media.
    public static let extraCacheOptions = WGSetting<Bool>("extras.extraCacheOptions", default: true)

    // MARK: Безопасность
    /// «Через 5 секунд» in the passcode auto-lock menu.
    public static let autolockFiveSeconds = WGSetting<Bool>("extras.autolockFiveSeconds", default: true)
    /// IP address and api_id in the details of a session.
    public static let sessionDetails = WGSetting<Bool>("extras.sessionDetails", default: true)
    /// «Подключить устройство» (QR login) even where the server hides it.
    public static let qrLoginAlways = WGSetting<Bool>("extras.qrLoginAlways", default: true)
    /// The alert about a session ended by the server names the likely reasons.
    public static let logoutReason = WGSetting<Bool>("extras.logoutReason", default: true)
    /// «Добавить аккаунт» in Settings with a single account too (upstream shows it from two).
    public static let addAccountRow = WGSetting<Bool>("extras.addAccountRow", default: true)

    static func declare() {
        let _ = WGExtrasSettings.extraMuteDurations
        let _ = WGExtrasSettings.hideAccountInNotifications
        let _ = WGExtrasSettings.searchPartialWords
        let _ = WGExtrasSettings.mentionChain
        let _ = WGExtrasSettings.noRecordTooltip
        let _ = WGExtrasSettings.linkPreviewOpensMedia
        let _ = WGExtrasSettings.linkMenuShare
        let _ = WGExtrasSettings.bioLinks
        let _ = WGExtrasSettings.moreBrowsers
        let _ = WGExtrasSettings.systemShareSheet
        let _ = WGExtrasSettings.hideRepostToStory
        let _ = WGExtrasSettings.selectionPanelButtons
        let _ = WGExtrasSettings.adminListsForAllAdmins
        let _ = WGExtrasSettings.recentActionsShortcut
        let _ = WGExtrasSettings.administratorsMenuItem
        let _ = WGExtrasSettings.hiddenPinnedMenuItem
        let _ = WGExtrasSettings.restrictUntilTime
        let _ = WGExtrasSettings.restrictionReasonCode
        let _ = WGExtrasSettings.archiveInChatMenu
        let _ = WGExtrasSettings.hidePremiumOffers
        let _ = WGExtrasSettings.extraLanguages
        let _ = WGExtrasSettings.youTubePictureInPicture
        let _ = WGExtrasSettings.extraCacheOptions
        let _ = WGExtrasSettings.autolockFiveSeconds
        let _ = WGExtrasSettings.sessionDetails
        let _ = WGExtrasSettings.qrLoginAlways
        let _ = WGExtrasSettings.logoutReason
        let _ = WGExtrasSettings.discussionButton
        let _ = WGExtrasSettings.addAccountRow
    }
}
