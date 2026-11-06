import Foundation
import WGCore
import WGAppearanceSettings

/// One-time move of the old Wraithgram's appearance settings (three stores: `FontCustomization.*` /
/// `WG.fontCustomization.*`, `WG.checkmark.*`, and the Wraithgram keys parked in SGSimpleSettings)
/// into the registry. Only values the user actually stored are moved: an absent key
/// leaves the new default (toggles off). Old «show …» toggles that were ON by default became
/// «hide …» toggles that are OFF by default.
///
/// Dead keys are not moved: `readStatusColor*` (no consumer), the `chatListGradient*` switches
/// (the gradient never painted; its color, size and strength only fill the one edge group when the
/// blur's are absent). The glass settings (`WG.liquidGlass*`) are not moved at all: the feature was
/// removed (owner 2026-10-27), its keys only go (`appearance.glass.removed.v1`).
enum WGAppearanceMigration {
    static func register() {
        WGMigrations.registerGlobal(id: "appearance.v1") { legacy in
            WGAppearanceMigration.moveBubbles(legacy)
            WGAppearanceMigration.moveCheckmarks(legacy)
            WGAppearanceMigration.moveMessages(legacy)
            WGAppearanceMigration.moveTheme(legacy)
            WGAppearanceMigration.moveEdges(legacy)
            WGAppearanceMigration.moveBackgrounds(legacy)
            WGAppearanceMigration.moveProfile(legacy)
        }
        WGMigrations.registerGlobal(id: "appearance.font.v2") { legacy in
            WGAppearanceMigration.dropRemovedFonts(legacy)
        }
        WGMigrations.registerGlobal(id: "appearance.merge.v1") { _ in
            WGAppearanceMigration.mergeRetiredSettings()
        }
        // «Стекло» (Liquid Glass) was removed by the owner on 2026-10-27, its upstream edits went back
        // to upstream. Whatever it stored goes once: the old client's keys and this app's
        // `appearance.glass.*` (build 185 and earlier).
        WGMigrations.registerGlobal(id: "appearance.glass.removed.v1") { legacy in
            for key in WGAppearanceMigration.removedGlassLegacyKeys {
                legacy.removeLegacyKey(key)
            }
            WGRetiredSettings.remove(prefixes: ["appearance.glass."])
        }
    }

    /// The old client's glass keys: its raw `UserDefaults` switches and the Swiftgram key of the system
    /// glass (`SGSimpleSettings.systemLiquidGlassEnabled` used the same name).
    static let removedGlassLegacyKeys: [String] = [
        "GG.liquidGlass", "GG.liquidGlassIntensity", "GG.liquidGlass.tintColor", "GG.liquidGlass.cornerRadius",
        "GG.liquidGlass.disableBlur", "GG.liquidGlass.disableShadow", "GG.liquidGlass.disableHighlight",
        "GG.liquidGlass.tabBar", "GG.liquidGlass.navBar", "GG.liquidGlass.search", "GG.liquidGlass.chatInput",
        "GG.liquidGlass.chatButtons", "GG.systemLiquidGlass.enabled"
    ]

    /// Builds ≤ 185 had two switches for hidden reactions, two for hidden formatting and nine rows
    /// of screen edges; since 2026-10-27 each is one setting (`WGAppearanceChoices.swift`). Their
    /// stored values are carried over once, then dropped from the settings file.
    static let retiredKeys: [String] = [
        "appearance.messages.hideReactionsInChats", "appearance.messages.hideReactionsInChannels",
        "appearance.messages.hideIncomingFormatting", "appearance.messages.hideOutgoingFormatting",
        "appearance.edges.blur", "appearance.edges.blurColor", "appearance.edges.blurSize", "appearance.edges.blurIntensity",
        "appearance.edges.gradient", "appearance.edges.gradientColor", "appearance.edges.gradientSize",
        "appearance.edges.gradientIntensity", "appearance.edges.gradientHideInChatList"
    ]

    private static func mergeRetiredSettings() {
        if let value = WGHiddenReactions.merged(inChats: WGRetiredSettings.value("appearance.messages.hideReactionsInChats", as: Bool.self), inChannels: WGRetiredSettings.value("appearance.messages.hideReactionsInChannels", as: Bool.self)) {
            WGAppearanceSettings.hideReactions.set(value.rawValue)
        }
        if let value = WGHiddenFormatting.merged(inIncoming: WGRetiredSettings.value("appearance.messages.hideIncomingFormatting", as: Bool.self), inOutgoing: WGRetiredSettings.value("appearance.messages.hideOutgoingFormatting", as: Bool.self)) {
            WGAppearanceSettings.hideFormatting.set(value.rawValue)
        }
        var old = WGEdgeMerge.Old()
        old.blur = WGRetiredSettings.value("appearance.edges.blur", as: Bool.self)
        old.blurColor = WGRetiredSettings.value("appearance.edges.blurColor", as: String.self)
        old.blurSize = WGRetiredSettings.value("appearance.edges.blurSize", as: Double.self)
        old.blurIntensity = WGRetiredSettings.value("appearance.edges.blurIntensity", as: Double.self)
        old.gradient = WGRetiredSettings.value("appearance.edges.gradient", as: Bool.self)
        old.gradientColor = WGRetiredSettings.value("appearance.edges.gradientColor", as: String.self)
        old.gradientSize = WGRetiredSettings.value("appearance.edges.gradientSize", as: Double.self)
        old.gradientIntensity = WGRetiredSettings.value("appearance.edges.gradientIntensity", as: Double.self)
        old.gradientHideInChatList = WGRetiredSettings.value("appearance.edges.gradientHideInChatList", as: Bool.self)
        if let merge = WGEdgeMerge.merged(old) {
            WGAppearanceMigration.apply(merge)
        }
        WGRetiredSettings.remove(keys: WGAppearanceMigration.retiredKeys)
    }

    private static func apply(_ merge: WGEdgeMerge) {
        if merge.style != .off {
            WGAppearanceSettings.edgeStyle.set(merge.style.rawValue)
        }
        if let color = merge.color, let rgb = wgAppearanceParseColor(color) {
            WGAppearanceSettings.edgeColor.set(wgAppearanceColorString(rgb))
        }
        if let size = merge.size {
            WGAppearanceSettings.edgeSize.set(size)
        }
        if let intensity = merge.intensity {
            WGAppearanceSettings.edgeIntensity.set(intensity)
        }
        if let hideInChatList = merge.hideInChatList {
            WGAppearanceSettings.edgeHideInChatList.set(hideInChatList)
        }
    }

    // MARK: Helpers

    private static func bool(_ legacy: WGLegacyDefaults, _ key: String, to setting: WGSetting<Bool>, inverted: Bool = false) {
        if let value = legacy.bool(key) {
            setting.set(inverted ? !value : value)
            legacy.removeLegacyKey(key)
        }
    }

    private static func double(_ legacy: WGLegacyDefaults, _ key: String, to setting: WGSetting<Double>, range: ClosedRange<Double>) {
        if let value = legacy.double(key) {
            setting.set(min(range.upperBound, max(range.lowerBound, value)))
            legacy.removeLegacyKey(key)
        }
    }

    /// The old checkmark colors were stored as `[r, g, b, a]` doubles.
    private static func rgbaColor(_ legacy: WGLegacyDefaults, _ key: String) -> String? {
        guard let components = legacy.object(key) as? [NSNumber], components.count >= 3 else {
            return nil
        }
        let r = UInt32(max(0.0, min(1.0, components[0].doubleValue)) * 255.0)
        let g = UInt32(max(0.0, min(1.0, components[1].doubleValue)) * 255.0)
        let b = UInt32(max(0.0, min(1.0, components[2].doubleValue)) * 255.0)
        return wgAppearanceColorString((r << 16) | (g << 8) | b)
    }

    /// The old code stored absolute paths, which break when iOS moves the app container: the same
    /// file name is looked up in Documents as well.
    static func legacyFile(_ path: String) -> URL? {
        if path.isEmpty {
            return nil
        }
        if FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty, let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let candidate = documents.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Deletes a leftover directory off the main thread (migrations run on it at launch).
    static func removeInBackground(_ url: URL) {
        DispatchQueue.global(qos: .utility).async {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: Groups

    /// Fonts are only the ones that ship with iOS (owner decision 2026-10-22), so no font value is
    /// carried over; whatever pointed at a removed font goes:
    /// - the old Wraithgram's keys (it offered only its bundled free fonts and an imported file; the
    ///   last one is its «show fonts» list state) and `Documents/Fonts`, where its import copied every
    ///   picked file and never deleted one;
    /// - a family stored by an earlier build of this app (a removed bundled font, «imported») → the
    ///   system font (the default), and that build's directory of imported fonts.
    private static func dropRemovedFonts(_ legacy: WGLegacyDefaults) {
        for key in ["FontCustomization.isEnabled", "FontCustomization.selectedFont", "FontCustomization.isCustomSelected", "FontCustomization.importedFontPath", "FontCustomization.importedFontName", "FontCustomizationController.fontsExpanded"] {
            legacy.removeLegacyKey(key)
        }
        if WGFontFamily(rawValue: WGAppearanceSettings.fontFamily.value) == nil && !WGCustomFonts.isCustomValue(WGAppearanceSettings.fontFamily.value) {
            WGAppearanceSettings.fontFamily.reset()
        }
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            WGAppearanceMigration.removeInBackground(documents.appendingPathComponent("Fonts", isDirectory: true))
        }
        if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            WGAppearanceMigration.removeInBackground(applicationSupport.appendingPathComponent("ghostgram/appearance/fonts", isDirectory: true))
        }
    }

    private static func moveBubbles(_ legacy: WGLegacyDefaults) {
        WGAppearanceMigration.bool(legacy, "bubbleEditorEnabled", to: WGAppearanceSettings.bubbleEditor)
        WGAppearanceMigration.double(legacy, "bubbleIncomingRadius", to: WGAppearanceSettings.bubbleIncomingRadius, range: 0.0 ... 16.0)
        WGAppearanceMigration.double(legacy, "bubbleOutgoingRadius", to: WGAppearanceSettings.bubbleOutgoingRadius, range: 0.0 ... 16.0)
        WGAppearanceMigration.double(legacy, "bubblePadding", to: WGAppearanceSettings.bubblePadding, range: 0.0 ... 24.0)
        WGAppearanceMigration.double(legacy, "bubbleWidthPercent", to: WGAppearanceSettings.bubbleWidth, range: 40.0 ... 100.0)
        WGAppearanceMigration.double(legacy, "bubbleBackgroundOpacity", to: WGAppearanceSettings.bubbleBackgroundOpacity, range: 0.0 ... 100.0)
        WGAppearanceMigration.double(legacy, "bubbleOutlineOpacity", to: WGAppearanceSettings.bubbleOutlineOpacity, range: 0.0 ... 100.0)
        WGAppearanceMigration.bool(legacy, "bubbleHasTails", to: WGAppearanceSettings.bubbleHideTails, inverted: true)
    }

    private static func moveCheckmarks(_ legacy: WGLegacyDefaults) {
        if legacy.bool("GG.checkmark.useCustomReadColor") == true, let color = WGAppearanceMigration.rgbaColor(legacy, "GG.checkmark.readColor") {
            WGAppearanceSettings.readCheckColor.set(color)
        }
        if legacy.bool("GG.checkmark.useCustomUnreadColor") == true, let color = WGAppearanceMigration.rgbaColor(legacy, "GG.checkmark.unreadColor") {
            WGAppearanceSettings.unreadCheckColor.set(color)
        }
        WGAppearanceMigration.bool(legacy, "GG.checkmark.useReadColorForUnread", to: WGAppearanceSettings.unreadCheckSameAsRead)
        WGAppearanceMigration.bool(legacy, "GG.checkmark.applyInChatList", to: WGAppearanceSettings.checkColorsInChatList)
        for key in ["GG.checkmark.useCustomReadColor", "GG.checkmark.readColor", "GG.checkmark.useCustomUnreadColor", "GG.checkmark.unreadColor"] {
            legacy.removeLegacyKey(key)
        }
    }

    private static func moveMessages(_ legacy: WGLegacyDefaults) {
        WGAppearanceMigration.bool(legacy, "FontCustomization.showExactLastSeen", to: WGAppearanceSettings.exactLastSeen)
        // Hidden formatting and hidden reactions are one choice each since 2026-10-27.
        if let value = WGHiddenFormatting.merged(inIncoming: legacy.bool("FontCustomization.hideIncomingTextFormatting"), inOutgoing: legacy.bool("FontCustomization.hideOutgoingTextFormatting")) {
            WGAppearanceSettings.hideFormatting.set(value.rawValue)
        }
        legacy.removeLegacyKey("FontCustomization.hideIncomingTextFormatting")
        legacy.removeLegacyKey("FontCustomization.hideOutgoingTextFormatting")
        WGAppearanceMigration.bool(legacy, "FontCustomization.hideChannelComments", to: WGAppearanceSettings.hideChannelComments)
        WGAppearanceMigration.bool(legacy, "FontCustomization.hideChannelViewCounts", to: WGAppearanceSettings.hideViewCounts)
        WGAppearanceMigration.bool(legacy, "FontCustomization.hideMessageTimestamps", to: WGAppearanceSettings.hideTime)
        WGAppearanceMigration.bool(legacy, "FontCustomization.hideEditedStatus", to: WGAppearanceSettings.hideEdited)
        WGAppearanceMigration.bool(legacy, "FontCustomization.chatAvatarOnlineIndicator", to: WGAppearanceSettings.authorOnlineIndicator)
        if let mode = legacy.string("GG.fontCustomization.tripleTapDeleteMode") {
            switch mode {
            case "local":
                WGAppearanceSettings.tripleTapDelete.set(WGTripleTapDelete.local.rawValue)
            case "everyone":
                WGAppearanceSettings.tripleTapDelete.set(WGTripleTapDelete.everyone.rawValue)
            default:
                break
            }
            legacy.removeLegacyKey("GG.fontCustomization.tripleTapDeleteMode")
        }
        WGAppearanceMigration.bool(legacy, "FontCustomization.showChatTopBarBackButton", to: WGAppearanceSettings.hideBackButton, inverted: true)
        WGAppearanceMigration.bool(legacy, "FontCustomization.showChatTopBarTitlePanel", to: WGAppearanceSettings.hideTitlePanel, inverted: true)
        WGAppearanceMigration.bool(legacy, "FontCustomization.showChatTopBarAvatar", to: WGAppearanceSettings.hideAvatar, inverted: true)
        WGAppearanceMigration.bool(legacy, "FontCustomization.showChatTopBarPinnedMessages", to: WGAppearanceSettings.hidePinnedMessages, inverted: true)
        WGAppearanceMigration.bool(legacy, "disableBlurOnMessageSelection", to: WGAppearanceSettings.noSelectionBlur)
        WGAppearanceMigration.bool(legacy, "wideChannelPosts", to: WGAppearanceSettings.wideChannelPosts)
        WGAppearanceMigration.bool(legacy, "secondsInMessages", to: WGAppearanceSettings.secondsInTime)
        // The old Swiftgram key meant both places; it is older, so the specific keys win.
        let hideEverywhere: Bool? = legacy.bool("hideReactions") == true ? true : nil
        if let value = WGHiddenReactions.merged(inChats: legacy.bool("hideReactionsInChats") ?? hideEverywhere, inChannels: legacy.bool("hideReactionsInChannels") ?? hideEverywhere) {
            WGAppearanceSettings.hideReactions.set(value.rawValue)
        }
        for key in ["hideReactions", "hideReactionsInChats", "hideReactionsInChannels"] {
            legacy.removeLegacyKey(key)
        }
        WGAppearanceMigration.double(legacy, "stickerSize", to: WGAppearanceSettings.stickerSize, range: 50.0 ... 100.0)
        WGAppearanceMigration.bool(legacy, "stickerTimestamp", to: WGAppearanceSettings.stickerHideTime, inverted: true)
    }

    private static func moveTheme(_ legacy: WGLegacyDefaults) {
        WGAppearanceMigration.bool(legacy, "GG.fontCustomization.amoledTrueBlack", to: WGAppearanceSettings.amoled)
        WGAppearanceMigration.bool(legacy, "GG.fontCustomization.amoledKeyboard", to: WGAppearanceSettings.amoledKeyboard)
        WGAppearanceMigration.bool(legacy, "GG.fontCustomization.hideCellSeparators", to: WGAppearanceSettings.hideSeparators)
        WGAppearanceMigration.double(legacy, "accountColorsSaturation", to: WGAppearanceSettings.nameColorSaturation, range: 0.0 ... 100.0)
        WGAppearanceMigration.bool(legacy, "GG.fontCustomization.snowflakes", to: WGAppearanceSettings.snow)
        WGAppearanceMigration.double(legacy, "GG.fontCustomization.snowflakesIntensity", to: WGAppearanceSettings.snowIntensity, range: 10.0 ... 100.0)
        WGAppearanceMigration.bool(legacy, "GG.fontCustomization.snowflakesInChat", to: WGAppearanceSettings.snowHideInChats, inverted: true)
        // Swiftgram's New Year effect needed its server to switch on; its style is kept.
        if let style = legacy.string("nyStyle") {
            if style == "lightning" {
                WGAppearanceSettings.snowStyle.set(WGSnowStyle.lightning.rawValue)
            }
            legacy.removeLegacyKey("nyStyle")
        }
    }

    /// The old switches are not carried over (the blur was on by default, the gradient never
    /// painted): only the values, into the one group «Затемнение краёв» — the blur's first.
    private static func moveEdges(_ legacy: WGLegacyDefaults) {
        var old = WGEdgeMerge.Old()
        old.blurColor = WGAppearanceMigration.legacyColor(legacy, "chatBlurColor", autoKey: "chatBlurAutoColor")
        old.blurSize = legacy.double("chatBlurSize")
        old.blurIntensity = legacy.double("chatBlurIntensity")
        old.gradientColor = WGAppearanceMigration.legacyColor(legacy, "chatListGradientColor", autoKey: "chatListGradientAutoColor")
        old.gradientSize = legacy.double("chatListGradientSize")
        old.gradientIntensity = legacy.double("chatListGradientIntensity")
        old.gradientHideInChatList = legacy.bool("chatListGradientInChatList").map { !$0 }
        if let merge = WGEdgeMerge.merged(old) {
            WGAppearanceMigration.apply(merge)
        }
        for key in ["displayBlurInChats", "chatBlurAutoColor", "chatBlurColor", "chatBlurSize", "chatBlurIntensity", "chatListGradientEnabled", "chatListGradientAutoColor", "chatListGradientColor", "chatListGradientSize", "chatListGradientIntensity", "chatListGradientInChatList"] {
            legacy.removeLegacyKey(key)
        }
    }

    /// An old color is used only when its «automatic» switch was off.
    private static func legacyColor(_ legacy: WGLegacyDefaults, _ key: String, autoKey: String) -> String? {
        guard legacy.bool(autoKey) == false, let value = legacy.string(key), let rgb = wgAppearanceParseColor(value) else {
            return nil
        }
        return wgAppearanceColorString(rgb)
    }

    private static func moveBackgrounds(_ legacy: WGLegacyDefaults) {
        WGAppearanceMigration.double(legacy, "gifWallpaperOpacity", to: WGAppearanceSettings.chatBackgroundOpacity, range: 5.0 ... 100.0)
        WGAppearanceMigration.double(legacy, "profileGifOpacity", to: WGAppearanceSettings.profileBackgroundOpacity, range: 5.0 ... 100.0)
        // Old files are converted in the background; the background switches on when ready.
        if legacy.bool("gifWallpaperEnabled") == true, let path = legacy.string("gifWallpaperPath"), let url = WGAppearanceMigration.legacyFile(path) {
            WGAnimatedBackgrounds.importFile(at: url, kind: .chat, completion: { _ in })
        }
        if legacy.bool("profileGifEnabled") == true, let path = legacy.string("profileGifPath"), let url = WGAppearanceMigration.legacyFile(path) {
            WGAnimatedBackgrounds.importFile(at: url, kind: .profile, completion: { _ in })
        }
        for key in ["gifWallpaperEnabled", "gifWallpaperPath", "profileGifEnabled", "profileGifPath"] {
            legacy.removeLegacyKey(key)
        }
    }

    private static func moveProfile(_ legacy: WGLegacyDefaults) {
        WGAppearanceMigration.bool(legacy, "showProfileId", to: WGAppearanceSettings.profileShowId)
        WGAppearanceMigration.bool(legacy, "showDC", to: WGAppearanceSettings.profileShowDataCenter)
        WGAppearanceMigration.bool(legacy, "showCreationDate", to: WGAppearanceSettings.profileShowDates)
        WGAppearanceMigration.bool(legacy, "GG.fontCustomization.hideProfileDescription", to: WGAppearanceSettings.profileHideDescription)
        WGAppearanceMigration.bool(legacy, "GG.fontCustomization.showPeerInfoShareButton", to: WGAppearanceSettings.profileHideShareButton, inverted: true)
        WGAppearanceMigration.bool(legacy, "GG.fontCustomization.hideStarRatingBadge", to: WGAppearanceSettings.profileHideStarRating)
    }
}
