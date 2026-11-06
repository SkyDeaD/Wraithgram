import Foundation
import WGCore

/// Every setting of anti-delete, edit history, local edits and bookmarks, declared once.
/// What the notification service reads (capture) is `.appGroup` + `.extensions`, or an account
/// setting with `.extensions`; the rest is app-only.
public enum WGAntiDeleteSettings {
    // MARK: Capture (read by the notification service too)

    /// Keep messages other people (or the server) deleted.
    public static let enabled = WGSetting<Bool>("antiDelete.enabled", default: false, scope: .appGroup, flags: [.extensions])
    /// Keep one's own outgoing messages deleted «for everyone» (here or on another device).
    public static let keepOwn = WGSetting<Bool>("antiDelete.keepOwn", default: false, scope: .appGroup, flags: [.extensions])
    /// Keep incoming self-destructing messages (timers, view-once) when the timer fires.
    public static let keepSelfDestructing = WGSetting<Bool>("antiDelete.keepSelfDestructing", default: false, scope: .appGroup, flags: [.extensions])
    /// Apply all of the above to secret chats as well.
    public static let secretChats = WGSetting<Bool>("antiDelete.secretChats", default: false, scope: .appGroup, flags: [.extensions])
    /// Keep previous versions of edited messages.
    public static let editHistory = WGSetting<Bool>("antiDelete.editHistory", default: false, scope: .appGroup, flags: [.extensions])
    public static let excludeGroups = WGSetting<Bool>("antiDelete.excludeGroups", default: false, scope: .appGroup, flags: [.extensions])
    public static let excludeBots = WGSetting<Bool>("antiDelete.excludeBots", default: false, scope: .appGroup, flags: [.extensions])
    public static let excludeChannels = WGSetting<Bool>("antiDelete.excludeChannels", default: false, scope: .appGroup, flags: [.extensions])
    /// Excluded chats still keep previous versions of edited messages.
    public static let editsInExclusions = WGSetting<Bool>("antiDelete.editsInExclusions", default: false, scope: .appGroup, flags: [.extensions])

    /// Chats excluded by hand (the whole PeerId; a secret chat follows its user).
    public static let excludedPeers = WGAccountSetting<Set<WGPeerKey>>("antiDelete.excludedPeers", default: [], flags: [.extensions])
    /// Folders whose chats are excluded (folder ids of this account).
    public static let excludedFolders = WGAccountSetting<Set<Int32>>("antiDelete.excludedFolders", default: [])
    /// The chats of `excludedFolders`, kept up to date by the app while the account runs
    /// (folders change, chats move). Derived data: not exported, recomputed after a reset.
    public static let excludedFolderPeers = WGAccountSetting<Set<WGPeerKey>>("antiDelete.excludedFolderPeers", default: [], flags: [.extensions, .noExport])

    // MARK: App only

    /// Keep a copy of the media of deleted messages (not for secret chats).
    public static let keepMedia = WGSetting<Bool>("antiDelete.keepMedia", default: false)
    /// Transparency of deleted messages, percent 0…80.
    public static let transparency = WGSetting<Double>("antiDelete.transparency", default: 45.0)
    /// Previous versions are shown under the text (otherwise only in «История правок»).
    public static let editHistoryInline = WGSetting<Bool>("antiDelete.editHistoryInline", default: false)
    /// Transparency of the previous versions shown under the text, percent 0…80.
    public static let versionsTransparency = WGSetting<Double>("antiDelete.versionsTransparency", default: 45.0)
    /// «Изменить локально» in the message menu.
    public static let localEdit = WGSetting<Bool>("antiDelete.localEdit", default: false)
    /// `WGAntiDeleteRetention` raw value.
    public static let autoClear = WGSetting<String>("antiDelete.autoClear", default: WGAntiDeleteRetention.never.rawValue)

    /// The old client's archive was imported into this account.
    public static let legacyImportDone = WGAccountSetting<Bool>("antiDelete.legacyImportDone", default: false, flags: [.noExport])

    public static let transparencyRange: ClosedRange<Double> = 0.0 ... 80.0

    static func declare() {
        let _ = WGAntiDeleteSettings.enabled
        let _ = WGAntiDeleteSettings.keepOwn
        let _ = WGAntiDeleteSettings.keepSelfDestructing
        let _ = WGAntiDeleteSettings.secretChats
        let _ = WGAntiDeleteSettings.editHistory
        let _ = WGAntiDeleteSettings.excludeGroups
        let _ = WGAntiDeleteSettings.excludeBots
        let _ = WGAntiDeleteSettings.excludeChannels
        let _ = WGAntiDeleteSettings.editsInExclusions
        let _ = WGAntiDeleteSettings.excludedPeers
        let _ = WGAntiDeleteSettings.excludedFolders
        let _ = WGAntiDeleteSettings.excludedFolderPeers
        let _ = WGAntiDeleteSettings.keepMedia
        let _ = WGAntiDeleteSettings.transparency
        let _ = WGAntiDeleteSettings.editHistoryInline
        let _ = WGAntiDeleteSettings.versionsTransparency
        let _ = WGAntiDeleteSettings.localEdit
        let _ = WGAntiDeleteSettings.autoClear
        let _ = WGAntiDeleteSettings.legacyImportDone
        let _ = WGBookmarkSettings.enabled
    }

    /// Alpha of a deleted message from the transparency percent (clamped like the slider).
    public static func alpha(forTransparency value: Double) -> CGFloat {
        let clamped = min(WGAntiDeleteSettings.transparencyRange.upperBound, max(WGAntiDeleteSettings.transparencyRange.lowerBound, value))
        return CGFloat(1.0 - clamped / 100.0)
    }
}

public enum WGBookmarkSettings {
    /// «Закладка» in the message menu, the marker on the bubble and the row under the chat search.
    public static let enabled = WGSetting<Bool>("bookmarks.enabled", default: false)
}
