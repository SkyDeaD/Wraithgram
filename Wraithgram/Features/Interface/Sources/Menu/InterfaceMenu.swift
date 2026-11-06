import Foundation
import UIKit
import Display
import TelegramPresentationData
import AccountContext
import SettingsUI
import WGCore
import WGSettingsUI
import WGFeaturesShared

/// The zone's part of the menu: «Оформление › Список чатов / Панели / Иконки» and the Settings
/// half of «Профиль и Настройки». Every setting has one row; every row applies at once except the
/// app icon (iOS asks itself) — nothing here restarts the app.
enum InterfaceMenu {
    private static let chatListStories = WGMenuSectionID("appearance.chatList.stories")
    private static let chatListPreviews = WGMenuSectionID("appearance.chatList.previews")
    private static let chatListAvatars = WGMenuSectionID("appearance.chatList.avatars")
    private static let chatListFolders = WGMenuSectionID("appearance.chatList.folders")
    private static let panelsTabBarPreview = WGMenuSectionID("appearance.panels.tabBarPreview")
    private static let panelsTabBar = WGMenuSectionID("appearance.panels.tabBar")
    private static let panelsInput = WGMenuSectionID("appearance.panels.input")
    private static let panelsInputPreview = WGMenuSectionID("appearance.panels.inputPreview")
    private static let panelsTyping = WGMenuSectionID("appearance.panels.typing")
    private static let panelsButtons = WGMenuSectionID("appearance.panels.buttons")
    private static let panelsReactions = WGMenuSectionID("appearance.panels.reactions")
    private static let iconsBadge = WGMenuSectionID("appearance.icons.badge")
    private static let settingsTab = WGMenuSectionID("appearance.profileSettings.settingsTab")

    static func register() {
        InterfaceMenu.registerChatList()
        InterfaceMenu.registerPanels()
        InterfaceMenu.registerIcons()
        InterfaceMenu.registerSettingsTab()
    }

    private static func percent(_ value: Double) -> String {
        return WGStrings.Interface.Menu.percent(value: "\(Int(value.rounded()))")
    }

    private static func points(_ value: Double) -> String {
        return WGStrings.Interface.Menu.points(value: "\(Int(value.rounded()))")
    }

    private static func options(_ values: [String], title: @escaping (String) -> String) -> [WGMenuChoiceOption] {
        return values.map { value in
            return WGMenuChoiceOption(value: value, title: { title(value) })
        }
    }

    // MARK: Список чатов

    private static func registerChatList() {
        let tab = WGMenuTabID.appearanceChatList
        let main = WGMenuSectionID.main(of: tab)

        WGMenuRegistry.register(WGMenuRow(
            id: "interface.chatList.preview",
            section: .preview(of: tab),
            order: 100,
            title: { "" },
            kind: .preview(.miniChatList(WGMiniChatListConfiguration(scope: "interface.chatList", height: 228.0, rows: { _ in
                return WGPreviewChatListRow.samples()
            })))
        ))
        // Hidden previews show in the mini list the way they do in the real one.
        WGPreviewModifiers.registerChatListModifier(id: "interface.hidePreview", order: 100, { rows, context in
            guard context.previewScope == "interface.chatList", InterfaceSettings.hidePreview.value, InterfaceSettings.hidePreviewScope.value == "all" else {
                return
            }
            for index in rows.indices {
                rows[index].text = ""
                rows[index].authorName = nil
            }
        })

        let toggles: [(String, Int, () -> String, (() -> String)?, WGSetting<Bool>, () -> [String])] = [
            ("interface.chatList.compact", 200, { WGStrings.Interface.Menu.compactList }, { WGStrings.Interface.Menu.compactListInfo }, InterfaceSettings.compactList, { [] }),
            ("interface.chatList.senderAvatars", 600, { WGStrings.Interface.Menu.senderAvatars }, { WGStrings.Interface.Menu.senderAvatarsInfo }, InterfaceSettings.senderAvatars, { [] }),
            ("interface.chatList.hideEmojiStatus", 700, { WGStrings.Interface.Menu.hideEmojiStatus }, nil, InterfaceSettings.hideEmojiStatus, { [] }),
            ("interface.chatList.hideSearchField", 800, { WGStrings.Interface.Menu.hideSearchField }, { WGStrings.Interface.Menu.hideSearchFieldInfo }, InterfaceSettings.hideSearchField, { [] }),
            ("interface.chatList.searchById", 900, { WGStrings.Interface.Menu.searchById }, { WGStrings.Interface.Menu.searchByIdInfo }, InterfaceSettings.searchById, { [] }),
            ("interface.chatList.hideConnectionText", 1000, { WGStrings.Interface.Menu.hideConnectionText }, { WGStrings.Interface.Menu.hideConnectionTextInfo }, InterfaceSettings.hideConnectionText, { [] }),
            ("interface.chatList.hideProxySponsor", 1200, { WGStrings.Interface.Menu.hideProxySponsor }, { WGStrings.Interface.Menu.hideProxySponsorInfo }, InterfaceSettings.hideProxySponsor, { [] })
        ]
        for (id, order, title, subtitle, setting, keywords) in toggles {
            WGMenuRegistry.register(WGMenuRow(id: id, section: main, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting)), searchKeywords: keywords))
        }
        WGMenuRegistry.register(WGMenuRow(id: "interface.chatList.previewLines", section: main, order: 300, title: { WGStrings.Interface.Menu.previewLines }, kind: .discreteChoice(.global(InterfaceSettings.previewLines), options: InterfaceMenu.options(["1", "2", "3"], title: { WGStrings.Interface.Menu.number(value: $0) }))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.chatList.rowScale", section: main, order: 400, title: { WGStrings.Interface.Menu.rowScale }, kind: .choice(.global(InterfaceSettings.rowScale), options: InterfaceMenu.options(WGChatListFeature.rowScaleOptions, title: { InterfaceMenu.percent(Double($0) ?? 100.0) }))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.chatList.avatarScale", section: main, order: 500, title: { WGStrings.Interface.Menu.avatarScale }, kind: .choice(.global(InterfaceSettings.avatarScale), options: InterfaceMenu.options(WGChatListFeature.avatarScaleOptions, title: { InterfaceMenu.percent(Double($0) ?? 100.0) }))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.chatList.swipeActions", section: main, order: 1100, title: { WGStrings.Interface.Menu.swipeActions }, kind: .choice(.global(InterfaceSettings.swipeActions), options: [
            WGMenuChoiceOption(value: "all", title: { WGStrings.Interface.Menu.swipeAll }),
            WGMenuChoiceOption(value: "noDelete", title: { WGStrings.Interface.Menu.swipeNoDelete }),
            WGMenuChoiceOption(value: "none", title: { WGStrings.Interface.Menu.swipeNone })
        ])))

        // Stories
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: InterfaceMenu.chatListStories, screen: .tab(tab), order: 300, header: { WGStrings.Interface.Menu.storiesHeader }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.chatList.hideStories", section: InterfaceMenu.chatListStories, order: 100, title: { WGStrings.Interface.Menu.hideStories }, kind: .toggle(.global(InterfaceSettings.hideStories))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.chatList.hideStoryRings", section: InterfaceMenu.chatListStories, order: 200, title: { WGStrings.Interface.Menu.hideStoryRings }, kind: .toggle(.global(InterfaceSettings.hideStoryRings))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.chatList.disableStoryCameraSwipe", section: InterfaceMenu.chatListStories, order: 300, title: { WGStrings.Interface.Menu.disableStoryCameraSwipe }, subtitle: { WGStrings.Interface.Menu.disableStoryCameraSwipeInfo }, kind: .toggle(.global(InterfaceSettings.disableStoryCameraSwipe))))
        let ringColors: [(String, () -> String)] = [
            ("", { WGStrings.Interface.Menu.colorTheme }),
            ("3390EC", { WGStrings.Interface.Menu.colorBlue }),
            ("34C759", { WGStrings.Interface.Menu.colorGreen }),
            ("FF9500", { WGStrings.Interface.Menu.colorOrange }),
            ("FF2D55", { WGStrings.Interface.Menu.colorPink }),
            ("AF52DE", { WGStrings.Interface.Menu.colorPurple }),
            ("FFFFFF", { WGStrings.Interface.Menu.colorWhite }),
            ("8E8E93", { WGStrings.Interface.Menu.colorGray })
        ]
        WGMenuRegistry.register(WGMenuRow(id: "interface.avatars.storyRingColor", section: InterfaceMenu.chatListStories, order: 400, title: { WGStrings.Interface.Menu.storyRingColor }, kind: .choice(.global(InterfaceSettings.storyRingColor), options: ringColors.map { WGMenuChoiceOption(value: $0.0, title: $0.1) }), isVisible: { _ in !InterfaceSettings.hideStoryRings.value }))

        // Message previews
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: InterfaceMenu.chatListPreviews, screen: .tab(tab), order: 400, header: { WGStrings.Interface.Menu.previewsHeader }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.chatList.hidePreview", section: InterfaceMenu.chatListPreviews, order: 100, title: { WGStrings.Interface.Menu.hidePreview }, subtitle: { WGStrings.Interface.Menu.hidePreviewInfo }, kind: .toggle(.global(InterfaceSettings.hidePreview))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.chatList.hidePreviewScope", section: InterfaceMenu.chatListPreviews, order: 200, title: { WGStrings.Interface.Menu.hidePreviewScope }, kind: .choice(.global(InterfaceSettings.hidePreviewScope), options: [
            WGMenuChoiceOption(value: "all", title: { WGStrings.Interface.Menu.scopeAll }),
            WGMenuChoiceOption(value: "selected", title: { WGStrings.Interface.Menu.scopeSelected })
        ]), isVisible: { _ in InterfaceSettings.hidePreview.value }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.chatList.hidePreviewPeers", section: InterfaceMenu.chatListPreviews, order: 300, title: { WGStrings.Interface.ChatList.hiddenPreviewChats }, kind: .action({ menu in
            menu.push(WGHiddenPreviewScreens.makeScreen(context: menu.context))
        }), isVisible: { _ in InterfaceSettings.hidePreview.value && InterfaceSettings.hidePreviewScope.value == "selected" }, label: { menu in
            let count = InterfaceSettings.hidePreviewPeers.value(for: menu.accountID).count
            return count == 0 ? nil : "\(count)"
        }))

        // Avatars
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: InterfaceMenu.chatListAvatars, screen: .tab(tab), order: 500, header: { WGStrings.Interface.Menu.avatarsHeader }, footer: { _ in WGStrings.Interface.Menu.avatarsFooter }))
        // One row since 2026-10-27: the circle is the first stop, the square the last.
        WGMenuRegistry.register(WGMenuRow(id: "interface.avatars.corners", section: InterfaceMenu.chatListAvatars, order: 100, title: { WGStrings.Interface.Menu.squareness }, kind: .discreteChoice(.global(InterfaceSettings.avatarCorners), options: [
            WGMenuChoiceOption(value: WGAvatarCorners.round, title: { WGStrings.Interface.Menu.squarenessNone }),
            WGMenuChoiceOption(value: "25", title: { WGStrings.Interface.Menu.squarenessSlight }),
            WGMenuChoiceOption(value: "50", title: { WGStrings.Interface.Menu.squarenessMedium }),
            WGMenuChoiceOption(value: "75", title: { WGStrings.Interface.Menu.squarenessStrong }),
            WGMenuChoiceOption(value: "100", title: { WGStrings.Interface.Menu.squarenessFull })
        ]), searchKeywords: { [WGStrings.Interface.Menu.squarenessKeywords] }))
        // Forums are drawn as circles with any corner setting, so the switch is always shown.
        WGMenuRegistry.register(WGMenuRow(id: "interface.avatars.roundInForums", section: InterfaceMenu.chatListAvatars, order: 200, title: { WGStrings.Interface.Menu.roundInForums }, kind: .toggle(.global(InterfaceSettings.roundAvatarsInForums))))

        // Folders
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: InterfaceMenu.chatListFolders, screen: .tab(tab), order: 600, header: { WGStrings.Interface.Menu.foldersHeader }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.folders.hideAllChats", section: InterfaceMenu.chatListFolders, order: 100, title: { WGStrings.Interface.Menu.hideAllChats }, subtitle: { WGStrings.Interface.Menu.hideAllChatsInfo }, kind: .toggle(.global(InterfaceSettings.hideAllChats))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.folders.allChatsTitle", section: InterfaceMenu.chatListFolders, order: 200, title: { WGStrings.Interface.Menu.allChatsTitle }, kind: .choice(.global(InterfaceSettings.allChatsTitle), options: [
            WGMenuChoiceOption(value: "default", title: { WGStrings.Interface.Menu.allChatsTitleDefault }),
            WGMenuChoiceOption(value: "long", title: { WGStrings.Interface.Menu.allChatsTitleLong })
        ]), isVisible: { _ in !InterfaceSettings.hideAllChats.value }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.folders.compactTabs", section: InterfaceMenu.chatListFolders, order: 300, title: { WGStrings.Interface.Menu.compactFolderTabs }, kind: .toggle(.global(InterfaceSettings.compactFolderTabs))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.folders.atBottom", section: InterfaceMenu.chatListFolders, order: 400, title: { WGStrings.Interface.Menu.foldersAtBottom }, subtitle: { WGStrings.Interface.Menu.foldersAtBottomInfo }, kind: .toggle(.global(InterfaceSettings.foldersAtBottom))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.folders.barHeightOffset", section: InterfaceMenu.chatListFolders, order: 500, title: { WGStrings.Interface.Menu.folderBarHeight }, kind: .slider(.global(InterfaceSettings.folderBarHeightOffset), range: 0.0 ... 24.0, step: 1.0, format: InterfaceMenu.points)))
        WGMenuRegistry.register(WGMenuRow(id: "interface.folders.rememberLast", section: InterfaceMenu.chatListFolders, order: 600, title: { WGStrings.Interface.Menu.rememberLastFolder }, subtitle: { WGStrings.Interface.Menu.rememberLastFolderInfo }, kind: .toggle(.global(InterfaceSettings.rememberLastFolder))))
    }

    // MARK: Панели

    private static func registerPanels() {
        let tab = WGMenuTabID.appearancePanels

        // Two previews, each under its section's header and over its rows (owner, builds 188–189): the
        // tab bar, the input field.
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: InterfaceMenu.panelsTabBarPreview, screen: .tab(tab), order: 240, header: { WGStrings.Interface.Menu.tabBarHeader }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.panels.preview", section: InterfaceMenu.panelsTabBarPreview, order: 100, title: { "" }, kind: .preview(.custom(height: WGTabBarPreviewView.height, make: { _ in
            return WGTabBarPreviewView(frame: CGRect())
        }))))

        let main = InterfaceMenu.panelsTabBar
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: main, screen: .tab(tab), order: 250))
        WGMenuRegistry.register(WGMenuRow(id: "interface.tabBar.organizer", section: main, order: 100, title: { WGStrings.Interface.TabBar.organizerTitle }, subtitle: { WGStrings.Interface.Menu.tabOrganizerInfo }, kind: .action({ menu in
            menu.push(WGTabBarScreens.makeOrganizer(context: menu.context))
        }), searchKeywords: { [WGStrings.Interface.Menu.tabKeywords] }, label: { _ in
            let changed = !InterfaceSettings.tabOrder.isDefault || !InterfaceSettings.tabTitles.isDefault || !InterfaceSettings.hiddenTabs.isDefault
            return changed ? WGStrings.Interface.Menu.changedLabel : nil
        }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.tabBar.hideTitles", section: main, order: 200, title: { WGStrings.Interface.Menu.hideTabTitles }, subtitle: { WGStrings.Interface.Menu.hideTabTitlesInfo }, kind: .toggle(.global(InterfaceSettings.hideTabTitles))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.tabBar.wide", section: main, order: 300, title: { WGStrings.Interface.Menu.wideTabBar }, kind: .toggle(.global(InterfaceSettings.wideTabBar))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.tabBar.hide", section: main, order: 400, title: { WGStrings.Interface.Menu.hideTabBar }, subtitle: { WGStrings.Interface.Menu.hideTabBarInfo }, kind: .toggle(.global(InterfaceSettings.hideTabBar))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.tabBar.heightOffset", section: main, order: 500, title: { WGStrings.Interface.Menu.tabBarHeight }, kind: .slider(.global(InterfaceSettings.tabBarHeightOffset), range: WGTabBarLayout.heightOffsetRange, step: 1.0, format: InterfaceMenu.points), isVisible: { _ in !InterfaceSettings.hideTabBar.value }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.tabBar.bottomOffset", section: main, order: 600, title: { WGStrings.Interface.Menu.tabBarLift }, kind: .slider(.global(InterfaceSettings.tabBarBottomOffset), range: WGTabBarLayout.bottomOffsetRange, step: 1.0, format: InterfaceMenu.points), isVisible: { _ in !InterfaceSettings.hideTabBar.value }))

        // Input field
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: InterfaceMenu.panelsInputPreview, screen: .tab(tab), order: 290, header: { WGStrings.Interface.Menu.inputHeader }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.panels.inputPreview", section: InterfaceMenu.panelsInputPreview, order: 100, title: { "" }, kind: .preview(.custom(height: WGInputBarPreviewView.height, make: { _ in
            return WGInputBarPreviewView(frame: CGRect())
        }))))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: InterfaceMenu.panelsInput, screen: .tab(tab), order: 300))
        WGMenuRegistry.register(WGMenuRow(id: "interface.inputBar.editor", section: InterfaceMenu.panelsInput, order: 100, title: { WGStrings.Interface.Menu.inputEditor }, subtitle: { WGStrings.Interface.Menu.inputEditorInfo }, kind: .action({ menu in
            WGInputBarEditor.start(context: menu.context, navigationController: menu.navigationController)
        }), label: { _ in
            return InterfaceSettings.inputBarGeometry.isDefault ? nil : WGStrings.Interface.Menu.changedLabel
        }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.inputBar.characterCounter", section: InterfaceMenu.panelsInput, order: 200, title: { WGStrings.Interface.Menu.characterCounter }, subtitle: { WGStrings.Interface.Menu.characterCounterInfo }, kind: .toggle(.global(InterfaceSettings.characterCounter))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.inputBar.formattingToolbar", section: InterfaceMenu.panelsInput, order: 300, title: { WGStrings.Interface.Menu.formattingToolbar }, subtitle: { WGStrings.Interface.Menu.formattingToolbarInfo }, kind: .toggle(.global(InterfaceSettings.formattingToolbar))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.inputBar.autoFormatting", section: InterfaceMenu.panelsInput, order: 400, title: { WGStrings.Interface.Menu.autoFormatting }, subtitle: { WGStrings.Interface.Menu.autoFormattingInfo }, kind: .toggle(.global(InterfaceSettings.autoFormatting))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.inputBar.autoFormattingStyle", section: InterfaceMenu.panelsInput, order: 500, title: { WGStrings.Interface.Menu.autoFormattingStyle }, kind: .choice(.global(InterfaceSettings.autoFormattingStyle), options: InterfaceMenu.options(WGAutoFormatting.styles, title: WGAutoFormatting.title)), isVisible: { _ in InterfaceSettings.autoFormatting.value }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.inputBar.emojiTabFirst", section: InterfaceMenu.panelsInput, order: 600, title: { WGStrings.Interface.Menu.emojiTabFirst }, kind: .toggle(.global(InterfaceSettings.emojiTabFirst))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.inputBar.standardEmojiFirst", section: InterfaceMenu.panelsInput, order: 700, title: { WGStrings.Interface.Menu.standardEmojiFirst }, kind: .toggle(.global(InterfaceSettings.standardEmojiFirst))))

        // Typing animation
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: InterfaceMenu.panelsTyping, screen: .tab(tab), order: 400, header: { WGStrings.Interface.Menu.typingHeader }, footer: { _ in WGStrings.Interface.Menu.typingFooter }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.typingAnimation.enabled", section: InterfaceMenu.panelsTyping, order: 100, title: { WGStrings.Interface.Menu.typingAnimation }, kind: .toggle(.global(InterfaceSettings.typingAnimation))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.typingAnimation.preset", section: InterfaceMenu.panelsTyping, order: 200, title: { WGStrings.Interface.Menu.typingPreset }, kind: .choice(.global(InterfaceSettings.typingAnimationPreset), options: InterfaceMenu.options(WGTypingAnimationParameters.presets, title: InterfaceMenu.presetTitle)), isVisible: { _ in InterfaceSettings.typingAnimation.value }))
        let isCustom: (WGMenuContext) -> Bool = { _ in InterfaceSettings.typingAnimation.value && InterfaceSettings.typingAnimationPreset.value == "custom" }
        let sliders: [(String, Int, () -> String, WGSetting<Double>)] = [
            ("interface.typingAnimation.intensity", 300, { WGStrings.Interface.Menu.typingIntensity }, InterfaceSettings.typingAnimationIntensity),
            ("interface.typingAnimation.speed", 400, { WGStrings.Interface.Menu.typingSpeed }, InterfaceSettings.typingAnimationSpeed),
            ("interface.typingAnimation.scale", 500, { WGStrings.Interface.Menu.typingScale }, InterfaceSettings.typingAnimationScale),
            ("interface.typingAnimation.offset", 600, { WGStrings.Interface.Menu.typingOffset }, InterfaceSettings.typingAnimationOffset),
            ("interface.typingAnimation.glow", 700, { WGStrings.Interface.Menu.typingGlow }, InterfaceSettings.typingAnimationGlow)
        ]
        for (id, order, title, setting) in sliders {
            WGMenuRegistry.register(WGMenuRow(id: id, section: InterfaceMenu.panelsTyping, order: order, title: title, kind: .slider(.global(setting), range: 0.0 ... 100.0, step: 5.0, format: InterfaceMenu.percent), isVisible: isCustom))
        }

        // Quick buttons
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: InterfaceMenu.panelsButtons, screen: .tab(tab), order: 500, header: { WGStrings.Interface.Menu.buttonsHeader }, footer: { _ in WGStrings.Interface.Menu.buttonsFooter }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.bindButtons.enabled", section: InterfaceMenu.panelsButtons, order: 100, title: { WGStrings.Interface.Menu.bindButtons }, kind: .toggle(.global(InterfaceSettings.bindButtons))))
        // The buttons on a full chat preview: dragged into place, width and height by sliders.
        WGMenuRegistry.register(WGMenuRow(id: "interface.bindButtons.layout", section: InterfaceMenu.panelsButtons, order: 150, title: { WGStrings.Interface.Binds.editorTitle }, kind: .action({ menu in
            menu.push(WGQuickButtonsEditorController(context: menu.context))
        }), isVisible: { _ in InterfaceSettings.bindButtons.value }, label: { _ in
            let size = WGQuickButtonsLayout.size()
            let defaultSide = CGFloat(WGQuickButtonsLayout.defaultSide)
            if size.width != defaultSide || size.height != defaultSide {
                return "\(Int(size.width))×\(Int(size.height))"
            }
            return InterfaceSettings.bindButtonsPositions.value.isEmpty ? nil : WGStrings.Interface.Binds.customLayout
        }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.bindButtons.hidden", section: InterfaceMenu.panelsButtons, order: 200, title: { WGStrings.Interface.Binds.buttonsTitle }, kind: .action({ menu in
            menu.push(WGQuickButtonScreens.makeScreen(context: menu.context))
        }), isVisible: { _ in InterfaceSettings.bindButtons.value }, label: { _ in
            let all = WGQuickActions.all.map { $0.id }
            let hidden = Set(InterfaceSettings.bindButtonsHidden.value)
            return "\(all.filter { !hidden.contains($0) }.count)/\(all.count)"
        }))

        // Reactions
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: InterfaceMenu.panelsReactions, screen: .tab(tab), order: 600, header: { WGStrings.Interface.Menu.reactionsHeader }, footer: { _ in WGStrings.Interface.Menu.reactionsFooter }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.customReactions.enabled", section: InterfaceMenu.panelsReactions, order: 100, title: { WGStrings.Interface.Menu.customReactions }, kind: .toggle(.global(InterfaceSettings.customReactions))))
        WGMenuRegistry.register(WGMenuRow(id: "interface.customReactions.list", section: InterfaceMenu.panelsReactions, order: 200, title: { WGStrings.Interface.Reactions.editorTitle }, kind: .action({ menu in
            menu.push(WGReactionScreens.makeEditor(context: menu.context))
        }), isVisible: { _ in InterfaceSettings.customReactions.value }, label: { _ in
            return "\(InterfaceSettings.customReactionsList.value.count)"
        }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.customReactions.appendStandard", section: InterfaceMenu.panelsReactions, order: 300, title: { WGStrings.Interface.Menu.appendStandardReactions }, kind: .toggle(.global(InterfaceSettings.customReactionsAppendStandard)), isVisible: { _ in InterfaceSettings.customReactions.value }))
    }

    private static func presetTitle(_ preset: String) -> String {
        switch preset {
        case "pulse":
            return WGStrings.Interface.Menu.presetPulse
        case "wave":
            return WGStrings.Interface.Menu.presetWave
        case "panelWave":
            return WGStrings.Interface.Menu.presetPanelWave
        case "neon":
            return WGStrings.Interface.Menu.presetNeon
        case "shake":
            return WGStrings.Interface.Menu.presetShake
        default:
            return WGStrings.Interface.Menu.presetCustom
        }
    }

    // MARK: Иконки

    private static func registerIcons() {
        let tab = WGMenuTabID.appearanceIcons
        let main = WGMenuSectionID.main(of: tab)

        WGMenuRegistry.register(WGMenuRow(id: "interface.icons.preview", section: .preview(of: tab), order: 100, title: { "" }, kind: .preview(.custom(height: 176.0, make: { _ in
            return WGIconsPreviewView(frame: CGRect())
        }))))

        // No «Иконка приложения» row: Wraithgram ships one app icon, the ghost (the duck was removed by
        // the owner, 2026-10-28), so there is nothing to choose.
        WGMenuRegistry.register(WGMenuRow(id: "interface.iconPacks", section: main, order: 200, title: { WGStrings.Interface.IconPacks.title }, subtitle: { WGStrings.Interface.Menu.iconPacksInfo }, icon: .bundle("Chat/Context Menu/Apps"), kind: .action({ menu in
            menu.push(WGIconPackScreens.makeListScreen(context: menu.context))
        }), searchKeywords: { [WGStrings.Interface.Menu.iconPacksKeywords] }, label: { _ in
            let count = InterfaceSettings.iconPacks.value.count
            return count == 0 ? WGStrings.Interface.Menu.offLabel : "\(count)"
        }))

        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: InterfaceMenu.iconsBadge, screen: .tab(tab), order: 300, header: { WGStrings.Interface.Menu.badgeHeader }, footer: { _ in
            return WGIslandBadgeGeometry.isSupported ? WGStrings.Interface.Menu.badgeFooter : WGStrings.Interface.Menu.badgeUnsupported
        }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.islandBadge.enabled", section: InterfaceMenu.iconsBadge, order: 100, title: { WGStrings.Interface.Menu.islandBadge }, kind: .toggle(.global(InterfaceSettings.islandBadge)), searchKeywords: { [WGStrings.Interface.Menu.badgeKeywords] }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.islandBadge.selection", section: InterfaceMenu.iconsBadge, order: 200, title: { WGStrings.Interface.Badge.galleryTitle }, kind: .action({ menu in
            menu.push(WGBadgeGallery.makeScreen(context: menu.context))
        }), label: { _ in
            let selection = InterfaceSettings.islandBadgeSelection.value
            return WGBadgeStore.isValidId(selection) ? WGStrings.Interface.Menu.ownBadgeLabel : WGStrings.Interface.Badge.bundledName
        }))
    }

    // MARK: Вкладка «Настройки»

    private static func registerSettingsTab() {
        let tab = WGMenuTabID.appearanceProfileSettings
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: InterfaceMenu.settingsTab, screen: .tab(tab), order: 500, header: { WGStrings.Interface.Menu.settingsTabHeader }, footer: { _ in WGStrings.Interface.Menu.settingsTabFooter }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.settingsTab.items", section: InterfaceMenu.settingsTab, order: 100, title: { WGStrings.Interface.SettingsTab.itemsTitle }, subtitle: { WGStrings.Interface.Menu.settingsItemsInfo }, kind: .action({ menu in
            menu.push(WGSettingsTabScreens.makeScreen(context: menu.context))
        }), searchKeywords: { [WGStrings.Interface.Menu.settingsItemsKeywords] }, label: { _ in
            let count = InterfaceSettings.hiddenSettingsItems.value.count
            return count == 0 ? nil : WGStrings.Interface.Menu.hiddenCount(count: count)
        }))
        WGMenuRegistry.register(WGMenuRow(id: "interface.settingsTab.shortcuts", section: InterfaceMenu.settingsTab, order: 200, title: { WGStrings.Interface.Shortcuts.title }, subtitle: { WGStrings.Interface.Menu.shortcutsInfo }, kind: .action({ menu in
            menu.push(WGShortcutScreens.makeScreen(context: menu.context))
        }), searchKeywords: { [WGStrings.Interface.Menu.shortcutsKeywords] }, label: { menu in
            let count = InterfaceSettings.settingsShortcuts.value(for: menu.accountID).count
            return count == 0 ? nil : "\(count)"
        }))
    }
}
