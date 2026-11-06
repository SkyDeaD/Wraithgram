import Foundation
import WGCore

// Every setting of the Interface zone (chat list, folders, tab bar, input panel, icons, the
// Settings tab), declared once. Defaults live here and nowhere else; user toggles are off.
// Keys: `interface.<feature>.<key>` (strings use the same `interface` namespace).

/// Geometry of the chat input panel (input bar editor). Zero = upstream layout.
struct WGInputBarGeometry: Codable, Equatable, WGSettingValue {
    /// Extra height of the text field, pt (0…100).
    var heightPadding: Double
    /// Insets of the text field from the left / right edge, pt (0…160).
    var leftMargin: Double
    var rightMargin: Double
    /// Lift of the whole panel above the bottom edge, pt (0…220).
    var bottomOffset: Double
    /// Free offsets of the attachment, emoji (accessory) and send / record buttons, pt.
    var attachX: Double
    var attachY: Double
    var accessoryX: Double
    var accessoryY: Double
    var sendX: Double
    var sendY: Double

    static let zero = WGInputBarGeometry(heightPadding: 0.0, leftMargin: 0.0, rightMargin: 0.0, bottomOffset: 0.0, attachX: 0.0, attachY: 0.0, accessoryX: 0.0, accessoryY: 0.0, sendX: 0.0, sendY: 0.0)

    var isZero: Bool {
        return self == WGInputBarGeometry.zero
    }

    static let heightPaddingRange: ClosedRange<Double> = 0.0 ... 100.0
    static let marginRange: ClosedRange<Double> = 0.0 ... 160.0
    static let bottomOffsetRange: ClosedRange<Double> = 0.0 ... 220.0
    static let buttonXRange: ClosedRange<Double> = -120.0 ... 120.0
    static let buttonYRange: ClosedRange<Double> = -80.0 ... 80.0

    /// Clamped to the editor's ranges (an imported file may hold anything).
    var clamped: WGInputBarGeometry {
        func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
            return min(range.upperBound, max(range.lowerBound, value))
        }
        return WGInputBarGeometry(
            heightPadding: clamp(self.heightPadding, WGInputBarGeometry.heightPaddingRange),
            leftMargin: clamp(self.leftMargin, WGInputBarGeometry.marginRange),
            rightMargin: clamp(self.rightMargin, WGInputBarGeometry.marginRange),
            bottomOffset: clamp(self.bottomOffset, WGInputBarGeometry.bottomOffsetRange),
            attachX: clamp(self.attachX, WGInputBarGeometry.buttonXRange),
            attachY: clamp(self.attachY, WGInputBarGeometry.buttonYRange),
            accessoryX: clamp(self.accessoryX, WGInputBarGeometry.buttonXRange),
            accessoryY: clamp(self.accessoryY, WGInputBarGeometry.buttonYRange),
            sendX: clamp(self.sendX, WGInputBarGeometry.buttonXRange),
            sendY: clamp(self.sendY, WGInputBarGeometry.buttonYRange)
        )
    }
}

/// A row pinned to Telegram's Settings tab («Ярлыки»).
struct WGSettingsShortcut: Codable, Equatable, WGSettingValue {
    enum Kind: String, Codable {
        case chat
        case miniApp
        case site
    }

    /// `chat:<peer>`, `miniApp:<peer>` or `site:<normalized url>`. Unique within the list.
    var id: String
    var kind: Kind
    var peer: WGPeerKey?
    /// Normalized absolute http(s) URL for sites.
    var url: String?
    /// User title for sites; chats and mini apps always show the peer's current name.
    var title: String?
}

enum InterfaceSettings {
    // MARK: Chat list (chatlist_tweaks, SG-B1…B5)

    /// SG-B1: smaller rows and avatars.
    static let compactList = WGSetting<Bool>("interface.chatList.compact", default: false)
    /// SG-B2: lines of message preview, "1" / "2" / "3". "2" is Telegram's layout.
    static let previewLines = WGSetting<String>("interface.chatList.previewLines", default: "2")
    /// Row height in percent of Telegram's ("80" … "130").
    static let rowScale = WGSetting<String>("interface.chatList.rowScale", default: "100")
    /// Avatar size in percent of Telegram's ("70" … "120").
    static let avatarScale = WGSetting<String>("interface.chatList.avatarScale", default: "100")
    static let hideEmojiStatus = WGSetting<Bool>("interface.chatList.hideEmojiStatus", default: false)
    static let hideSearchField = WGSetting<Bool>("interface.chatList.hideSearchField", default: false)
    /// A small avatar of the sender before the preview text (groups).
    static let senderAvatars = WGSetting<Bool>("interface.chatList.senderAvatars", default: false)
    static let hidePreview = WGSetting<Bool>("interface.chatList.hidePreview", default: false)
    /// "all" or "selected" (the chats in `hidePreviewPeers`).
    static let hidePreviewScope = WGSetting<String>("interface.chatList.hidePreviewScope", default: "all")
    static let hidePreviewPeers = WGAccountSetting<Set<WGPeerKey>>("interface.chatList.hidePreviewPeers", default: [])
    /// SG-B3: "all" (Telegram), "noDelete", "none".
    static let swipeActions = WGSetting<String>("interface.chatList.swipeActions", default: "all")
    /// SG-B4.
    static let disableStoryCameraSwipe = WGSetting<Bool>("interface.chatList.disableStoryCameraSwipe", default: false)
    /// SG-B5: no stories strip above the list.
    static let hideStories = WGSetting<Bool>("interface.chatList.hideStories", default: false)
    /// No story rings around the avatars of the rows.
    static let hideStoryRings = WGSetting<Bool>("interface.chatList.hideStoryRings", default: false)
    static let hideProxySponsor = WGSetting<Bool>("interface.chatList.hideProxySponsor", default: false)
    /// Only the spinner while connecting, no «Соединение…» text.
    static let hideConnectionText = WGSetting<Bool>("interface.chatList.hideConnectionText", default: false)
    /// A numeric query in the chat list search also looks the id up. On by default: Swiftgram does it
    /// always (W6-SGD, owner's decision 2026-10-29).
    static let searchById = WGSetting<Bool>("interface.chatList.searchById", default: true)

    // MARK: Avatars (square_avatars)

    /// «Скругление углов»: "0" = Telegram's circle, "25"…"100" = how far from a circle the shape
    /// goes (`WGAvatarCorners`). Replaced «Квадратные аватары» + its level on 2026-10-27.
    static let avatarCorners = WGSetting<String>("interface.avatars.corners", default: WGAvatarCorners.round)
    static let roundAvatarsInForums = WGSetting<Bool>("interface.avatars.roundInForums", default: false)
    /// "" = the theme's colors, otherwise "RRGGBB".
    static let storyRingColor = WGSetting<String>("interface.avatars.storyRingColor", default: "")

    // MARK: Folders (folders_tweaks, SG-A5…A9)

    /// SG-A5: the folder strip above the tab bar (`WGChatListFolderStrip.atBottom`).
    static let foldersAtBottom = WGSetting<Bool>("interface.folders.atBottom", default: false)
    /// Service: the old client's `ExperimentalUISettings.foldersTabAtBottom` was read once.
    static let foldersAtBottomImported = WGSetting<Bool>("interface.folders.atBottomImported", default: false, flags: [.noExport])
    static let hideAllChats = WGSetting<Bool>("interface.folders.hideAllChats", default: false)
    static let compactFolderTabs = WGSetting<Bool>("interface.folders.compactTabs", default: false)
    /// "default" (Telegram's «Все») or "long" («Все чаты»).
    static let allChatsTitle = WGSetting<String>("interface.folders.allChatsTitle", default: "default")
    static let rememberLastFolder = WGSetting<Bool>("interface.folders.rememberLast", default: false)
    /// The folder the list showed last, per account: 0 = «Все чаты», otherwise the filter id.
    static let lastFolder = WGAccountSetting<Int32>("interface.folders.lastFolder", default: 0, flags: [.noExport])
    /// Extra height of the folder tab strip, pt (0…24).
    static let folderBarHeightOffset = WGSetting<Double>("interface.folders.barHeightOffset", default: 0.0)

    // MARK: Tab bar (tabbar_tweaks, SG-A1…A4)

    /// Order of the tab ids: "contacts", "calls", "chats", "settings".
    static let tabOrder = WGSetting<[String]>("interface.tabBar.order", default: WGTabBarLayout.defaultOrder)
    /// Own labels by tab id.
    static let tabTitles = WGSetting<[String: String]>("interface.tabBar.titles", default: [:])
    /// Tabs taken out of the bar ("contacts", "calls"); the chat list and Settings always stay.
    static let hiddenTabs = WGSetting<[String]>("interface.tabBar.hidden", default: [])
    static let hideTabTitles = WGSetting<Bool>("interface.tabBar.hideTitles", default: false)
    static let wideTabBar = WGSetting<Bool>("interface.tabBar.wide", default: false)
    static let hideTabBar = WGSetting<Bool>("interface.tabBar.hide", default: false)
    /// Extra height of the bar and its lift above the bottom edge, pt.
    static let tabBarHeightOffset = WGSetting<Double>("interface.tabBar.heightOffset", default: 0.0)
    static let tabBarBottomOffset = WGSetting<Double>("interface.tabBar.bottomOffset", default: 0.0)

    // MARK: Input panel (input_bar_editor, typing_animation, SG-F11, SG-G9)

    static let inputBarGeometry = WGSetting<WGInputBarGeometry>("interface.inputBar.geometry", default: .zero)
    static let characterCounter = WGSetting<Bool>("interface.inputBar.characterCounter", default: false)
    /// SG-F11: the formatting toolbar above the keyboard, in every composer.
    static let formattingToolbar = WGSetting<Bool>("interface.inputBar.formattingToolbar", default: false)
    static let autoFormatting = WGSetting<Bool>("interface.inputBar.autoFormatting", default: false)
    /// "bold", "italic", "monospace", "strikethrough", "underline", "spoiler", "quote", "code".
    static let autoFormattingStyle = WGSetting<String>("interface.inputBar.autoFormattingStyle", default: "bold")
    /// SG-G9.
    static let emojiTabFirst = WGSetting<Bool>("interface.inputBar.emojiTabFirst", default: false)
    static let standardEmojiFirst = WGSetting<Bool>("interface.inputBar.standardEmojiFirst", default: false)

    static let typingAnimation = WGSetting<Bool>("interface.typingAnimation.enabled", default: false)
    /// "pulse", "wave", "panelWave", "neon", "shake", "custom".
    static let typingAnimationPreset = WGSetting<String>("interface.typingAnimation.preset", default: "wave")
    static let typingAnimationIntensity = WGSetting<Double>("interface.typingAnimation.intensity", default: 55.0)
    static let typingAnimationSpeed = WGSetting<Double>("interface.typingAnimation.speed", default: 55.0)
    static let typingAnimationScale = WGSetting<Double>("interface.typingAnimation.scale", default: 45.0)
    static let typingAnimationOffset = WGSetting<Double>("interface.typingAnimation.offset", default: 45.0)
    static let typingAnimationGlow = WGSetting<Double>("interface.typingAnimation.glow", default: 55.0)

    // MARK: Quick buttons in a chat (bind_buttons)

    static let bindButtons = WGSetting<Bool>("interface.bindButtons.enabled", default: false)
    /// Action ids switched off by the user (all registered actions show by default once the
    /// master switch is on — the master is the feature toggle and is off by default).
    static let bindButtonsHidden = WGSetting<[String]>("interface.bindButtons.hidden", default: [])
    /// Where each button stands: action id → [x, y], its centre in the chat's free area, 0…1
    /// (`WGQuickButtonsLayout`). A button without an entry stands in the column on the right.
    /// Written by «Расположение и размер» (`WGQuickButtonsEditorController`).
    static let bindButtonsPositions = WGSetting<[String: [Double]]>("interface.bindButtons.positions", default: [:])
    /// Size of every button, pt (`WGQuickButtonsLayout.sideRange`).
    static let bindButtonsWidth = WGSetting<Double>("interface.bindButtons.width", default: WGQuickButtonsLayout.defaultSide)
    static let bindButtonsHeight = WGSetting<Double>("interface.bindButtons.height", default: WGQuickButtonsLayout.defaultSide)

    // MARK: Custom recent reactions (custom_recent_reactions)

    static let customReactions = WGSetting<Bool>("interface.customReactions.enabled", default: false)
    /// "e:<emoji>" for builtin reactions, "doc:<file id>" for custom emoji (the old wire format).
    static let customReactionsList = WGSetting<[String]>("interface.customReactions.list", default: WGCustomReactions.defaultList)
    /// Telegram's own top reactions after the custom set.
    static let customReactionsAppendStandard = WGSetting<Bool>("interface.customReactions.appendStandard", default: false)

    // MARK: Icon packs (icon_packs)

    /// Enabled packs, highest priority first. Empty = Telegram's icons.
    static let iconPacks = WGSetting<[String]>("interface.iconPacks.enabled", default: [])

    // MARK: Badge under the cutout (app_icons_badges, SG-I2)

    /// On by default, as in the old client: the Wraithgram badge takes the place of Telegram's,
    /// which is never shown (`WGIslandBadge`).
    static let islandBadge = WGSetting<Bool>("interface.islandBadge.enabled", default: true)
    /// "wraithgram" (bundled) or the id of a studio badge.
    static let islandBadgeSelection = WGSetting<String>("interface.islandBadge.selection", default: "wraithgram")

    // MARK: Telegram's Settings tab (settings_structure)

    /// Telegram rows hidden from the Settings tab (`WGSettingsTabItem.rawValue`).
    static let hiddenSettingsItems = WGSetting<[String]>("interface.settingsTab.hidden", default: [])
    /// Order of Telegram's rows inside their sections; empty = Telegram's order.
    static let settingsItemsOrder = WGSetting<[String]>("interface.settingsTab.order", default: [])
    static let settingsShortcuts = WGAccountSetting<[WGSettingsShortcut]>("interface.settingsTab.shortcuts", default: [])

    /// Called from `WGInterfaceModule.register()`: the registry must know every setting before
    /// export, search and migrations run.
    static func declare() {
        let _ = InterfaceSettings.compactList
        let _ = InterfaceSettings.previewLines
        let _ = InterfaceSettings.rowScale
        let _ = InterfaceSettings.avatarScale
        let _ = InterfaceSettings.hideEmojiStatus
        let _ = InterfaceSettings.hideSearchField
        let _ = InterfaceSettings.senderAvatars
        let _ = InterfaceSettings.hidePreview
        let _ = InterfaceSettings.hidePreviewScope
        let _ = InterfaceSettings.hidePreviewPeers
        let _ = InterfaceSettings.swipeActions
        let _ = InterfaceSettings.disableStoryCameraSwipe
        let _ = InterfaceSettings.hideStories
        let _ = InterfaceSettings.hideStoryRings
        let _ = InterfaceSettings.hideProxySponsor
        let _ = InterfaceSettings.hideConnectionText
        let _ = InterfaceSettings.searchById

        let _ = InterfaceSettings.avatarCorners
        let _ = InterfaceSettings.roundAvatarsInForums
        let _ = InterfaceSettings.storyRingColor

        let _ = InterfaceSettings.foldersAtBottom
        let _ = InterfaceSettings.foldersAtBottomImported
        let _ = InterfaceSettings.hideAllChats
        let _ = InterfaceSettings.compactFolderTabs
        let _ = InterfaceSettings.allChatsTitle
        let _ = InterfaceSettings.rememberLastFolder
        let _ = InterfaceSettings.lastFolder
        let _ = InterfaceSettings.folderBarHeightOffset

        let _ = InterfaceSettings.tabOrder
        let _ = InterfaceSettings.tabTitles
        let _ = InterfaceSettings.hiddenTabs
        let _ = InterfaceSettings.hideTabTitles
        let _ = InterfaceSettings.wideTabBar
        let _ = InterfaceSettings.hideTabBar
        let _ = InterfaceSettings.tabBarHeightOffset
        let _ = InterfaceSettings.tabBarBottomOffset

        let _ = InterfaceSettings.inputBarGeometry
        let _ = InterfaceSettings.characterCounter
        let _ = InterfaceSettings.formattingToolbar
        let _ = InterfaceSettings.autoFormatting
        let _ = InterfaceSettings.autoFormattingStyle
        let _ = InterfaceSettings.emojiTabFirst
        let _ = InterfaceSettings.standardEmojiFirst

        let _ = InterfaceSettings.typingAnimation
        let _ = InterfaceSettings.typingAnimationPreset
        let _ = InterfaceSettings.typingAnimationIntensity
        let _ = InterfaceSettings.typingAnimationSpeed
        let _ = InterfaceSettings.typingAnimationScale
        let _ = InterfaceSettings.typingAnimationOffset
        let _ = InterfaceSettings.typingAnimationGlow

        let _ = InterfaceSettings.bindButtons
        let _ = InterfaceSettings.bindButtonsHidden
        let _ = InterfaceSettings.bindButtonsPositions
        let _ = InterfaceSettings.bindButtonsWidth
        let _ = InterfaceSettings.bindButtonsHeight

        let _ = InterfaceSettings.customReactions
        let _ = InterfaceSettings.customReactionsList
        let _ = InterfaceSettings.customReactionsAppendStandard

        let _ = InterfaceSettings.iconPacks

        let _ = InterfaceSettings.islandBadge
        let _ = InterfaceSettings.islandBadgeSelection

        let _ = InterfaceSettings.hiddenSettingsItems
        let _ = InterfaceSettings.settingsItemsOrder
        let _ = InterfaceSettings.settingsShortcuts
    }
}
