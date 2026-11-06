import Foundation
import SwiftSignalKit
import WGCore
import WGHooks
import WGSettingsUI
import WGFeaturesShared

/// Where the Swiftgram-parity features live in the Wraithgram menu (W5-SG): next to the similar rows
/// of each tab, in a few sections of their own. No new tab: every feature found its place.
enum WGExtrasMenu {
    // Own sections.
    static let linksSection = WGMenuSectionID("extras.links")
    static let messageToolsSection = WGMenuSectionID("extras.messageTools")
    static let groupsSection = WGMenuSectionID("extras.groups")
    static let chatListMenuSection = WGMenuSectionID("extras.chatListMenu")
    static let languageSection = WGMenuSectionID("extras.language")
    static let cacheSection = WGMenuSectionID("extras.cache")
    static let sessionsSection = WGMenuSectionID("extras.sessions")
    /// Right under «Уведомления» (no header of its own: the zone's footer speaks of chat exceptions).
    static let notificationsSection = WGMenuSectionID("extras.notifications")
    static let videoSection = WGMenuSectionID("extras.video")

    // Sections of other zones the rows join (at the end, after their own rows).
    static let sendingInputSection = WGMenuSectionID("sending.input")
    static let passcodeOptionsSection = WGMenuSectionID("security.passcode.options")
    /// W2-5's «Таббар» section of «Панели».
    static let panelsTabBarSection = WGMenuSectionID("appearance.panels.tabBar")

    static func register() {
        WGExtrasMenu.registerSections()
        WGExtrasMenu.registerMessages()
        WGExtrasMenu.registerGroups()
        WGExtrasMenu.registerAppearance()
        WGExtrasMenu.registerMedia()
        WGExtrasMenu.registerSecurity()
    }

    private static func registerSections() {
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGExtrasMenu.linksSection, screen: .tab(.messagesMenuGestures), order: 400, header: { WGStrings.Extras.Menu.linksHeader }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGExtrasMenu.messageToolsSection, screen: .tab(.messagesMenuGestures), order: 500, header: { WGStrings.Extras.Menu.messageToolsHeader }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGExtrasMenu.groupsSection, screen: .category(.messages), order: 350, header: { WGStrings.Extras.Menu.groupsHeader }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGExtrasMenu.chatListMenuSection, screen: .tab(.appearanceChatList), order: 700, header: { WGStrings.Extras.Menu.chatListMenuHeader }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGExtrasMenu.languageSection, screen: .tab(.appearanceProfileSettings), order: 600, header: { WGStrings.Extras.Menu.languageHeader }, footer: { _ in WGStrings.Extras.Menu.languageFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGExtrasMenu.cacheSection, screen: .tab(.mediaDownloads), order: 700, header: { WGStrings.Extras.Menu.cacheHeader }, footer: { _ in WGStrings.Extras.Menu.cacheFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGExtrasMenu.sessionsSection, screen: .tab(.securityAccounts), order: 400, header: { WGStrings.Extras.Menu.sessionsHeader }, footer: { _ in WGStrings.Extras.Menu.sessionsFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGExtrasMenu.notificationsSection, screen: .category(.messages), order: 410))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGExtrasMenu.videoSection, screen: .tab(.mediaDownloads), order: 650, header: { WGStrings.Extras.Menu.videoHeader }))
    }

    // MARK: Сообщения

    private static func registerMessages() {
        // Under «Уведомления» (category screen).
        WGMenuRegistry.register(toggle("extras.extraMuteDurations", section: WGExtrasMenu.notificationsSection, order: 100, setting: WGExtrasSettings.extraMuteDurations, title: { WGStrings.Extras.Menu.extraMuteDurations }, subtitle: { WGStrings.Extras.Menu.extraMuteDurationsInfo }))
        WGMenuRegistry.register(toggle("extras.hideAccountInNotifications", section: WGExtrasMenu.notificationsSection, order: 200, setting: WGExtrasSettings.hideAccountInNotifications, title: { WGStrings.Extras.Menu.hideAccountInNotifications }, subtitle: { WGStrings.Extras.Menu.hideAccountInNotificationsInfo }))

        // «Чаты» (category screen).
        WGMenuRegistry.register(toggle("extras.searchPartialWords", section: .messagesChats, order: 1200, setting: WGExtrasSettings.searchPartialWords, title: { WGStrings.Extras.Menu.searchPartialWords }, subtitle: { WGStrings.Extras.Menu.searchPartialWordsInfo }))

        // «Отправка» › «Ввод».
        WGMenuRegistry.register(toggle("extras.mentionChain", section: WGExtrasMenu.sendingInputSection, order: 9000, setting: WGExtrasSettings.mentionChain, title: { WGStrings.Extras.Menu.mentionChain }, subtitle: { WGStrings.Extras.Menu.mentionChainInfo }))
        WGMenuRegistry.register(toggle("extras.noRecordTooltip", section: WGExtrasMenu.sendingInputSection, order: 9100, setting: WGExtrasSettings.noRecordTooltip, title: { WGStrings.Extras.Menu.noRecordTooltip }, subtitle: { WGStrings.Extras.Menu.noRecordTooltipInfo }))

        // «Меню и жесты» › «Ссылки и «Поделиться»».
        let links = WGExtrasMenu.linksSection
        WGMenuRegistry.register(toggle("extras.linkPreviewOpensMedia", section: links, order: 100, setting: WGExtrasSettings.linkPreviewOpensMedia, title: { WGStrings.Extras.Menu.linkPreviewOpensMedia }, subtitle: { WGStrings.Extras.Menu.linkPreviewOpensMediaInfo }))
        WGMenuRegistry.register(toggle("extras.linkMenuShare", section: links, order: 200, setting: WGExtrasSettings.linkMenuShare, title: { WGStrings.Extras.Menu.linkMenuShare }, subtitle: { WGStrings.Extras.Menu.linkMenuShareInfo }))
        WGMenuRegistry.register(toggle("extras.bioLinks", section: links, order: 300, setting: WGExtrasSettings.bioLinks, title: { WGStrings.Extras.Menu.bioLinks }, subtitle: { WGStrings.Extras.Menu.bioLinksInfo }))
        WGMenuRegistry.register(toggle("extras.moreBrowsers", section: links, order: 400, setting: WGExtrasSettings.moreBrowsers, title: { WGStrings.Extras.Menu.moreBrowsers }, subtitle: { WGStrings.Extras.Menu.moreBrowsersInfo }))
        WGMenuRegistry.register(toggle("extras.systemShareSheet", section: links, order: 500, setting: WGExtrasSettings.systemShareSheet, title: { WGStrings.Extras.Menu.systemShareSheet }, subtitle: { WGStrings.Extras.Menu.systemShareSheetInfo }))
        WGMenuRegistry.register(toggle("extras.hideRepostToStory", section: links, order: 600, setting: WGExtrasSettings.hideRepostToStory, title: { WGStrings.Extras.Menu.hideRepostToStory }, subtitle: { WGStrings.Extras.Menu.hideRepostToStoryInfo }))

        // «Меню и жесты» › «Меню и выделение».
        let tools = WGExtrasMenu.messageToolsSection
        WGMenuRegistry.register(toggle("extras.selectionPanelButtons", section: tools, order: 200, setting: WGExtrasSettings.selectionPanelButtons, title: { WGStrings.Extras.Menu.selectionPanelButtons }, subtitle: { WGStrings.Extras.Menu.selectionPanelButtonsInfo }))
    }

    // MARK: Сообщения › Группы и каналы

    private static func registerGroups() {
        let section = WGExtrasMenu.groupsSection
        WGMenuRegistry.register(toggle("extras.adminListsForAllAdmins", section: section, order: 100, setting: WGExtrasSettings.adminListsForAllAdmins, title: { WGStrings.Extras.Menu.adminListsForAllAdmins }, subtitle: { WGStrings.Extras.Menu.adminListsForAllAdminsInfo }))
        WGMenuRegistry.register(toggle("extras.recentActionsShortcut", section: section, order: 200, setting: WGExtrasSettings.recentActionsShortcut, title: { WGStrings.Extras.Menu.recentActionsShortcut }, subtitle: { WGStrings.Extras.Menu.recentActionsShortcutInfo }))
        WGMenuRegistry.register(toggle("extras.administratorsMenuItem", section: section, order: 300, setting: WGExtrasSettings.administratorsMenuItem, title: { WGStrings.Extras.Menu.administratorsMenuItem }, subtitle: { WGStrings.Extras.Menu.administratorsMenuItemInfo }))
        WGMenuRegistry.register(toggle("extras.hiddenPinnedMenuItem", section: section, order: 400, setting: WGExtrasSettings.hiddenPinnedMenuItem, title: { WGStrings.Extras.Menu.hiddenPinnedMenuItem }, subtitle: { WGStrings.Extras.Menu.hiddenPinnedMenuItemInfo }))
        WGMenuRegistry.register(toggle("extras.restrictUntilTime", section: section, order: 500, setting: WGExtrasSettings.restrictUntilTime, title: { WGStrings.Extras.Menu.restrictUntilTime }, subtitle: { WGStrings.Extras.Menu.restrictUntilTimeInfo }))
        WGMenuRegistry.register(toggle("extras.restrictionReasonCode", section: section, order: 600, setting: WGExtrasSettings.restrictionReasonCode, title: { WGStrings.Extras.Menu.restrictionReasonCode }, subtitle: { WGStrings.Extras.Menu.restrictionReasonCodeInfo }))
        WGMenuRegistry.register(toggle("extras.discussionButton", section: section, order: 700, setting: WGExtrasSettings.discussionButton, title: { WGStrings.Extras.Menu.discussionButton }, subtitle: { WGStrings.Extras.Menu.discussionButtonInfo }))
    }

    // MARK: Оформление

    private static func registerAppearance() {
        let chatList = WGExtrasMenu.chatListMenuSection
        WGMenuRegistry.register(toggle("extras.archiveInChatMenu", section: chatList, order: 100, setting: WGExtrasSettings.archiveInChatMenu, title: { WGStrings.Extras.Menu.archiveInChatMenu }, subtitle: { WGStrings.Extras.Menu.archiveInChatMenuInfo }))
        WGMenuRegistry.register(toggle("extras.hidePremiumOffers", section: chatList, order: 200, setting: WGExtrasSettings.hidePremiumOffers, title: { WGStrings.Extras.Menu.hidePremiumOffers }, subtitle: { WGStrings.Extras.Menu.hidePremiumOffersInfo }))

        // «Панели» › tab bar (W2-5's section).

        WGMenuRegistry.register(toggle("extras.extraLanguages", section: WGExtrasMenu.languageSection, order: 100, setting: WGExtrasSettings.extraLanguages, title: { WGStrings.Extras.Menu.extraLanguages }, subtitle: { WGStrings.Extras.Menu.extraLanguagesInfo }))
    }

    // MARK: Медиа › Загрузки и качество

    private static func registerMedia() {
        WGMenuRegistry.register(toggle("extras.youTubePictureInPicture", section: WGExtrasMenu.videoSection, order: 100, setting: WGExtrasSettings.youTubePictureInPicture, title: { WGStrings.Extras.Menu.youTubePictureInPicture }, subtitle: { WGStrings.Extras.Menu.youTubePictureInPictureInfo }))
        WGMenuRegistry.register(toggle("extras.extraCacheOptions", section: WGExtrasMenu.cacheSection, order: 100, setting: WGExtrasSettings.extraCacheOptions, title: { WGStrings.Extras.Menu.extraCacheOptions }, subtitle: { WGStrings.Extras.Menu.extraCacheOptionsInfo }))
    }

    // MARK: Безопасность

    private static func registerSecurity() {
        WGMenuRegistry.register(toggle("extras.autolockFiveSeconds", section: WGExtrasMenu.passcodeOptionsSection, order: 9000, setting: WGExtrasSettings.autolockFiveSeconds, title: { WGStrings.Extras.Menu.autolockFiveSeconds }, subtitle: { WGStrings.Extras.Menu.autolockFiveSecondsInfo }))
        let sessions = WGExtrasMenu.sessionsSection
        WGMenuRegistry.register(toggle("extras.sessionDetails", section: sessions, order: 100, setting: WGExtrasSettings.sessionDetails, title: { WGStrings.Extras.Menu.sessionDetails }, subtitle: { WGStrings.Extras.Menu.sessionDetailsInfo }))
        WGMenuRegistry.register(toggle("extras.qrLoginAlways", section: sessions, order: 200, setting: WGExtrasSettings.qrLoginAlways, title: { WGStrings.Extras.Menu.qrLoginAlways }, subtitle: { WGStrings.Extras.Menu.qrLoginAlwaysInfo }))
        WGMenuRegistry.register(toggle("extras.logoutReason", section: sessions, order: 300, setting: WGExtrasSettings.logoutReason, title: { WGStrings.Extras.Menu.logoutReason }, subtitle: { WGStrings.Extras.Menu.logoutReasonInfo }))
        // «Аккаунты» (W3-4's tab), after its own rows.
        WGMenuRegistry.register(toggle("extras.addAccountRow", section: WGMenuSectionID.main(of: WGMenuTabID.securityAccounts), order: 9000, setting: WGExtrasSettings.addAccountRow, title: { WGStrings.Extras.Menu.addAccountRow }, subtitle: { WGStrings.Extras.Menu.addAccountRowInfo }))
        // The row is built with the Settings tab, which Telegram rebuilds only when its own data
        // changes: the switch rebuilds it at once.
        WGExtrasMenu.addAccountRowDisposable = (WGExtrasSettings.addAccountRow.signal
        |> deliverOnMainQueue).start(next: { _ in
            WGSettingsTabHooks.invalidate()
        })
    }

    private static var addAccountRowDisposable: Disposable?

    private static func toggle(_ id: String, section: WGMenuSectionID, order: Int, setting: WGSetting<Bool>, title: @escaping () -> String, subtitle: (() -> String)? = nil) -> WGMenuRow {
        return WGMenuRow(id: id, section: section, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting)))
    }
}
