import Foundation
import UIKit
import WGFeaturesShared
import WGCore

// One-time moves of the old Wraithgram's keys (FontCustomization / SGSimpleSettings / MiscSettings
// / raw WG.*) into InterfaceSettings. Only what this zone carries over; dead keys
// (`tabBarUnifiedSearch`, `chatListGradient*`, `readStatusColor*`) are not read.
enum InterfaceMigrations {
    /// The old client's Settings shortcuts, read by the global migration of this launch (in memory
    /// only: they go to the accounts that start in this launch, see `register()`).
    private static let legacyShortcutsLock = NSLock()
    private static var legacyShortcuts: [WGSettingsShortcut] = []

    private static func setLegacyShortcuts(_ shortcuts: [WGSettingsShortcut]) {
        InterfaceMigrations.legacyShortcutsLock.lock()
        InterfaceMigrations.legacyShortcuts = shortcuts
        InterfaceMigrations.legacyShortcutsLock.unlock()
    }

    private static func currentLegacyShortcuts() -> [WGSettingsShortcut] {
        InterfaceMigrations.legacyShortcutsLock.lock()
        defer {
            InterfaceMigrations.legacyShortcutsLock.unlock()
        }
        return InterfaceMigrations.legacyShortcuts
    }

    static func register() {
        WGMigrations.registerGlobal(id: "interface.chatList.v1") { legacy in
            InterfaceMigrations.moveBool(legacy, "compactChatList", to: InterfaceSettings.compactList)
            // Swiftgram counts the title line too: its "3" (the default) is Telegram's two lines of
            // text, and the old client made anything below "3" one line of text.
            if let lines = legacy.string("chatListLines"), ["1", "2", "3"].contains(lines) {
                if lines != "3" {
                    InterfaceSettings.previewLines.set("1")
                }
            } else if legacy.bool("compactMessagePreview") == true {
                InterfaceSettings.previewLines.set("1")
            }
            legacy.removeLegacyKey("chatListLines")
            legacy.removeLegacyKey("compactMessagePreview")

            if let scale = legacy.int("GG.fontCustomization.chatListItemScale") {
                InterfaceSettings.rowScale.set(InterfaceMigrations.nearestOption(Double(scale), options: WGChatListFeature.rowScaleOptions))
                legacy.removeLegacyKey("GG.fontCustomization.chatListItemScale")
            }
            // The old slider: 0…100, 50 = Telegram's size, otherwise 20…80 pt.
            if let size = legacy.int("GG.avatarSize"), size != 50 {
                let points = 20.0 + Double(max(0, min(100, size))) * 0.6
                InterfaceSettings.avatarScale.set(InterfaceMigrations.nearestOption(points / 60.0 * 100.0, options: WGChatListFeature.avatarScaleOptions))
            }
            legacy.removeLegacyKey("GG.avatarSize")

            InterfaceMigrations.moveBool(legacy, "hideEmojiStatusInChatSelection", to: InterfaceSettings.hideEmojiStatus)
            InterfaceMigrations.moveBool(legacy, "GG.fontCustomization.hideChatListSearchBar", to: InterfaceSettings.hideSearchField)
            InterfaceMigrations.moveBool(legacy, "GG.fontCustomization.senderMiniAvatars", to: InterfaceSettings.senderAvatars)
            InterfaceMigrations.moveBool(legacy, "GG.hideMessagePreview", to: InterfaceSettings.hidePreview)
            if let scope = legacy.string("GG.hideMessagePreview.scope"), scope == "selected" {
                InterfaceSettings.hidePreviewScope.set("selected")
            }
            legacy.removeLegacyKey("GG.hideMessagePreview.scope")

            // SG-B3: two inverted keys become one honest choice.
            let disableAll = legacy.bool("disableChatSwipeOptions") ?? false
            let disableDelete = legacy.bool("disableDeleteChatSwipeOption") ?? false
            if disableAll {
                InterfaceSettings.swipeActions.set("none")
            } else if disableDelete {
                InterfaceSettings.swipeActions.set("noDelete")
            }
            legacy.removeLegacyKey("disableChatSwipeOptions")
            legacy.removeLegacyKey("disableDeleteChatSwipeOption")

            InterfaceMigrations.moveBool(legacy, "disableSwipeToRecordStory", to: InterfaceSettings.disableStoryCameraSwipe)
            InterfaceMigrations.moveBool(legacy, "hideStories", to: InterfaceSettings.hideStories)
            InterfaceMigrations.moveBool(legacy, "GG.fontCustomization.hideStoryCirclesInChatList", to: InterfaceSettings.hideStoryRings)
            InterfaceMigrations.moveBool(legacy, "hideProxySponsor", to: InterfaceSettings.hideProxySponsor)
            if let show = legacy.bool("FontCustomization.showConnectionStatusText") {
                InterfaceSettings.hideConnectionText.set(!show)
                legacy.removeLegacyKey("FontCustomization.showConnectionStatusText")
            }
            // «Вид Android» is not carried over (removed, owner 2026-10-28).
            legacy.removeLegacyKey("GG.ggdroid.androidChatList")
        }

        // Builds ≤ 194 moved Swiftgram's `chatListLines` "3" over as three lines of text, so every
        // row of an updated client was a line taller (owner, 2026-10-29). The one-line move above
        // never writes "3", so a "3" here came from that move or from the menu; both go back to
        // Telegram's two lines.
        WGMigrations.registerGlobal(id: "interface.chatList.previewLines.sgLines.v1") { _ in
            if InterfaceSettings.previewLines.value == "3" {
                InterfaceSettings.previewLines.reset()
            }
        }

        WGMigrations.registerAccount(id: "interface.chatList.hiddenPreviews.v1") { legacy, account in
            // Stored globally by the old client (Int64 of PeerId.toInt64() as strings); every
            // account gets the list, ids of another account's chats simply never match.
            guard let raw = legacy.stringArray("GG.hideMessagePreview.selectedPeerIds") else {
                return
            }
            var keys = Set<WGPeerKey>()
            for item in raw {
                if let value = Int64(item) {
                    keys.insert(WGLegacyKeys.peerKey(fromLegacyInt64: value))
                }
            }
            if !keys.isEmpty {
                InterfaceSettings.hidePreviewPeers.set(keys, for: account)
            }
        }

        WGMigrations.registerGlobal(id: "interface.avatars.v1") { legacy in
            // Square avatars and their level are one setting since 2026-10-27 (`WGAvatarCorners`).
            if let corners = WGAvatarCorners.fromLegacy(square: legacy.bool("FontCustomization.squareAvatarsInChatList"), level: legacy.int("FontCustomization.avatarSquarenessLevel")) {
                InterfaceSettings.avatarCorners.set(corners)
            }
            legacy.removeLegacyKey("FontCustomization.squareAvatarsInChatList")
            legacy.removeLegacyKey("FontCustomization.avatarSquarenessLevel")
            InterfaceMigrations.moveBool(legacy, "FontCustomization.roundAvatarsInForums", to: InterfaceSettings.roundAvatarsInForums)
            if let color = legacy.string("GG.fontCustomization.storyCircleColor"), let normalized = WGColorHex.normalized(color) {
                InterfaceSettings.storyRingColor.set(normalized)
            }
            legacy.removeLegacyKey("GG.fontCustomization.storyCircleColor")
        }

        // Builds ≤ 185 had «Квадратные аватары» and «Скругление углов» as two settings; one since
        // 2026-10-27 (square = the last stop of the rounding).
        WGMigrations.registerGlobal(id: "interface.avatars.corners.v1") { _ in
            let square = WGRetiredSettings.value("interface.avatars.square", as: Bool.self)
            let squareness = WGRetiredSettings.value("interface.avatars.squareness", as: String.self)
            if let corners = WGAvatarCorners.merged(square: square, squareness: squareness) {
                InterfaceSettings.avatarCorners.set(corners)
            }
            WGRetiredSettings.remove(keys: ["interface.avatars.square", "interface.avatars.squareness"])
        }

        WGMigrations.registerGlobal(id: "interface.folders.v1") { legacy in
            InterfaceMigrations.moveBool(legacy, "allChatsHidden", to: InterfaceSettings.hideAllChats)
            InterfaceMigrations.moveBool(legacy, "compactFolderNames", to: InterfaceSettings.compactFolderTabs)
            // Telegram's strip now always says «Все»: "short" is the default, only "long" differs.
            if let value = legacy.string("allChatsTitleLengthOverride"), value == "long" {
                InterfaceSettings.allChatsTitle.set(value)
            }
            legacy.removeLegacyKey("allChatsTitleLengthOverride")
            InterfaceMigrations.moveBool(legacy, "rememberLastFolder", to: InterfaceSettings.rememberLastFolder)
            if let offset = legacy.int("FontCustomization.folderBarHeightOffset") {
                InterfaceSettings.folderBarHeightOffset.set(min(24.0, max(0.0, Double(offset))))
                legacy.removeLegacyKey("FontCustomization.folderBarHeightOffset")
            }
            // `FontCustomization.folderBarBottomOffset` lifted the strip into the list; the new
            // strip has one height control (see the report) — the lift is not carried over.
            legacy.removeLegacyKey("FontCustomization.folderBarBottomOffset")
            legacy.removeLegacyKey("lastAccountFolders")
        }

        WGMigrations.registerGlobal(id: "interface.tabBar.v1") { legacy in
            if let order = legacy.stringArray("tabBarItemOrder") {
                InterfaceSettings.tabOrder.set(WGTabBarLayout.normalizedOrder(order))
                legacy.removeLegacyKey("tabBarItemOrder")
            }
            if let titles = legacy.object("tabBarCustomTitles") as? [String: String] {
                var result: [String: String] = [:]
                for (key, value) in titles where WGTabBarLayout.allIds.contains(key) {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        result[key] = trimmed
                    }
                }
                InterfaceSettings.tabTitles.set(result)
                legacy.removeLegacyKey("tabBarCustomTitles")
            }
            if let show = legacy.bool("showTabNames") {
                InterfaceSettings.hideTabTitles.set(!show)
                legacy.removeLegacyKey("showTabNames")
            }
            InterfaceMigrations.moveBool(legacy, "wideTabBar", to: InterfaceSettings.wideTabBar)
            InterfaceMigrations.moveBool(legacy, "hideTabBar", to: InterfaceSettings.hideTabBar)
            if let value = legacy.int("tabBarHeightOffset") {
                InterfaceSettings.tabBarHeightOffset.set(WGTabBarLayout.clampHeightOffset(Double(value)))
                legacy.removeLegacyKey("tabBarHeightOffset")
            }
            if let value = legacy.int("tabBarBottomOffset") {
                InterfaceSettings.tabBarBottomOffset.set(WGTabBarLayout.clampBottomOffset(Double(value)))
                legacy.removeLegacyKey("tabBarBottomOffset")
            }
        }

        WGMigrations.registerGlobal(id: "interface.inputBar.v1") { legacy in
            var geometry = WGInputBarGeometry.zero
            var found = false
            func read(_ key: String) -> Double {
                if let value = legacy.int("GG.fontCustomization." + key) {
                    found = true
                    legacy.removeLegacyKey("GG.fontCustomization." + key)
                    return Double(value)
                }
                return 0.0
            }
            geometry.heightPadding = read("inputBarHeightPadding")
            geometry.leftMargin = read("inputBarLeftMargin")
            geometry.rightMargin = read("inputBarRightMargin")
            geometry.bottomOffset = read("inputBarBottomOffset")
            geometry.attachX = read("inputBarLeftButtonOffsetX")
            geometry.attachY = read("inputBarLeftButtonOffsetY")
            geometry.accessoryX = read("inputBarAccessoryButtonOffsetX")
            geometry.accessoryY = read("inputBarAccessoryButtonOffsetY")
            geometry.sendX = read("inputBarRightButtonOffsetX")
            geometry.sendY = read("inputBarRightButtonOffsetY")
            if found {
                InterfaceSettings.inputBarGeometry.set(geometry.clamped)
            }

            InterfaceMigrations.moveBool(legacy, "showCharacterCounter", to: InterfaceSettings.characterCounter)
            InterfaceMigrations.moveBool(legacy, "inputToolbar", to: InterfaceSettings.formattingToolbar)
            InterfaceMigrations.moveBool(legacy, "autoTextFormattingEnabled", to: InterfaceSettings.autoFormatting)
            if let style = legacy.string("autoTextFormattingStyle"), WGAutoFormatting.styles.contains(style) {
                InterfaceSettings.autoFormattingStyle.set(style)
            }
            legacy.removeLegacyKey("autoTextFormattingStyle")
            InterfaceMigrations.moveBool(legacy, "forceEmojiTab", to: InterfaceSettings.emojiTabFirst)
            InterfaceMigrations.moveBool(legacy, "defaultEmojisFirst", to: InterfaceSettings.standardEmojiFirst)

            InterfaceMigrations.moveBool(legacy, "GG.typingAnimation.enabled", to: InterfaceSettings.typingAnimation)
            if let preset = legacy.string("GG.typingAnimation.preset"), WGTypingAnimationParameters.presets.contains(preset) {
                InterfaceSettings.typingAnimationPreset.set(preset)
            }
            legacy.removeLegacyKey("GG.typingAnimation.preset")
            InterfaceMigrations.moveSlider(legacy, "GG.typingAnimation.intensity", to: InterfaceSettings.typingAnimationIntensity)
            InterfaceMigrations.moveSlider(legacy, "GG.typingAnimation.speed", to: InterfaceSettings.typingAnimationSpeed)
            InterfaceMigrations.moveSlider(legacy, "GG.typingAnimation.scale", to: InterfaceSettings.typingAnimationScale)
            InterfaceMigrations.moveSlider(legacy, "GG.typingAnimation.offset", to: InterfaceSettings.typingAnimationOffset)
            InterfaceMigrations.moveSlider(legacy, "GG.typingAnimation.glow", to: InterfaceSettings.typingAnimationGlow)
        }

        WGMigrations.registerGlobal(id: "interface.bindButtons.v1") { legacy in
            InterfaceMigrations.moveBool(legacy, "FontCustomization.showBindButtons", to: InterfaceSettings.bindButtons)
            // Per-button switches: an explicit `false` hides the matching quick action.
            let map: [(String, String)] = [
                ("FontCustomization.showGhostModeBind", WGQuickActionIds.ghostMode),
                ("FontCustomization.showDeletedMessagesBind", WGQuickActionIds.deletedMessages),
                ("FontCustomization.showEditedMessagesBind", WGQuickActionIds.editedMessages),
                ("FontCustomization.showScheduledMessagesBind", WGQuickActionIds.sendDelay),
                ("FontCustomization.showScrollToTopBind", WGQuickActionIds.scrollToTop),
                ("FontCustomization.showTranslateBeforeSendBind", WGQuickActionIds.translateBeforeSend),
                ("FontCustomization.showScreenshotPrivacyBind", WGQuickActionIds.screenshotPrivacy)
            ]
            var hidden: [String] = []
            for (key, id) in map {
                if legacy.bool(key) == false {
                    hidden.append(id)
                }
                legacy.removeLegacyKey(key)
            }
            if !hidden.isEmpty {
                InterfaceSettings.bindButtonsHidden.set(hidden)
            }
        }

        // The old client's own positions (dragged inside a chat): centres normalized to the whole chat
        // screen, `{"<type>": {"x": …, "y": …}}`. Converted on a reference screen (402 × 874 pt with
        // Telegram 13's chat bars) into centres in the free area (WGQuickButtonsLayout), so on any
        // phone the buttons land proportionally where they stood.
        WGMigrations.registerGlobal(id: "interface.bindButtons.positions.v1") { legacy in
            let key = "ghostgram.bindButtons.positions.v1"
            guard let data = legacy.data(key) else {
                return
            }
            legacy.removeLegacyKey(key)
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return
            }
            let ids: [String: String] = [
                "ghostMode": WGQuickActionIds.ghostMode,
                "antiDelete": WGQuickActionIds.deletedMessages,
                "editHistory": WGQuickActionIds.editedMessages,
                "scheduledMessages": WGQuickActionIds.sendDelay,
                "translateBeforeSend": WGQuickActionIds.translateBeforeSend,
                "scrollToTop": WGQuickActionIds.scrollToTop,
                "screenshotPrivacy": WGQuickActionIds.screenshotPrivacy
            ]
            let screen = CGSize(width: 402.0, height: 874.0)
            let area = WGQuickButtonsLayout.area(bounds: screen, insets: UIEdgeInsets(top: 122.0, left: 0.0, bottom: 88.0, right: 0.0))
            let size = WGQuickButtonsLayout.size(width: WGQuickButtonsLayout.defaultSide, height: WGQuickButtonsLayout.defaultSide)
            var positions: [String: [Double]] = [:]
            for (oldId, value) in object {
                guard let id = ids[oldId], let point = value as? [String: Any], let x = (point["x"] as? NSNumber)?.doubleValue, let y = (point["y"] as? NSNumber)?.doubleValue, x.isFinite, y.isFinite else {
                    continue
                }
                let normalized = WGQuickButtonsLayout.normalized(center: CGPoint(x: x * Double(screen.width), y: y * Double(screen.height)), area: area, size: size)
                positions[id] = [(Double(normalized.x) * 10000.0).rounded() / 10000.0, (Double(normalized.y) * 10000.0).rounded() / 10000.0]
            }
            if !positions.isEmpty {
                InterfaceSettings.bindButtonsPositions.set(positions)
            }
        }

        WGMigrations.registerGlobal(id: "interface.customReactions.v1") { legacy in
            // Read before `moveBool` removes it: the fallback of «Стандартные после своих» needs it.
            let wasEnabled = legacy.bool("MiscSettings.customRecentReactionsEnabled")
            InterfaceMigrations.moveBool(legacy, "MiscSettings.customRecentReactionsEnabled", to: InterfaceSettings.customReactions)
            if let data = legacy.data("MiscSettings.customRecentReactionsList"), let items = try? JSONDecoder().decode([String].self, from: data) {
                InterfaceSettings.customReactionsList.set(WGCustomReactions.normalized(items))
                legacy.removeLegacyKey("MiscSettings.customRecentReactionsList")
            }
            // The old default was «on» when the key was absent (it mattered only with the own set on).
            let appendStandard = legacy.bool("MiscSettings.customRecentReactionsShowStandard") ?? (wasEnabled ?? false)
            InterfaceSettings.customReactionsAppendStandard.set(appendStandard)
            legacy.removeLegacyKey("MiscSettings.customRecentReactionsShowStandard")
        }

        WGMigrations.registerGlobal(id: "interface.iconPacks.v1") { legacy in
            // Custom packs are re-imported from their old folder by the storage on first launch;
            // here only the enabled order is kept (base packs Solar/Remix are not bundled).
            if let layout = legacy.stringArray("GG.iconPacks.layout") {
                let custom = layout.filter { !$0.hasPrefix("base.") }
                if !custom.isEmpty {
                    InterfaceSettings.iconPacks.set(custom)
                }
                legacy.removeLegacyKey("GG.iconPacks.layout")
            }
            legacy.removeLegacyKey("GG.iconPacks.hidden")
        }

        WGMigrations.registerGlobal(id: "interface.islandBadge.v1") { legacy in
            // The old client registered both keys as defaults: only the one the user changed is stored,
            // so each is carried over on its own (the old badge was on by default, like this one).
            // A bundled old badge is not kept (only Wraithgram's own ghost is, owner 2026-10-28).
            if let show = legacy.bool("showCustomAppBadge") {
                InterfaceSettings.islandBadge.set(show)
            }
            if let selection = legacy.string("customAppBadge"), selection.hasPrefix("custom.") {
                InterfaceSettings.islandBadgeSelection.set(selection)
            }
            legacy.removeLegacyKey("showCustomAppBadge")
            legacy.removeLegacyKey("customAppBadge")
        }

        WGMigrations.registerGlobal(id: "interface.settingsTab.v1") { legacy in
            // Read every old switch first: one old switch («Кошелёк») hid several rows.
            var hiddenLegacyNames = Set<String>()
            for legacyName in WGSettingsTabItem.allLegacyNames {
                if legacy.bool("FontCustomization.hiddenSettings." + legacyName) == true {
                    hiddenLegacyNames.insert(legacyName)
                }
            }
            var hidden: [String] = []
            for item in WGSettingsTabItem.allCases where !hiddenLegacyNames.isDisjoint(with: item.legacyNames) {
                hidden.append(item.rawValue)
            }
            for legacyName in WGSettingsTabItem.allLegacyNames {
                legacy.removeLegacyKey("FontCustomization.hiddenSettings." + legacyName)
            }
            if !hidden.isEmpty {
                InterfaceSettings.hiddenSettingsItems.set(hidden)
            }
            if let order = legacy.stringArray("FontCustomization.hiddenSettings.order") {
                let mapped = order.compactMap { WGSettingsTabItem(legacyName: $0)?.rawValue }
                InterfaceSettings.settingsItemsOrder.set(WGSettingsTabLayout.normalizedOrder(mapped))
            }
            legacy.removeLegacyKey("FontCustomization.hiddenSettings.order")
            legacy.removeLegacyKey("FontCustomization.hiddenSettings.orderVersion")
        }

        // The old «Скрыть «Сменить эмодзи-статус» / «Изменить цвет профиля» / «Выбрать фотографию»»
        // of the profile customization: one place now, the list «Скрыть в настройках» (W2-4 request).
        WGMigrations.registerGlobal(id: "interface.settingsTab.profileActions.v1") { legacy in
            let keys: [(String, WGSettingsTabItem)] = [
                ("GG.fontCustomization.hideEditEmojiStatusAction", .editEmojiStatus),
                ("GG.fontCustomization.hideEditProfileColorAction", .editProfileColor),
                ("GG.fontCustomization.hideEditProfilePhotoAction", .editPhoto)
            ]
            var hidden = InterfaceSettings.hiddenSettingsItems.value
            for (key, item) in keys {
                if legacy.bool(key) == true && !hidden.contains(item.rawValue) {
                    hidden.append(item.rawValue)
                }
                legacy.removeLegacyKey(key)
            }
            if hidden != InterfaceSettings.hiddenSettingsItems.value {
                InterfaceSettings.hiddenSettingsItems.set(hidden)
            }
        }

        // The old lists were global. They are read and their keys removed once, before any account
        // starts; the accounts of that launch get them (another account's peers do not resolve and are
        // dropped from the screen, not from the list). An account added later starts empty — the old
        // keys used to stay and every new account inherited the old shortcuts.
        WGMigrations.registerGlobal(id: "interface.settingsTab.shortcuts.capture.v1") { legacy in
            var shortcuts: [WGSettingsShortcut] = []
            if let peers = legacy.object("GG.fontCustomization.customSettingsShortcutPeerIds") as? [NSNumber] {
                for value in peers {
                    let key = WGLegacyKeys.peerKey(fromLegacyInt64: value.int64Value)
                    shortcuts.append(WGSettingsShortcut(id: "chat:" + key.stringValue, kind: .chat, peer: key, url: nil, title: nil))
                }
            }
            if let peers = legacy.object("GG.fontCustomization.customSettingsShortcutMiniAppPeerIds") as? [NSNumber] {
                for value in peers {
                    let key = WGLegacyKeys.peerKey(fromLegacyInt64: value.int64Value)
                    shortcuts.append(WGSettingsShortcut(id: "miniApp:" + key.stringValue, kind: .miniApp, peer: key, url: nil, title: nil))
                }
            }
            if let data = legacy.data("GG.fontCustomization.customSettingsShortcutURLs") ?? legacy.string("GG.fontCustomization.customSettingsShortcutURLs")?.data(using: .utf8) {
                if let sites = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    for site in sites {
                        guard let url = site["url"] as? String, let normalized = WGSiteShortcut.normalizedURL(url) else {
                            continue
                        }
                        let title = (site["title"] as? String) ?? ""
                        shortcuts.append(WGSettingsShortcut(id: "site:" + normalized, kind: .site, peer: nil, url: normalized, title: title.isEmpty ? nil : title))
                    }
                }
            }
            var seen = Set<String>()
            shortcuts = shortcuts.filter { seen.insert($0.id).inserted }
            InterfaceMigrations.setLegacyShortcuts(shortcuts)
            legacy.removeLegacyKey("GG.fontCustomization.customSettingsShortcutPeerIds")
            legacy.removeLegacyKey("GG.fontCustomization.customSettingsShortcutMiniAppPeerIds")
            legacy.removeLegacyKey("GG.fontCustomization.customSettingsShortcutURLs")
        }
        WGMigrations.registerAccount(id: "interface.settingsTab.shortcuts.v1") { _, account in
            let shortcuts = InterfaceMigrations.currentLegacyShortcuts()
            if !shortcuts.isEmpty {
                InterfaceSettings.settingsShortcuts.set(shortcuts, for: account)
            }
        }

        // «Вид Android» removed (owner, 2026-10-28): its stored value goes too.
        WGMigrations.registerGlobal(id: "interface.androidStyle.removed.v1") { _ in
            WGRetiredSettings.remove(keys: ["interface.chatList.androidStyle"])
        }
    }

    private static func moveBool(_ legacy: WGLegacyDefaults, _ key: String, to setting: WGSetting<Bool>) {
        if let value = legacy.bool(key) {
            setting.set(value)
            legacy.removeLegacyKey(key)
        }
    }

    private static func moveSlider(_ legacy: WGLegacyDefaults, _ key: String, to setting: WGSetting<Double>) {
        if let value = legacy.double(key) {
            setting.set(min(100.0, max(0.0, value)))
            legacy.removeLegacyKey(key)
        }
    }

    /// The option ("80", "90", …) closest to a numeric value.
    static func nearestOption(_ value: Double, options: [String]) -> String {
        var best = options.first ?? ""
        var bestDistance = Double.greatestFiniteMagnitude
        for option in options {
            guard let number = Double(option) else {
                continue
            }
            let distance = abs(number - value)
            if distance < bestDistance {
                bestDistance = distance
                best = option
            }
        }
        return best
    }
}
