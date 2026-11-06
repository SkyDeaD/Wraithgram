import Foundation
import UIKit
import Display
import ItemListUI
import TelegramPresentationData
import WGCore
import WGSettingsUI
import WGAppearanceSettings

/// The appearance rows of the Wraithgram menu (PLAN §2.4): tabs «Сообщения», «Тема и фон» and the
/// «Профиль» part of «Профиль и Настройки». Every setting has exactly one row; titles are computed
/// at display time; sliders write once, on release (the preview follows the finger).
enum WGAppearanceMenu {
    // Sections of «Сообщения».
    static let messagesBubbles = WGMenuSectionID("appearance.messages.bubbles")
    static let messagesChecks = WGMenuSectionID("appearance.messages.checkmarks")
    static let messagesStickers = WGMenuSectionID("appearance.messages.stickers")
    static let messagesInterface = WGMenuSectionID("appearance.messages.interface")
    static let messagesTopBar = WGMenuSectionID("appearance.messages.topBar")
    // Sections of «Тема и фон».
    static let themeEdges = WGMenuSectionID("appearance.themeBackground.edges")
    static let themeBackground = WGMenuSectionID("appearance.themeBackground.chatBackground")
    static let themeSnow = WGMenuSectionID("appearance.themeBackground.snow")
    // Sections of «Профиль и Настройки» (the «Настройки» part belongs to the interface feature).
    static let profileInfo = WGMenuSectionID("appearance.profileSettings.profile")
    static let profileBackground = WGMenuSectionID("appearance.profileSettings.profileBackground")
    // The font tab.
    static let fontTab = WGMenuTabID("appearance.font")
    static let fontSystem = WGMenuSectionID("appearance.font.systemDesigns")
    static let fontFamilies = WGMenuSectionID("appearance.font.families")
    static let fontCustom = WGMenuSectionID("appearance.font.custom")

    static func register() {
        WGAppearanceMenu.registerMessages()
        WGAppearanceMenu.registerFont()
        WGAppearanceMenu.registerTheme()
        WGAppearanceMenu.registerProfile()
    }

    // MARK: Formats

    static func percent(_ value: Double) -> String {
        return WGStrings.Appearance.Common.percent(value: "\(Int(value.rounded()))")
    }

    static func points(_ value: Double) -> String {
        return WGStrings.Appearance.Common.points(value: "\(Int(value.rounded()))")
    }

    static func colorLabel(_ setting: WGSetting<String>) -> String {
        if let rgb = wgAppearanceParseColor(setting.value) {
            return "#" + wgAppearanceColorString(rgb)
        }
        return WGStrings.Appearance.Common.automatic
    }

    // MARK: «Сообщения»

    private static func registerMessages() {
        let tab = WGMenuTabID.appearanceMessages

        WGMenuRegistry.register(WGMenuRow(
            id: "appearance.messages.preview",
            section: .preview(of: tab),
            order: 100,
            title: { "" },
            // Live: bubbles follow the sliders of the bubble editor while dragged (U6); the top bar
            // follows «Скрыть в шапке чата» (U7).
            kind: .preview(.miniChat(WGAppearancePreview.configuration(scope: "appearance.messages", overlays: false, content: { _ in
                var content = WGAppearancePreview.sampleContent()
                if content.messages.count > 1 {
                    // Shows the «edited» label, the time and the checkmarks the options change.
                    content.messages[1].isEdited = true
                }
                return content
            })))
        ))

        // Font: its own tab with samples.
        WGMenuRegistry.register(tab: WGMenuTabDescriptor(
            id: WGAppearanceMenu.fontTab,
            parent: .tab(tab),
            title: { WGStrings.Appearance.Font.title },
            topView: WGMenuTopView(content: .emoji("🔤"), text: { WGStrings.Appearance.Font.info }),
            searchKeywords: { [WGStrings.Appearance.Font.keywords] }
        ), linkIn: .main(of: tab), order: 100, subtitle: { WGStrings.Appearance.Font.subtitle }, icon: .bundle("Chat/Context Menu/FormatText"), label: { _ in
            return WGFonts.selectedDisplayName
        })

        // Bubbles.
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGAppearanceMenu.messagesBubbles, screen: .tab(tab), order: 300, header: { WGStrings.Appearance.Bubbles.header }, footer: { _ in WGStrings.Appearance.Bubbles.footer }))
        let editorOn: (WGMenuContext) -> Bool = { _ in WGAppearanceSettings.bubbleEditor.value }
        WGMenuRegistry.register(WGMenuRow(id: "appearance.bubbles.editor", section: WGAppearanceMenu.messagesBubbles, order: 100, title: { WGStrings.Appearance.Bubbles.editor }, subtitle: { WGStrings.Appearance.Bubbles.editorInfo }, kind: .toggle(.global(WGAppearanceSettings.bubbleEditor)), searchKeywords: { [WGStrings.Appearance.Bubbles.keywords] }))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.bubbles.incomingRadius", section: WGAppearanceMenu.messagesBubbles, order: 200, title: { WGStrings.Appearance.Bubbles.incomingRadius }, kind: .slider(.global(WGAppearanceSettings.bubbleIncomingRadius), range: 0.0 ... 16.0, step: 1.0, format: WGAppearanceMenu.points), isVisible: editorOn))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.bubbles.outgoingRadius", section: WGAppearanceMenu.messagesBubbles, order: 300, title: { WGStrings.Appearance.Bubbles.outgoingRadius }, kind: .slider(.global(WGAppearanceSettings.bubbleOutgoingRadius), range: 0.0 ... 16.0, step: 1.0, format: WGAppearanceMenu.points), isVisible: editorOn))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.bubbles.padding", section: WGAppearanceMenu.messagesBubbles, order: 400, title: { WGStrings.Appearance.Bubbles.padding }, kind: .slider(.global(WGAppearanceSettings.bubblePadding), range: 0.0 ... 24.0, step: 1.0, format: WGAppearanceMenu.points), isVisible: editorOn))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.bubbles.width", section: WGAppearanceMenu.messagesBubbles, order: 500, title: { WGStrings.Appearance.Bubbles.width }, kind: .slider(.global(WGAppearanceSettings.bubbleWidth), range: 40.0 ... 100.0, step: 5.0, format: WGAppearanceMenu.percent), isVisible: editorOn))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.bubbles.backgroundOpacity", section: WGAppearanceMenu.messagesBubbles, order: 600, title: { WGStrings.Appearance.Bubbles.backgroundOpacity }, kind: .slider(.global(WGAppearanceSettings.bubbleBackgroundOpacity), range: 0.0 ... 100.0, step: 5.0, format: WGAppearanceMenu.percent), isVisible: editorOn))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.bubbles.outlineOpacity", section: WGAppearanceMenu.messagesBubbles, order: 700, title: { WGStrings.Appearance.Bubbles.outlineOpacity }, kind: .slider(.global(WGAppearanceSettings.bubbleOutlineOpacity), range: 0.0 ... 100.0, step: 5.0, format: WGAppearanceMenu.percent), isVisible: editorOn))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.bubbles.reset", section: WGAppearanceMenu.messagesBubbles, order: 800, title: { WGStrings.Appearance.Bubbles.reset }, kind: .action({ _ in
            WGAppearanceSettings.bubbleIncomingRadius.reset()
            WGAppearanceSettings.bubbleOutgoingRadius.reset()
            WGAppearanceSettings.bubblePadding.reset()
            WGAppearanceSettings.bubbleWidth.reset()
            WGAppearanceSettings.bubbleBackgroundOpacity.reset()
            WGAppearanceSettings.bubbleOutlineOpacity.reset()
        }), isVisible: editorOn, isDestructive: true))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.bubbles.hideTails", section: WGAppearanceMenu.messagesBubbles, order: 900, title: { WGStrings.Appearance.Bubbles.hideTails }, subtitle: { WGStrings.Appearance.Bubbles.hideTailsInfo }, kind: .toggle(.global(WGAppearanceSettings.bubbleHideTails))))

        // Checkmarks.
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGAppearanceMenu.messagesChecks, screen: .tab(tab), order: 400, header: { WGStrings.Appearance.Checkmarks.header }))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.checkmarks.readColor", section: WGAppearanceMenu.messagesChecks, order: 100, title: { WGStrings.Appearance.Checkmarks.readColor }, kind: .action({ context in
            WGColorPicker.present(context: context, setting: WGAppearanceSettings.readCheckColor, fallback: UIColor(rgb: 0x19c700))
        }), searchKeywords: { [WGStrings.Appearance.Checkmarks.keywords] }, label: { _ in WGAppearanceMenu.colorLabel(WGAppearanceSettings.readCheckColor) }))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.checkmarks.unreadSameAsRead", section: WGAppearanceMenu.messagesChecks, order: 200, title: { WGStrings.Appearance.Checkmarks.unreadSameAsRead }, kind: .toggle(.global(WGAppearanceSettings.unreadCheckSameAsRead)), isVisible: { _ in !WGAppearanceSettings.readCheckColor.value.isEmpty }))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.checkmarks.unreadColor", section: WGAppearanceMenu.messagesChecks, order: 300, title: { WGStrings.Appearance.Checkmarks.unreadColor }, kind: .action({ context in
            WGColorPicker.present(context: context, setting: WGAppearanceSettings.unreadCheckColor, fallback: UIColor(rgb: 0xa3a3a3))
        }), isVisible: { _ in !WGAppearanceSettings.unreadCheckSameAsRead.value || WGAppearanceSettings.readCheckColor.value.isEmpty }, label: { _ in WGAppearanceMenu.colorLabel(WGAppearanceSettings.unreadCheckColor) }))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.checkmarks.inChatList", section: WGAppearanceMenu.messagesChecks, order: 400, title: { WGStrings.Appearance.Checkmarks.inChatList }, kind: .toggle(.global(WGAppearanceSettings.checkColorsInChatList)), isVisible: { _ in !WGAppearanceSettings.readCheckColor.value.isEmpty }))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.checkmarks.reset", section: WGAppearanceMenu.messagesChecks, order: 500, title: { WGStrings.Appearance.Checkmarks.reset }, kind: .action({ _ in
            WGAppearanceSettings.readCheckColor.reset()
            WGAppearanceSettings.unreadCheckColor.reset()
        }), isVisible: { _ in !WGAppearanceSettings.readCheckColor.value.isEmpty || !WGAppearanceSettings.unreadCheckColor.value.isEmpty }, isDestructive: true))

        // Stickers.
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGAppearanceMenu.messagesStickers, screen: .tab(tab), order: 500, header: { WGStrings.Appearance.Stickers.header }))
        // Live: the emoji and the sticker follow the size slider while it is dragged (2026-11-02).
        WGMenuRegistry.register(WGMenuRow(id: "appearance.stickers.preview", section: WGAppearanceMenu.messagesStickers, order: 50, title: { "" }, kind: .preview(.custom(height: WGStickerSizePreviewView.height, make: { _ in
            return WGStickerSizePreviewView(frame: .zero)
        }))))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.stickers.size", section: WGAppearanceMenu.messagesStickers, order: 100, title: { WGStrings.Appearance.Stickers.size }, kind: .slider(.global(WGAppearanceSettings.stickerSize), range: 50.0 ... 200.0, step: 5.0, format: WGAppearanceMenu.percent)))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.stickers.hideTime", section: WGAppearanceMenu.messagesStickers, order: 200, title: { WGStrings.Appearance.Stickers.hideTime }, kind: .toggle(.global(WGAppearanceSettings.stickerHideTime))))

        // Message interface.
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGAppearanceMenu.messagesInterface, screen: .tab(tab), order: 600, header: { WGStrings.Appearance.Messages.header }))
        // «Скрыть в сообщениях» (2026-10-27): four switches in one row that opens in place.
        let hiddenInMessages: [(String, () -> String, WGSetting<Bool>)] = [
            ("appearance.messages.hideEdited", { WGStrings.Appearance.Messages.hiddenEdited }, WGAppearanceSettings.hideEdited),
            ("appearance.messages.hideTime", { WGStrings.Appearance.Messages.hiddenTime }, WGAppearanceSettings.hideTime),
            ("appearance.messages.hideViewCounts", { WGStrings.Appearance.Messages.hiddenViewCounts }, WGAppearanceSettings.hideViewCounts),
            ("appearance.messages.hideChannelComments", { WGStrings.Appearance.Messages.hiddenChannelComments }, WGAppearanceSettings.hideChannelComments)
        ]
        WGMenuRegistry.register(WGMenuRow(id: "appearance.messages.hidden", section: WGAppearanceMenu.messagesInterface, order: 100, title: { WGStrings.Appearance.Messages.hidden }, kind: .expandableList(children: WGAppearanceMenu.hiddenChildren(hiddenInMessages, section: WGAppearanceMenu.messagesInterface), summary: WGAppearanceMenu.hiddenSummary)))
        let toggles: [(String, Int, () -> String, (() -> String)?, WGSetting<Bool>)] = [
            ("appearance.messages.secondsInTime", 300, { WGStrings.Appearance.Messages.secondsInTime }, { WGStrings.Appearance.Messages.secondsInTimeInfo }, WGAppearanceSettings.secondsInTime),
            ("appearance.messages.exactLastSeen", 400, { WGStrings.Appearance.Messages.exactLastSeen }, { WGStrings.Appearance.Messages.exactLastSeenInfo }, WGAppearanceSettings.exactLastSeen),
            ("appearance.messages.wideChannelPosts", 900, { WGStrings.Appearance.Messages.wideChannelPosts }, nil, WGAppearanceSettings.wideChannelPosts),
            ("appearance.messages.authorOnline", 1000, { WGStrings.Appearance.Messages.authorOnline }, { WGStrings.Appearance.Messages.authorOnlineInfo }, WGAppearanceSettings.authorOnlineIndicator),
            ("appearance.messages.colorSwatches", 1100, { WGStrings.Appearance.Messages.colorSwatches }, { WGStrings.Appearance.Messages.colorSwatchesInfo }, WGAppearanceSettings.colorSwatches),
            ("appearance.messages.noSelectionBlur", 1200, { WGStrings.Appearance.Messages.noSelectionBlur }, nil, WGAppearanceSettings.noSelectionBlur)
        ]
        for (id, order, title, subtitle, setting) in toggles {
            WGMenuRegistry.register(WGMenuRow(id: id, section: WGAppearanceMenu.messagesInterface, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting))))
        }
        // Two choices instead of four switches (2026-10-27): where reactions and formatting are hidden.
        WGMenuRegistry.register(WGMenuRow(id: "appearance.messages.hideReactions", section: WGAppearanceMenu.messagesInterface, order: 500, title: { WGStrings.Appearance.Messages.hideReactions }, kind: .choice(.global(WGAppearanceSettings.hideReactions), options: [
            WGMenuChoiceOption(value: WGHiddenReactions.off.rawValue, title: { WGStrings.Appearance.Messages.hiddenNowhere }),
            WGMenuChoiceOption(value: WGHiddenReactions.chats.rawValue, title: { WGStrings.Appearance.Messages.hideReactionsChats }),
            WGMenuChoiceOption(value: WGHiddenReactions.channels.rawValue, title: { WGStrings.Appearance.Messages.hideReactionsChannels }),
            WGMenuChoiceOption(value: WGHiddenReactions.all.rawValue, title: { WGStrings.Appearance.Messages.hiddenEverywhere })
        ])))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.messages.hideFormatting", section: WGAppearanceMenu.messagesInterface, order: 800, title: { WGStrings.Appearance.Messages.hideFormatting }, subtitle: { WGStrings.Appearance.Messages.hideFormattingInfo }, kind: .choice(.global(WGAppearanceSettings.hideFormatting), options: [
            WGMenuChoiceOption(value: WGHiddenFormatting.off.rawValue, title: { WGStrings.Appearance.Messages.hiddenNowhere }),
            WGMenuChoiceOption(value: WGHiddenFormatting.incoming.rawValue, title: { WGStrings.Appearance.Messages.hideFormattingIncoming }),
            WGMenuChoiceOption(value: WGHiddenFormatting.outgoing.rawValue, title: { WGStrings.Appearance.Messages.hideFormattingOutgoing }),
            WGMenuChoiceOption(value: WGHiddenFormatting.all.rawValue, title: { WGStrings.Appearance.Messages.hiddenEverywhere })
        ])))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.messages.tripleTapDelete", section: WGAppearanceMenu.messagesInterface, order: 1300, title: { WGStrings.Appearance.Messages.tripleTapDelete }, kind: .choice(.global(WGAppearanceSettings.tripleTapDelete), options: [
            WGMenuChoiceOption(value: WGTripleTapDelete.off.rawValue, title: { WGStrings.Appearance.Messages.tripleTapOff }),
            WGMenuChoiceOption(value: WGTripleTapDelete.local.rawValue, title: { WGStrings.Appearance.Messages.tripleTapLocal }),
            WGMenuChoiceOption(value: WGTripleTapDelete.everyone.rawValue, title: { WGStrings.Appearance.Messages.tripleTapEveryone })
        ])))

        // «Скрыть в шапке чата» (2026-10-27): the chat's top bar, four switches in one row. The
        // section keeps only its footer: the row's title says what it is.
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGAppearanceMenu.messagesTopBar, screen: .tab(tab), order: 700, footer: { _ in WGStrings.Appearance.TopBar.footer }))
        let hiddenInTopBar: [(String, () -> String, WGSetting<Bool>)] = [
            ("appearance.chatTopBar.hideBackButton", { WGStrings.Appearance.TopBar.backButton }, WGAppearanceSettings.hideBackButton),
            ("appearance.chatTopBar.hideTitle", { WGStrings.Appearance.TopBar.title }, WGAppearanceSettings.hideTitlePanel),
            ("appearance.chatTopBar.hideAvatar", { WGStrings.Appearance.TopBar.avatar }, WGAppearanceSettings.hideAvatar),
            ("appearance.chatTopBar.hidePinned", { WGStrings.Appearance.TopBar.pinned }, WGAppearanceSettings.hidePinnedMessages)
        ]
        WGMenuRegistry.register(WGMenuRow(id: "appearance.chatTopBar.hidden", section: WGAppearanceMenu.messagesTopBar, order: 100, title: { WGStrings.Appearance.TopBar.hidden }, kind: .expandableList(children: WGAppearanceMenu.hiddenChildren(hiddenInTopBar, section: WGAppearanceMenu.messagesTopBar), summary: WGAppearanceMenu.hiddenSummary), searchKeywords: { [WGStrings.Appearance.TopBar.keywords] }))
    }

    /// The switches of a «Скрыть в …» row, in the given order.
    private static func hiddenChildren(_ items: [(String, () -> String, WGSetting<Bool>)], section: WGMenuSectionID) -> [WGMenuRow] {
        var result: [WGMenuRow] = []
        var order = 100
        for (id, title, setting) in items {
            result.append(WGMenuRow(id: id, section: section, order: order, title: title, kind: .toggle(.global(setting))))
            order += 100
        }
        return result
    }

    /// «скрыто: 2 из 4» on the right of a «Скрыть в …» row (nothing while none is hidden).
    static func hiddenSummary(_ count: WGMenuGroupCount) -> String {
        return WGStrings.Appearance.Messages.hiddenCount(selected: "\(count.selected)", total: "\(count.total)")
    }

    // MARK: Font tab

    /// The user's own fonts (owner 2026-10-27), then the system font and its designs, then the
    /// families preinstalled in iOS. Nothing bundled, no font licenses to list.
    private static func registerFont() {
        WGAppearanceMenu.registerCustomFonts()

        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGAppearanceMenu.fontSystem, screen: .tab(WGAppearanceMenu.fontTab), order: 300, header: { WGStrings.Appearance.Font.systemHeader }, footer: { _ in
            if WGFonts.needsRestart {
                return WGStrings.Core.requiresRestartFooter
            }
            return WGStrings.Appearance.Font.systemFooter
        }))
        var order = 100
        for family in [WGFontFamily.system] + WGFonts.designFamilies {
            WGAppearanceMenu.registerFontRow(family: family, section: WGAppearanceMenu.fontSystem, order: order)
            order += 100
        }

        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGAppearanceMenu.fontFamilies, screen: .tab(WGAppearanceMenu.fontTab), order: 400, header: { WGStrings.Appearance.Font.familiesHeader }, footer: { _ in WGStrings.Appearance.Font.familiesFooter }))
        order = 100
        for family in WGFonts.installedFamilies {
            WGAppearanceMenu.registerFontRow(family: family, section: WGAppearanceMenu.fontFamilies, order: order)
            order += 100
        }
    }

    private static func registerFontRow(family: WGFontFamily, section: WGMenuSectionID, order: Int) {
        // «SF Mono», «New York» find the rows of the system designs too.
        let properName = WGFonts.properName(family)
        WGMenuRegistry.register(WGMenuRow(id: "appearance.font.\(family.rawValue)", section: section, order: order, title: { WGFonts.displayName(family) }, kind: .custom({ context in
            return WGAppearanceMenu.fontItem(family: family, context: context)
        }), isVisible: { _ in WGFonts.isAvailable(family) }, searchKeywords: { properName.map { [$0] } ?? [] }))
    }

    /// «Свои шрифты»: a row per added font (fixed slots: the registry is static, the list is a
    /// setting), «Добавить шрифт…» and «Удалить шрифт…».
    private static func registerCustomFonts() {
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGAppearanceMenu.fontCustom, screen: .tab(WGAppearanceMenu.fontTab), order: 200, header: { WGStrings.Appearance.Font.customHeader }, footer: { _ in
            if WGFonts.needsRestart && WGFonts.selectedCustomFont != nil {
                return WGStrings.Core.requiresRestartFooter
            }
            return WGStrings.Appearance.Font.customFooter
        }))
        for index in 0 ..< WGCustomFonts.maximumCount {
            let font: () -> WGCustomFont? = {
                let fonts = WGCustomFonts.fonts
                return index < fonts.count ? fonts[index] : nil
            }
            WGMenuRegistry.register(WGMenuRow(id: "appearance.font.custom.\(index)", section: WGAppearanceMenu.fontCustom, order: 100 + index * 10, title: { font()?.familyName ?? "" }, kind: .custom({ context in
                guard let customFont = font() else {
                    return WGAppearanceMenu.fontItem(family: .system, context: context)
                }
                return WGAppearanceMenu.customFontItem(customFont, context: context)
            }), isVisible: { _ in font() != nil }))
        }
        WGMenuRegistry.register(WGMenuRow(id: "appearance.font.add", section: WGAppearanceMenu.fontCustom, order: 500, title: { WGStrings.Appearance.Font.add }, kind: .action({ context in
            WGPickers.pickFont(context: context)
        }), searchKeywords: { [WGStrings.Appearance.Font.keywords] }))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.font.remove", section: WGAppearanceMenu.fontCustom, order: 600, title: { WGStrings.Appearance.Font.remove }, kind: .action({ context in
            WGAppearanceMenu.presentRemoveFont(context: context)
        }), isVisible: { _ in !WGCustomFonts.fonts.isEmpty }, isDestructive: true))
    }

    private static func customFontItem(_ customFont: WGCustomFont, context: WGMenuContext) -> ListViewItem {
        let presentationData = context.itemListPresentationData
        let sample = WGFonts.sampleImage(customFont: customFont, color: presentationData.theme.list.itemPrimaryTextColor)
        let detail: String? = WGFonts.hasCyrillic(customFont) ? nil : WGStrings.Appearance.Font.noCyrillic
        return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, icon: sample, iconSize: sample?.size, title: customFont.familyName, subtitle: detail, style: .right, checked: WGFonts.selectedCustomFont == customFont, zeroSeparatorInsets: false, sectionId: context.sectionId, action: {
            WGMenuBinding.global(WGAppearanceSettings.fontFamily).set(WGCustomFonts.settingValue(customFont), in: context)
        })
    }

    private static func presentRemoveFont(context: WGMenuContext) {
        let sheet = UIAlertController(title: WGStrings.Appearance.Font.removeTitle, message: nil, preferredStyle: .actionSheet)
        for customFont in WGCustomFonts.fonts {
            sheet.addAction(UIAlertAction(title: customFont.familyName, style: .destructive, handler: { _ in
                WGCustomFonts.remove(customFont)
            }))
        }
        sheet.addAction(UIAlertAction(title: context.presentationData.strings.Common_Cancel, style: .cancel, handler: nil))
        context.presentNative(sheet)
    }

    private static func fontItem(family: WGFontFamily, context: WGMenuContext) -> ListViewItem {
        let presentationData = context.itemListPresentationData
        let isSelected = WGFonts.selectedCustomFont == nil && WGFonts.selectedFamily == family
        let sample = WGFonts.sampleImage(family: family, color: presentationData.theme.list.itemPrimaryTextColor)
        return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, icon: sample, iconSize: sample?.size, title: WGFonts.displayName(family), subtitle: WGFonts.detail(family), style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: context.sectionId, action: {
            WGMenuBinding.global(WGAppearanceSettings.fontFamily).set(family.rawValue, in: context)
        })
    }

    // MARK: «Тема и фон»

    private static func registerTheme() {
        let tab = WGMenuTabID.appearanceThemeBackground

        WGMenuRegistry.register(WGMenuRow(
            id: "appearance.theme.preview",
            section: .preview(of: tab),
            order: 100,
            title: { "" },
            // Live: the theme follows its sliders while dragged; the animated background, the snow
            // and the edge bands are shown as in a chat (U6, U7).
            kind: .preview(.miniChat(WGAppearancePreview.configuration(scope: "appearance.theme", overlays: true, content: { _ in
                return WGAppearancePreview.sampleContent()
            })))
        ))

        let main = WGMenuSectionID.main(of: tab)
        WGMenuRegistry.register(WGMenuRow(id: "appearance.theme.amoled", section: main, order: 100, title: { WGStrings.Appearance.Theme.amoled }, subtitle: { WGStrings.Appearance.Theme.amoledInfo }, kind: .toggle(.global(WGAppearanceSettings.amoled)), searchKeywords: { [WGStrings.Appearance.Theme.amoledKeywords] }))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.theme.amoledKeyboard", section: main, order: 200, title: { WGStrings.Appearance.Theme.amoledKeyboard }, subtitle: { WGStrings.Appearance.Theme.amoledKeyboardInfo }, kind: .toggle(.global(WGAppearanceSettings.amoledKeyboard))))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.theme.hideSeparators", section: main, order: 300, title: { WGStrings.Appearance.Theme.hideSeparators }, kind: .toggle(.global(WGAppearanceSettings.hideSeparators))))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.theme.nameSaturation", section: main, order: 400, title: { WGStrings.Appearance.Theme.nameSaturation }, subtitle: { WGStrings.Appearance.Theme.nameSaturationInfo }, kind: .slider(.global(WGAppearanceSettings.nameColorSaturation), range: 0.0 ... 100.0, step: 5.0, format: WGAppearanceMenu.percent)))

        // «Затемнение краёв» (one group since 2026-10-27): the kind of band, then only what it uses.
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGAppearanceMenu.themeEdges, screen: .tab(tab), order: 400, header: { WGStrings.Appearance.Edges.header }, footer: { _ in WGStrings.Appearance.Edges.footer }))
        let edgeStyle: () -> WGEdgeStyle = { WGEdgeStyle(rawValue: WGAppearanceSettings.edgeStyle.value) ?? .off }
        let edgesOn: (WGMenuContext) -> Bool = { _ in edgeStyle() != .off }
        WGMenuRegistry.register(WGMenuRow(id: "appearance.edges.style", section: WGAppearanceMenu.themeEdges, order: 100, title: { WGStrings.Appearance.Edges.header }, kind: .discreteChoice(.global(WGAppearanceSettings.edgeStyle), options: [
            WGMenuChoiceOption(value: WGEdgeStyle.off.rawValue, title: { WGStrings.Appearance.Edges.styleOff }),
            WGMenuChoiceOption(value: WGEdgeStyle.blur.rawValue, title: { WGStrings.Appearance.Edges.styleBlur }),
            WGMenuChoiceOption(value: WGEdgeStyle.gradient.rawValue, title: { WGStrings.Appearance.Edges.styleGradient })
        ]), searchKeywords: { [WGStrings.Appearance.Edges.keywords] }))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.edges.intensity", section: WGAppearanceMenu.themeEdges, order: 200, title: { WGStrings.Appearance.Edges.intensity }, kind: .slider(.global(WGAppearanceSettings.edgeIntensity), range: 0.0 ... 100.0, step: 5.0, format: WGAppearanceMenu.percent), isVisible: edgesOn))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.edges.size", section: WGAppearanceMenu.themeEdges, order: 300, title: { WGStrings.Appearance.Edges.size }, kind: .slider(.global(WGAppearanceSettings.edgeSize), range: WGEdgeStyle.sizeRange, step: 4.0, format: WGAppearanceMenu.points), isVisible: edgesOn))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.edges.color", section: WGAppearanceMenu.themeEdges, order: 400, title: { WGStrings.Appearance.Edges.color }, kind: .action({ context in
            // The picker starts where the old rows did: the bar's color for the blur, the accent for the gradient.
            let fallback = edgeStyle() == .gradient ? context.presentationData.theme.list.itemAccentColor : context.presentationData.theme.rootController.navigationBar.opaqueBackgroundColor
            WGColorPicker.present(context: context, setting: WGAppearanceSettings.edgeColor, fallback: fallback)
        }), isVisible: edgesOn, label: { _ in WGAppearanceMenu.colorLabel(WGAppearanceSettings.edgeColor) }))
        // Back to «Automatic» (the bar's color, following the theme) once a color was chosen.
        WGMenuRegistry.register(WGMenuRow(id: "appearance.edges.resetColor", section: WGAppearanceMenu.themeEdges, order: 450, title: { WGStrings.Appearance.Edges.resetColor }, kind: .action({ _ in
            WGAppearanceSettings.edgeColor.reset()
        }), isVisible: { context in edgesOn(context) && !WGAppearanceSettings.edgeColor.value.isEmpty }, isDestructive: true))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.edges.hideInChatList", section: WGAppearanceMenu.themeEdges, order: 500, title: { WGStrings.Appearance.Edges.hideInChatList }, kind: .toggle(.global(WGAppearanceSettings.edgeHideInChatList)), isVisible: { _ in edgeStyle() == .gradient }))

        // Animated chat background.
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGAppearanceMenu.themeBackground, screen: .tab(tab), order: 500, header: { WGStrings.Appearance.Background.chatHeader }, footer: { _ in WGStrings.Appearance.Background.footer }))
        WGAppearanceMenu.registerBackgroundRows(kind: .chat, section: WGAppearanceMenu.themeBackground, idPrefix: "appearance.chatBackground")

        // Snowfall.
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGAppearanceMenu.themeSnow, screen: .tab(tab), order: 600, header: { WGStrings.Appearance.Snow.header }, footer: { _ in
            // Says so when the system is what stops the snow right now (the switch alone looked broken).
            if WGAppearanceSettings.snow.value && WGSystemState.current {
                return WGStrings.Appearance.Snow.footer + "\n\n" + WGStrings.Appearance.Snow.pausedNow
            }
            return WGStrings.Appearance.Snow.footer
        }))
        let snowOn: (WGMenuContext) -> Bool = { _ in WGAppearanceSettings.snow.value }
        WGMenuRegistry.register(WGMenuRow(id: "appearance.snow.enabled", section: WGAppearanceMenu.themeSnow, order: 100, title: { WGStrings.Appearance.Snow.enabled }, kind: .toggle(.global(WGAppearanceSettings.snow)), searchKeywords: { [WGStrings.Appearance.Snow.keywords] }))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.snow.style", section: WGAppearanceMenu.themeSnow, order: 200, title: { WGStrings.Appearance.Snow.style }, kind: .choice(.global(WGAppearanceSettings.snowStyle), options: [
            WGMenuChoiceOption(value: WGSnowStyle.snow.rawValue, title: { WGStrings.Appearance.Snow.styleSnow }),
            WGMenuChoiceOption(value: WGSnowStyle.lightning.rawValue, title: { WGStrings.Appearance.Snow.styleLightning })
        ]), isVisible: snowOn))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.snow.intensity", section: WGAppearanceMenu.themeSnow, order: 300, title: { WGStrings.Appearance.Snow.intensity }, kind: .slider(.global(WGAppearanceSettings.snowIntensity), range: 10.0 ... 100.0, step: 5.0, format: WGAppearanceMenu.percent), isVisible: snowOn))
        WGMenuRegistry.register(WGMenuRow(id: "appearance.snow.hideInChats", section: WGAppearanceMenu.themeSnow, order: 400, title: { WGStrings.Appearance.Snow.hideInChats }, kind: .toggle(.global(WGAppearanceSettings.snowHideInChats)), isVisible: snowOn))
    }

    /// Rows of an animated background: on/off (once a file exists), pick, opacity, delete.
    private static func registerBackgroundRows(kind: WGAnimatedBackgroundKind, section: WGMenuSectionID, idPrefix: String) {
        let hasFile: (WGMenuContext) -> Bool = { _ in kind.versionSetting.value != 0 }
        WGMenuRegistry.register(WGMenuRow(id: "\(idPrefix).enabled", section: section, order: 100, title: { WGStrings.Appearance.Background.enabled }, kind: .toggle(.global(kind.enabledSetting)), isVisible: hasFile))
        WGMenuRegistry.register(WGMenuRow(id: "\(idPrefix).pick", section: section, order: 200, title: { WGStrings.Appearance.Background.pick }, subtitle: { WGStrings.Appearance.Background.pickInfo }, kind: .action({ context in
            WGPickers.pickBackground(context: context, kind: kind)
        }), searchKeywords: { [WGStrings.Appearance.Background.keywords] }, label: { _ in
            return kind.versionSetting.value != 0 ? WGStrings.Appearance.Background.isSet : WGStrings.Appearance.Background.notSet
        }))
        WGMenuRegistry.register(WGMenuRow(id: "\(idPrefix).opacity", section: section, order: 300, title: { WGStrings.Appearance.Background.opacity }, kind: .slider(.global(kind.opacitySetting), range: 5.0 ... 100.0, step: 5.0, format: WGAppearanceMenu.percent), isVisible: hasFile))
        WGMenuRegistry.register(WGMenuRow(id: "\(idPrefix).remove", section: section, order: 400, title: { WGStrings.Appearance.Background.remove }, kind: .action({ _ in
            WGAnimatedBackgrounds.remove(kind)
        }), isVisible: hasFile, isDestructive: true))
    }

    // MARK: «Профиль»

    private static func registerProfile() {
        let tab = WGMenuTabID.appearanceProfileSettings
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGAppearanceMenu.profileInfo, screen: .tab(tab), order: 300, header: { WGStrings.Appearance.Profile.header }, footer: { _ in WGStrings.Appearance.Profile.footer }))
        let rows: [(String, () -> String, (() -> String)?, WGSetting<Bool>)] = [
            ("appearance.profile.showId", { WGStrings.Appearance.Profile.showId }, nil, WGAppearanceSettings.profileShowId),
            ("appearance.profile.showDataCenter", { WGStrings.Appearance.Profile.showDataCenter }, { WGStrings.Appearance.Profile.showDataCenterInfo }, WGAppearanceSettings.profileShowDataCenter),
            ("appearance.profile.showDates", { WGStrings.Appearance.Profile.showDates }, { WGStrings.Appearance.Profile.showDatesInfo }, WGAppearanceSettings.profileShowDates),
            ("appearance.profile.hideDescription", { WGStrings.Appearance.Profile.hideDescription }, nil, WGAppearanceSettings.profileHideDescription),
            ("appearance.profile.hideShareButton", { WGStrings.Appearance.Profile.hideShareButton }, nil, WGAppearanceSettings.profileHideShareButton),
            ("appearance.profile.hideStarRating", { WGStrings.Appearance.Profile.hideStarRating }, nil, WGAppearanceSettings.profileHideStarRating)
        ]
        var order = 100
        for (id, title, subtitle, setting) in rows {
            WGMenuRegistry.register(WGMenuRow(id: id, section: WGAppearanceMenu.profileInfo, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting))))
            order += 100
        }

        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGAppearanceMenu.profileBackground, screen: .tab(tab), order: 400, header: { WGStrings.Appearance.Background.profileHeader }, footer: { _ in WGStrings.Appearance.Background.profileFooter }))
        WGAppearanceMenu.registerBackgroundRows(kind: .profile, section: WGAppearanceMenu.profileBackground, idPrefix: "appearance.profileBackground")
    }
}
