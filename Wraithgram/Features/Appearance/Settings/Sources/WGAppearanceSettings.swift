import Foundation
import WGCore

/// Every appearance setting of Wraithgram, declared once (FOUNDATION_SPEC §3.1). Kept in its own small
/// module (WGCore only) so the upstream modules that draw them — down to the bubble background, which
/// sits below TelegramCore — read the same registry the menu writes.
///
/// Cells and layout never read these one by one on their hot paths: they read the immutable
/// `WGAppearanceSnapshot.current`, rebuilt once per change.
public enum WGAppearanceSettings {
    // MARK: Font (applied at launch: upstream keeps fonts in file-scope constants)

    /// `WGFontFamily.rawValue`; "system" = Telegram's font. Or "custom:<file>" — a font the user
    /// added (owner 2026-10-27, `customFonts`). Any other value reads as "system".
    public static let fontFamily = WGSetting<String>("appearance.font.family", default: "system", flags: [.requiresRestart])
    /// Fonts the user added from Files, in the order added: "<file name>\t<family name>". The files
    /// live in the app's container (Application Support/wraithgram/appearance/userFonts).
    /// Not exported: the files stay on this device.
    public static let customFonts = WGSetting<[String]>("appearance.font.custom", default: [], flags: [.noExport])

    // MARK: Bubbles

    public static let bubbleEditor = WGSetting<Bool>("appearance.bubbles.editor", default: false)
    public static let bubbleIncomingRadius = WGSetting<Double>("appearance.bubbles.incomingRadius", default: 16.0)
    public static let bubbleOutgoingRadius = WGSetting<Double>("appearance.bubbles.outgoingRadius", default: 16.0)
    /// Horizontal text inset inside a bubble, pt.
    public static let bubblePadding = WGSetting<Double>("appearance.bubbles.padding", default: 11.0)
    /// Share of the upstream maximum bubble width, %.
    public static let bubbleWidth = WGSetting<Double>("appearance.bubbles.width", default: 100.0)
    public static let bubbleBackgroundOpacity = WGSetting<Double>("appearance.bubbles.backgroundOpacity", default: 100.0)
    public static let bubbleOutlineOpacity = WGSetting<Double>("appearance.bubbles.outlineOpacity", default: 0.0)
    public static let bubbleHideTails = WGSetting<Bool>("appearance.bubbles.hideTails", default: false)

    // MARK: Checkmarks ("" = the theme's color)

    public static let readCheckColor = WGSetting<String>("appearance.checkmarks.readColor", default: "")
    public static let unreadCheckColor = WGSetting<String>("appearance.checkmarks.unreadColor", default: "")
    public static let unreadCheckSameAsRead = WGSetting<Bool>("appearance.checkmarks.unreadSameAsRead", default: false)
    public static let checkColorsInChatList = WGSetting<Bool>("appearance.checkmarks.inChatList", default: false)

    // MARK: Stickers

    /// %, 50…200 (bigger than 100 since 2026-10-27; a big sticker still fits the chat's width).
    public static let stickerSize = WGSetting<Double>("appearance.stickers.size", default: 100.0)
    public static let stickerHideTime = WGSetting<Bool>("appearance.stickers.hideTime", default: false)

    // MARK: Messages

    public static let wideChannelPosts = WGSetting<Bool>("appearance.messages.wideChannelPosts", default: false)
    public static let secondsInTime = WGSetting<Bool>("appearance.messages.secondsInTime", default: false)
    /// `WGHiddenReactions.rawValue` (one choice since 2026-10-27; replaced «…in chats» / «…in channels»).
    public static let hideReactions = WGSetting<String>("appearance.messages.hideReactions", default: WGHiddenReactions.off.rawValue)
    public static let hideEdited = WGSetting<Bool>("appearance.messages.hideEdited", default: false)
    public static let hideTime = WGSetting<Bool>("appearance.messages.hideTime", default: false)
    /// `WGHiddenFormatting.rawValue` (one choice since 2026-10-27; replaced «…incoming» / «…own»).
    public static let hideFormatting = WGSetting<String>("appearance.messages.hideFormatting", default: WGHiddenFormatting.off.rawValue)
    public static let hideChannelComments = WGSetting<Bool>("appearance.messages.hideChannelComments", default: false)
    public static let hideViewCounts = WGSetting<Bool>("appearance.messages.hideViewCounts", default: false)
    public static let colorSwatches = WGSetting<Bool>("appearance.messages.colorSwatches", default: false)
    public static let authorOnlineIndicator = WGSetting<Bool>("appearance.messages.authorOnline", default: false)
    public static let exactLastSeen = WGSetting<Bool>("appearance.messages.exactLastSeen", default: false)
    /// `WGTripleTapDelete.rawValue`.
    public static let tripleTapDelete = WGSetting<String>("appearance.messages.tripleTapDelete", default: "off")
    public static let noSelectionBlur = WGSetting<Bool>("appearance.messages.noSelectionBlur", default: false)

    // MARK: Chat top bar

    public static let hideBackButton = WGSetting<Bool>("appearance.chatTopBar.hideBackButton", default: false)
    public static let hideTitlePanel = WGSetting<Bool>("appearance.chatTopBar.hideTitle", default: false)
    public static let hideAvatar = WGSetting<Bool>("appearance.chatTopBar.hideAvatar", default: false)
    public static let hidePinnedMessages = WGSetting<Bool>("appearance.chatTopBar.hidePinned", default: false)

    // MARK: Theme

    public static let amoled = WGSetting<Bool>("appearance.theme.amoled", default: false)
    public static let amoledKeyboard = WGSetting<Bool>("appearance.theme.amoledKeyboard", default: false)
    public static let hideSeparators = WGSetting<Bool>("appearance.theme.hideSeparators", default: false)
    /// %, 0…100; 100 = the server's colors.
    public static let nameColorSaturation = WGSetting<Double>("appearance.theme.nameSaturation", default: 100.0)

    // MARK: Screen edges («Затемнение краёв»: one group since 2026-10-27 instead of blur + gradient)

    /// `WGEdgeStyle.rawValue`.
    public static let edgeStyle = WGSetting<String>("appearance.edges.style", default: WGEdgeStyle.off.rawValue)
    /// "" = automatic (the theme's background).
    public static let edgeColor = WGSetting<String>("appearance.edges.color", default: "")
    /// pt, `WGEdgeStyle.sizeRange`.
    public static let edgeSize = WGSetting<Double>("appearance.edges.size", default: WGEdgeStyle.defaultSize)
    /// %, 0…100.
    public static let edgeIntensity = WGSetting<Double>("appearance.edges.intensity", default: WGEdgeStyle.defaultIntensity)
    /// The gradient only (the blur is never drawn in the chat list).
    public static let edgeHideInChatList = WGSetting<Bool>("appearance.edges.hideInChatList", default: false)

    // MARK: Animated backgrounds (files live in the app container; settings keep only a version)

    public static let chatBackground = WGSetting<Bool>("appearance.chatBackground.enabled", default: false)
    public static let chatBackgroundOpacity = WGSetting<Double>("appearance.chatBackground.opacity", default: 30.0)
    /// Version of the converted file; 0 = none. Bumps on every new pick so players reload.
    public static let chatBackgroundVersion = WGSetting<Int>("appearance.chatBackground.version", default: 0, flags: [.noExport])
    public static let profileBackground = WGSetting<Bool>("appearance.profileBackground.enabled", default: false)
    public static let profileBackgroundOpacity = WGSetting<Double>("appearance.profileBackground.opacity", default: 50.0)
    public static let profileBackgroundVersion = WGSetting<Int>("appearance.profileBackground.version", default: 0, flags: [.noExport])

    // MARK: Snowfall (also the former «New Year» wallpaper effect)

    public static let snow = WGSetting<Bool>("appearance.snow.enabled", default: false)
    /// `WGSnowStyle.rawValue`.
    public static let snowStyle = WGSetting<String>("appearance.snow.style", default: "snow")
    /// %, 10…100.
    public static let snowIntensity = WGSetting<Double>("appearance.snow.intensity", default: 100.0)
    public static let snowHideInChats = WGSetting<Bool>("appearance.snow.hideInChats", default: false)

    // MARK: Profile

    /// On by default, as Swiftgram's `showProfileId` (W6-SGD, owner's decision 2026-10-29).
    public static let profileShowId = WGSetting<Bool>("appearance.profile.showId", default: true)
    public static let profileShowDataCenter = WGSetting<Bool>("appearance.profile.showDataCenter", default: false)
    /// On by default: Swiftgram's `showCreationDate` is on, and its «mutual contact» and «joined» rows
    /// have no switch at all (W6-SGD).
    public static let profileShowDates = WGSetting<Bool>("appearance.profile.showDates", default: true)
    public static let profileHideDescription = WGSetting<Bool>("appearance.profile.hideDescription", default: false)
    public static let profileHideShareButton = WGSetting<Bool>("appearance.profile.hideShareButton", default: false)
    public static let profileHideStarRating = WGSetting<Bool>("appearance.profile.hideStarRating", default: false)

    /// Touches every declaration so the registry knows them before export, search and migrations.
    public static func declare() {
        let _ = WGAppearanceSettings.fontFamily
        let _ = WGAppearanceSettings.customFonts
        let _ = WGAppearanceSettings.bubbleEditor
        let _ = WGAppearanceSettings.bubbleIncomingRadius
        let _ = WGAppearanceSettings.bubbleOutgoingRadius
        let _ = WGAppearanceSettings.bubblePadding
        let _ = WGAppearanceSettings.bubbleWidth
        let _ = WGAppearanceSettings.bubbleBackgroundOpacity
        let _ = WGAppearanceSettings.bubbleOutlineOpacity
        let _ = WGAppearanceSettings.bubbleHideTails
        let _ = WGAppearanceSettings.readCheckColor
        let _ = WGAppearanceSettings.unreadCheckColor
        let _ = WGAppearanceSettings.unreadCheckSameAsRead
        let _ = WGAppearanceSettings.checkColorsInChatList
        let _ = WGAppearanceSettings.stickerSize
        let _ = WGAppearanceSettings.stickerHideTime
        let _ = WGAppearanceSettings.wideChannelPosts
        let _ = WGAppearanceSettings.secondsInTime
        let _ = WGAppearanceSettings.hideReactions
        let _ = WGAppearanceSettings.hideEdited
        let _ = WGAppearanceSettings.hideTime
        let _ = WGAppearanceSettings.hideFormatting
        let _ = WGAppearanceSettings.hideChannelComments
        let _ = WGAppearanceSettings.hideViewCounts
        let _ = WGAppearanceSettings.colorSwatches
        let _ = WGAppearanceSettings.authorOnlineIndicator
        let _ = WGAppearanceSettings.exactLastSeen
        let _ = WGAppearanceSettings.tripleTapDelete
        let _ = WGAppearanceSettings.noSelectionBlur
        let _ = WGAppearanceSettings.hideBackButton
        let _ = WGAppearanceSettings.hideTitlePanel
        let _ = WGAppearanceSettings.hideAvatar
        let _ = WGAppearanceSettings.hidePinnedMessages
        let _ = WGAppearanceSettings.amoled
        let _ = WGAppearanceSettings.amoledKeyboard
        let _ = WGAppearanceSettings.hideSeparators
        let _ = WGAppearanceSettings.nameColorSaturation
        let _ = WGAppearanceSettings.edgeStyle
        let _ = WGAppearanceSettings.edgeColor
        let _ = WGAppearanceSettings.edgeSize
        let _ = WGAppearanceSettings.edgeIntensity
        let _ = WGAppearanceSettings.edgeHideInChatList
        let _ = WGAppearanceSettings.chatBackground
        let _ = WGAppearanceSettings.chatBackgroundOpacity
        let _ = WGAppearanceSettings.chatBackgroundVersion
        let _ = WGAppearanceSettings.profileBackground
        let _ = WGAppearanceSettings.profileBackgroundOpacity
        let _ = WGAppearanceSettings.profileBackgroundVersion
        let _ = WGAppearanceSettings.snow
        let _ = WGAppearanceSettings.snowStyle
        let _ = WGAppearanceSettings.snowIntensity
        let _ = WGAppearanceSettings.snowHideInChats
        let _ = WGAppearanceSettings.profileShowId
        let _ = WGAppearanceSettings.profileShowDataCenter
        let _ = WGAppearanceSettings.profileShowDates
        let _ = WGAppearanceSettings.profileHideDescription
        let _ = WGAppearanceSettings.profileHideShareButton
        let _ = WGAppearanceSettings.profileHideStarRating
    }
}

/// The fonts offered in the menu: the system font, its designs and families preinstalled in iOS 15+
/// (owner decision 2026-10-22: nothing bundled). Fonts the user adds are not cases here: they are
/// "custom:<file>" values of `appearance.font.family` (owner 2026-10-27). The raw values are stored in
/// `appearance.font.family`; the old Wraithgram's values (bundled free fonts, «imported») are not
/// among them and read as `.system`.
public enum WGFontFamily: String, CaseIterable {
    /// Telegram's font (SF Pro): no substitution at all.
    case system
    // Designs of the system font.
    case rounded
    case serif
    case monospaced
    // Families preinstalled in iOS; the menu lists them in this order (with Cyrillic first).
    case helveticaNeue
    case arial
    case avenirNext
    case gillSans
    case trebuchet
    case verdana
    case georgia
    case timesNewRoman
    case palatino
    case baskerville
    case charter
    case cochin
    case hoeflerText
    case iowanOldStyle
    case rockwell
    case americanTypewriter
    case markerFelt
    case noteworthy
    case chalkboard
    case menlo
    case courierNew
    case futura
    case optima
    case didot
    case bodoni

    /// The stored value as a family; anything unknown (a removed font) is the system font.
    public static func resolved(_ rawValue: String) -> WGFontFamily {
        return WGFontFamily(rawValue: rawValue) ?? .system
    }
}

public enum WGTripleTapDelete: String {
    case off
    case local
    case everyone
}

public enum WGSnowStyle: String {
    case snow
    case lightning
}

/// "RRGGBB" / "#RRGGBB" → 0xRRGGBB; nil for "" and anything malformed.
public func wgAppearanceParseColor(_ value: String) -> UInt32? {
    var text = value.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("#") {
        text.removeFirst()
    }
    if text.count != 6 {
        return nil
    }
    return UInt32(text, radix: 16)
}

/// 0xRRGGBB → "RRGGBB".
public func wgAppearanceColorString(_ rgb: UInt32) -> String {
    return String(format: "%06X", Int(rgb & 0xffffff))
}
