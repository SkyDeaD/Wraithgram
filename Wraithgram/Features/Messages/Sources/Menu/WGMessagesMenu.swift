import Foundation
import UIKit
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import PresentationDataUtils
import ItemListUI
import TranslateUI
import WGCore
import WGSettingsUI
import WGFeaturesShared

/// Menu rows of the zone (PLAN §2.2): «Сообщения» › «Обходы ограничений», «Отправка», «Перевод»,
/// «Меню и жесты» and the «Чаты» / «Уведомления» sections of the category screen.
/// Order is sparse (step 100); titles are evaluated at display time.
enum WGMessagesMenu {
    static let rulesTab = WGMenuTabID("sending.rules")
    static let keywordsTab = WGMenuTabID("chats.keywords")
    static let localCreatorTab = WGMenuTabID("chats.localCreator")
    static let exceptionsTab = WGMenuTabID("notifications.exceptions")

    static let sendingTextSection = WGMenuSectionID("sending.text")
    static let sendingRepliesSection = WGMenuSectionID("sending.replies")
    static let sendingInputSection = WGMenuSectionID("sending.input")
    static let translationServiceSection = WGMenuSectionID("translation.service")
    static let gesturesSection = WGMenuSectionID("gestures.main")
    static let notificationsSection = WGMenuSectionID("notifications.main")

    static func register() {
        WGMessagesMenu.registerRestrictions()
        WGMessagesMenu.registerSending()
        WGMessagesMenu.registerTranslation()
        WGMessagesMenu.registerMenuAndGestures()
        WGMessagesMenu.registerChats()
        WGMessagesMenu.registerNotifications()
    }

    private static func toggle(_ id: String, section: WGMenuSectionID, order: Int, setting: WGSetting<Bool>, title: @escaping () -> String, subtitle: (() -> String)? = nil, isVisible: ((WGMenuContext) -> Bool)? = nil, keywords: @escaping () -> [String] = { [] }) -> WGMenuRow {
        return WGMenuRow(id: id, section: section, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting)), isVisible: isVisible, searchKeywords: keywords)
    }

    // MARK: Restrictions

    private static func registerRestrictions() {
        let section = WGMenuSectionID.main(of: .messagesRestrictions)
        WGMenuRegistry.register(toggle("restrictions.copyProtection", section: section, order: 100, setting: WGMessagesSettings.copyProtectionBypass, title: { WGStrings.Restrictions.Menu.copyProtection }, subtitle: { WGStrings.Restrictions.Menu.copyProtectionInfo }, keywords: { [WGStrings.Restrictions.Menu.keywordForward] }))
        WGMenuRegistry.register(toggle("restrictions.forwardAttribution", section: section, order: 200, setting: WGMessagesSettings.forwardAttribution, title: { WGStrings.Restrictions.Menu.forwardAttribution }, subtitle: { WGStrings.Restrictions.Menu.forwardAttributionInfo }, isVisible: { _ in WGMessagesSettings.copyProtectionBypass.value }))
        WGMenuRegistry.register(toggle("restrictions.keepSelfDestructing", section: section, order: 300, setting: WGMessagesSettings.keepSelfDestructingMedia, title: { WGStrings.Restrictions.Menu.keepSelfDestructing }, subtitle: { WGStrings.Restrictions.Menu.keepSelfDestructingInfo }, keywords: { [WGStrings.Restrictions.Menu.keywordViewOnce] }))
        WGMenuRegistry.register(toggle("restrictions.screenshots", section: section, order: 400, setting: WGMessagesSettings.screenshotBypass, title: { WGStrings.Restrictions.Menu.screenshots }, subtitle: { WGStrings.Restrictions.Menu.screenshotsInfo }, keywords: { [WGStrings.Restrictions.Menu.keywordScreenshot] }))
        WGMenuRegistry.register(toggle("restrictions.blockAds", section: section, order: 500, setting: WGMessagesSettings.blockAds, title: { WGStrings.Restrictions.Menu.blockAds }, subtitle: { WGStrings.Restrictions.Menu.blockAdsInfo }))
        WGMenuRegistry.register(toggle("restrictions.contentRestrictions", section: section, order: 600, setting: WGMessagesSettings.contentRestrictionsBypass, title: { WGStrings.Restrictions.Menu.contentRestrictions }, subtitle: { WGStrings.Restrictions.Menu.contentRestrictionsInfo }))
        WGMenuRegistry.register(toggle("restrictions.revealSpoilers", section: section, order: 700, setting: WGMessagesSettings.revealSpoilers, title: { WGStrings.Restrictions.Menu.revealSpoilers }, subtitle: { WGStrings.Restrictions.Menu.revealSpoilersInfo }))
    }

    // MARK: Sending

    private static func registerSending() {
        let screen = WGMenuScreenID.tab(.messagesSending)
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGMessagesMenu.sendingTextSection, screen: screen, order: 300, header: { WGStrings.Sending.Menu.textHeader }, footer: { _ in WGStrings.Sending.Menu.textFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGMessagesMenu.sendingRepliesSection, screen: screen, order: 400, header: { WGStrings.Sending.Menu.repliesHeader }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGMessagesMenu.sendingInputSection, screen: screen, order: 500, header: { WGStrings.Sending.Menu.inputHeader }))

        WGMenuRegistry.register(WGMenuRow(id: "sending.preview", section: .preview(of: .messagesSending), order: 100, title: { "" }, kind: .preview(.miniChat(WGMiniChatConfiguration(scope: "sending", height: 150.0, content: { context in
            return WGSendingPreview.content(context)
        })))))

        let text = WGMessagesMenu.sendingTextSection
        WGMenuRegistry.register(toggle("sending.wordReplacement", section: text, order: 100, setting: WGMessagesSettings.wordReplacement, title: { WGStrings.Sending.Menu.wordReplacement }, subtitle: { WGStrings.Sending.Menu.wordReplacementInfo }, keywords: { [WGStrings.Sending.Menu.keywordText] }))
        WGMenuRegistry.register(tab: WGMenuTabDescriptor(id: WGMessagesMenu.rulesTab, parent: screen, title: { WGStrings.Sending.Rules.title }, makeScreen: { context in
            return wgMakeReplacementRulesScreen(menuContext: context)
        }))
        WGMenuRegistry.register(WGMenuRow(id: "sending.rules", section: text, order: 200, title: { WGStrings.Sending.Menu.rules }, kind: .tab(WGMessagesMenu.rulesTab), isVisible: { _ in WGMessagesSettings.wordReplacement.value }, label: { _ in
            return WGStrings.Sending.Menu.rulesCount(count: WGOutgoingPipeline.replacementRules.value.count)
        }))
        WGMenuRegistry.register(toggle("sending.antiCaps", section: text, order: 300, setting: WGMessagesSettings.antiCaps, title: { WGStrings.Sending.Menu.antiCaps }, subtitle: { WGStrings.Sending.Menu.antiCapsInfo }))
        WGMenuRegistry.register(toggle("sending.hyperlink", section: text, order: 600, setting: WGMessagesSettings.hyperlinkSpoof, title: { WGStrings.Sending.Menu.hyperlink }, subtitle: { WGStrings.Sending.Menu.hyperlinkInfo }))
        WGMenuRegistry.register(WGMenuRow(id: "sending.hyperlinkTarget", section: text, order: 700, title: { WGStrings.Sending.Menu.hyperlinkTarget }, kind: .action({ context in
            WGHyperlinkTarget.edit(menuContext: context)
        }), isVisible: { _ in WGMessagesSettings.hyperlinkSpoof.value }, label: { context in
            return WGHyperlinkTarget.label(menuContext: context)
        }))

        let replies = WGMessagesMenu.sendingRepliesSection
        WGMenuRegistry.register(toggle("sending.autoQuote", section: replies, order: 100, setting: WGMessagesSettings.autoQuoteReply, title: { WGStrings.Sending.Menu.autoQuote }, subtitle: { WGStrings.Sending.Menu.autoQuoteInfo }))
        WGMenuRegistry.register(toggle("sending.autoQuoteSkipComments", section: replies, order: 200, setting: WGMessagesSettings.autoQuoteSkipComments, title: { WGStrings.Sending.Menu.autoQuoteSkipComments }, isVisible: { _ in WGMessagesSettings.autoQuoteReply.value }))
        WGMenuRegistry.register(toggle("sending.anonymousStickers", section: replies, order: 300, setting: WGMessagesSettings.anonymousStickers, title: { WGStrings.Sending.Menu.anonymousStickers }, subtitle: { WGStrings.Sending.Menu.anonymousStickersInfo }))
        WGMenuRegistry.register(toggle("sending.withoutVia", section: replies, order: 400, setting: WGMessagesSettings.sendWithoutViaBot, title: { WGStrings.Sending.Menu.withoutVia }, subtitle: { WGStrings.Sending.Menu.withoutViaInfo }))
        WGMenuRegistry.register(toggle("sending.keepCaption", section: replies, order: 500, setting: WGMessagesSettings.keepInlineBotCaption, title: { WGStrings.Sending.Menu.keepCaption }, isVisible: { _ in WGMessagesSettings.sendWithoutViaBot.value }))

        let input = WGMessagesMenu.sendingInputSection
        WGMenuRegistry.register(toggle("sending.sendOnReturn", section: input, order: 100, setting: WGMessagesSettings.sendOnReturn, title: { WGStrings.Sending.Menu.sendOnReturn }, subtitle: { WGStrings.Sending.Menu.sendOnReturnInfo }))
        WGMenuRegistry.register(toggle("sending.hideSendAs", section: input, order: 200, setting: WGMessagesSettings.hideSendAsButton, title: { WGStrings.Sending.Menu.hideSendAs }))
    }

    // MARK: Translation

    private static func registerTranslation() {
        let screen = WGMenuScreenID.tab(.messagesTranslation)
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGMessagesMenu.translationServiceSection, screen: screen, order: 300, footer: { _ in WGStrings.Translation.Menu.serviceFooter }))

        // An incoming message in another language shows the quick translate button (when it is on),
        // the outgoing one the translation before sending.
        WGMenuRegistry.register(WGMenuRow(id: "translation.preview", section: .preview(of: .messagesTranslation), order: 100, title: { "" }, kind: .preview(.miniChat(WGMiniChatConfiguration(scope: "translation", height: 200.0, content: { _ in
            return WGMiniChatContent(header: nil, messages: [
                WGPreviewMessage(id: 1, isOutgoing: false, text: WGStrings.Translation.Preview.incoming, ageSeconds: 120),
                WGPreviewMessage(id: 2, isOutgoing: true, text: WGStrings.Translation.Preview.result, reply: WGPreviewReply(author: WGStrings.Translation.Preview.input, text: WGStrings.Translation.Preview.source), ageSeconds: 60)
            ])
        })))))

        WGMenuRegistry.register(WGMenuRow(id: "translation.service", section: WGMessagesMenu.translationServiceSection, order: 100, title: { WGStrings.Translation.Menu.service }, kind: .action({ context in
            WGTranslationMenu.chooseService(menuContext: context)
        }), searchKeywords: { [WGStrings.Translation.Menu.keyword] }, label: { _ in
            return WGTranslationMenu.serviceTitle(WGTranslationServiceKind(rawValue: WGMessagesSettings.translationService.value) ?? .telegram)
        }))

        let main = WGMenuSectionID.main(of: .messagesTranslation)
        WGMenuRegistry.register(toggle("translation.quickButton", section: main, order: 100, setting: WGMessagesSettings.quickTranslateButton, title: { WGStrings.Translation.Menu.quickButton }, subtitle: { WGStrings.Translation.Menu.quickButtonInfo }))
        WGMenuRegistry.register(toggle("translation.beforeSending", section: main, order: 200, setting: WGMessagesSettings.translateBeforeSending, title: { WGStrings.Translation.Menu.beforeSending }, subtitle: { WGStrings.Translation.Menu.beforeSendingInfo }))
        WGMenuRegistry.register(WGMenuRow(id: "translation.beforeSendingLanguage", section: main, order: 300, title: { WGStrings.Translation.Menu.beforeSendingLanguage }, kind: .choice(.global(WGMessagesSettings.translateBeforeSendingLanguage), options: WGTranslationMenu.languageOptions()), isVisible: { _ in WGMessagesSettings.translateBeforeSending.value }))
        WGMenuRegistry.register(toggle("translation.photo", section: main, order: 400, setting: WGMessagesSettings.photoTranslation, title: { WGStrings.Translation.Menu.photo }, subtitle: { WGStrings.Translation.Menu.photoInfo }))
        WGMenuRegistry.register(WGMenuRow(id: "translation.telegramSettings", section: main, order: 500, title: { WGStrings.Translation.Menu.telegramSettings }, subtitle: { WGStrings.Translation.Menu.telegramSettingsInfo }, kind: .action({ context in
            if let make = WGSettingsUIEnvironment.shared.makeTelegramLanguageController {
                context.push(make(context.context))
            }
        }), isVisible: { _ in WGSettingsUIEnvironment.shared.makeTelegramLanguageController != nil }))
    }

    // MARK: Menu and gestures

    private static func registerMenuAndGestures() {
        let main = WGMenuSectionID.main(of: .messagesMenuGestures)
        let children: [WGMenuRow] = [
            toggle("messageMenu.reply", section: main, order: 100, setting: WGMessagesSettings.menuShowReply, title: { WGStrings.MessageMenu.Menu.reply }),
            toggle("messageMenu.pin", section: main, order: 200, setting: WGMessagesSettings.menuShowPin, title: { WGStrings.MessageMenu.Menu.pin }),
            toggle("messageMenu.report", section: main, order: 300, setting: WGMessagesSettings.menuShowReport, title: { WGStrings.MessageMenu.Menu.report }),
            toggle("messageMenu.saveMedia", section: main, order: 400, setting: WGMessagesSettings.menuShowSaveMedia, title: { WGStrings.MessageMenu.Menu.saveMedia }),
            toggle("messageMenu.replies", section: main, order: 500, setting: WGMessagesSettings.menuShowReplies, title: { WGStrings.MessageMenu.Menu.replies }),
            toggle("messageMenu.restrict", section: main, order: 600, setting: WGMessagesSettings.menuShowRestrict, title: { WGStrings.MessageMenu.Menu.restrict }),
            toggle("messageMenu.saveToCloud", section: main, order: 700, setting: WGMessagesSettings.menuSaveToCloud, title: { WGStrings.MessageMenu.Menu.saveToCloud }),
            toggle("messageMenu.forwardWithoutAuthor", section: main, order: 800, setting: WGMessagesSettings.menuForwardWithoutAuthor, title: { WGStrings.MessageMenu.Menu.forwardWithoutAuthor })
        ]
        WGMenuRegistry.register(WGMenuRow(id: "messageMenu.custom", section: main, order: 100, title: { WGStrings.MessageMenu.Menu.custom }, subtitle: { WGStrings.MessageMenu.Menu.customInfo }, kind: .expandableGroup(master: .global(WGMessagesSettings.customMessageMenu), children: children)))

        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGMessagesMenu.gesturesSection, screen: .tab(.messagesMenuGestures), order: 300, header: { WGStrings.Gestures.Menu.header }))
        WGMenuRegistry.register(toggle("gestures.doubleTapToEdit", section: WGMessagesMenu.gesturesSection, order: 100, setting: WGMessagesSettings.doubleTapToEdit, title: { WGStrings.Gestures.Menu.doubleTapToEdit }, subtitle: { WGStrings.Gestures.Menu.doubleTapToEditInfo }))
        WGMenuRegistry.register(toggle("gestures.disableVideoPipSwipe", section: WGMessagesMenu.gesturesSection, order: 200, setting: WGMessagesSettings.disableVideoPipSwipe, title: { WGStrings.Gestures.Menu.disableVideoPipSwipe }, subtitle: { WGStrings.Gestures.Menu.disableVideoPipSwipeInfo }))
    }

    // MARK: Chats

    private static func registerChats() {
        let section = WGMenuSectionID.messagesChats
        WGMenuRegistry.register(toggle("chats.unlimitedSearch", section: section, order: 200, setting: WGMessagesSettings.unlimitedSearchHistory, title: { WGStrings.Chats.Menu.unlimitedSearch }, subtitle: { WGStrings.Chats.Menu.unlimitedSearchInfo }))
        WGMenuRegistry.register(toggle("chats.hideGreeting", section: section, order: 300, setting: WGMessagesSettings.hideGreetingSticker, title: { WGStrings.Chats.Menu.hideGreeting }, subtitle: { WGStrings.Chats.Menu.hideGreetingInfo }))
        WGMenuRegistry.register(toggle("chats.keywordFilter", section: section, order: 400, setting: WGMessagesSettings.keywordFilter, title: { WGStrings.Chats.Menu.keywordFilter }, subtitle: { WGStrings.Chats.Menu.keywordFilterInfo }))
        WGMenuRegistry.register(tab: WGMenuTabDescriptor(id: WGMessagesMenu.keywordsTab, parent: .category(.messages), title: { WGStrings.Chats.Keywords.title }, makeScreen: { context in
            return wgMakeKeywordsScreen(menuContext: context)
        }))
        WGMenuRegistry.register(WGMenuRow(id: "chats.keywords", section: section, order: 500, title: { WGStrings.Chats.Menu.keywords }, kind: .tab(WGMessagesMenu.keywordsTab), isVisible: { _ in WGMessagesSettings.keywordFilter.value }, label: { _ in
            return WGStrings.Chats.Menu.keywordsCount(count: WGMessagesSettings.keywords.value.count)
        }))
        WGMenuRegistry.register(toggle("chats.hideChannelButton", section: section, order: 600, setting: WGMessagesSettings.hideChannelBottomButton, title: { WGStrings.Chats.Menu.hideChannelButton }, subtitle: { WGStrings.Chats.Menu.hideChannelButtonInfo }))
        // One switch for channels and forum topics (2026-10-27).
        WGMenuRegistry.register(toggle("chats.noNext", section: section, order: 700, setting: WGMessagesSettings.disableScrollToNext, title: { WGStrings.Chats.Menu.noNext }, subtitle: { WGStrings.Chats.Menu.noNextInfo }))
        WGMenuRegistry.register(toggle("chats.noDeleteEffect", section: section, order: 900, setting: WGMessagesSettings.disableDeleteEffect, title: { WGStrings.Chats.Menu.noDeleteEffect }, subtitle: { WGStrings.Chats.Menu.noDeleteEffectInfo }))
        WGMenuRegistry.register(toggle("chats.hideRecordButton", section: section, order: 1000, setting: WGMessagesSettings.hideRecordButton, title: { WGStrings.Chats.Menu.hideRecordButton }, subtitle: { WGStrings.Chats.Menu.hideRecordButtonInfo }))
        WGMenuRegistry.register(tab: WGMenuTabDescriptor(id: WGMessagesMenu.localCreatorTab, parent: .category(.messages), title: { WGStrings.Chats.LocalCreator.title }, makeScreen: { context in
            return wgMakeLocalCreatorScreen(menuContext: context)
        }))
        WGMenuRegistry.register(WGMenuRow(id: "chats.localCreator", section: section, order: 1100, title: { WGStrings.Chats.Menu.localCreator }, subtitle: { WGStrings.Chats.Menu.localCreatorInfo }, kind: .tab(WGMessagesMenu.localCreatorTab), label: { context in
            return WGStrings.Chats.Menu.localCreatorCount(count: WGMessagesSettings.localCreatorChannels.value(for: context.accountID).count)
        }))
        // «Безлимитные закрепы» have no switch (always on, owner's decision 2026-10-22). The section
        // ends with what the user has to know about them: where they work and that the pins beyond
        // Telegram's limit stay on this device. Found by search as «закрепы».
        WGMenuRegistry.register(WGMenuRow(id: "chats.unlimitedPins", section: section, order: 10000, title: { WGStrings.Chats.Menu.unlimitedPins }, subtitle: { WGStrings.Chats.Menu.unlimitedPinsInfo }, kind: .custom({ context in
            return ItemListTextItem(presentationData: context.itemListPresentationData, text: .plain(WGStrings.Chats.Menu.unlimitedPinsInfo), sectionId: context.sectionId)
        }), searchKeywords: { [WGStrings.Chats.Menu.keywordPins] }))
    }

    // MARK: Notifications

    private static func registerNotifications() {
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGMessagesMenu.notificationsSection, screen: .category(.messages), order: 400, header: { WGStrings.Notifications.Menu.header }, footer: { _ in WGStrings.Notifications.Menu.footer }))
        let options = [
            WGMenuChoiceOption(value: WGNotificationDeliveryMode.standard.rawValue, title: { WGStrings.Notifications.Menu.modeStandard }),
            WGMenuChoiceOption(value: WGNotificationDeliveryMode.silent.rawValue, title: { WGStrings.Notifications.Menu.modeSilent }),
            WGMenuChoiceOption(value: WGNotificationDeliveryMode.disabled.rawValue, title: { WGStrings.Notifications.Menu.modeDisabled })
        ]
        let section = WGMessagesMenu.notificationsSection
        WGMenuRegistry.register(WGMenuRow(id: "notifications.pinned", section: section, order: 100, title: { WGStrings.Notifications.Menu.pinned }, kind: .choice(.global(WGMessagesSettings.pinnedNotifications), options: options)))
        WGMenuRegistry.register(WGMenuRow(id: "notifications.mentions", section: section, order: 200, title: { WGStrings.Notifications.Menu.mentions }, kind: .choice(.global(WGMessagesSettings.mentionNotifications), options: options)))
        WGMenuRegistry.register(tab: WGMenuTabDescriptor(id: WGMessagesMenu.exceptionsTab, parent: .category(.messages), title: { WGStrings.Notifications.Exceptions.title }, makeScreen: { context in
            return wgMakeNotificationExceptionsScreen(menuContext: context)
        }))
        WGMenuRegistry.register(WGMenuRow(id: "notifications.exceptions", section: section, order: 300, title: { WGStrings.Notifications.Menu.exceptions }, kind: .tab(WGMessagesMenu.exceptionsTab), label: { context in
            return WGStrings.Notifications.Menu.exceptionsCount(count: WGNotificationExceptions.peerKeys(accountId: context.accountID).count)
        }))
    }
}

/// «было → станет» on a real bubble: the sample text run through the enabled stages.
enum WGSendingPreview {
    static func content(_ context: WGMenuContext) -> WGMiniChatContent {
        let sample = WGStrings.Sending.Preview.sample
        let configuration = WGOutgoingPipeline.configuration(accountId: context.accountID)
        let pipelineContext = WGTextPipelineContext(isBot: false, isSavedMessages: false, isVerbatim: false)
        let result = WGOutgoingPipeline.run(WGOutgoingText(text: sample, entities: []), configuration: configuration, context: pipelineContext, hyperlinkTarget: nil)
        return WGMiniChatContent(header: nil, messages: [
            WGPreviewMessage(id: 1, isOutgoing: true, text: result.text, reply: WGPreviewReply(author: WGStrings.Sending.Preview.before, text: sample), ageSeconds: 60)
        ])
    }
}
