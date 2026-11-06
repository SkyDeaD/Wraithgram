import Foundation
import WGCore
import WGFeaturesShared

/// One sound of the call soundboard. The file lives in the soundboard directory (`WGCallSoundLibrary`);
/// only these metadata are in the settings registry.
struct WGCallSoundItem: Codable, Equatable, WGSettingValue {
    var id: String
    var title: String
    var fileName: String
    /// A sound imported by the old Wraithgram: the file is still in its old `Documents/ggcall/soundboard`.
    var isLegacy: Bool
    var createdAt: Double
}

/// One saved call recording of an account. The file is in that account's recordings directory.
struct WGCallRecordingItem: Codable, Equatable, WGSettingValue {
    enum Kind: String, Codable {
        case audio
        case video
    }

    var id: String
    var fileName: String
    var kind: Kind
    /// Peer of the 1:1 call (canonical key) and its name at the time of the call.
    var peer: WGPeerKey?
    var peerTitle: String
    var startDate: Double
    var duration: Double
    var size: Int64
}

enum WGDownloadBoostMode: String {
    case off
    case medium
    case maximum
}

/// Every setting of the zone. Declared once here; defaults only here.
enum WGCallsMediaSettings {
    // MARK: Calls

    /// `WGCallRecordingMode.rawValue` (one choice since 2026-10-27; replaced «аудиозвонки» / «видеозвонки»).
    static let recordCalls = WGSetting<String>("calls.record", default: WGCallRecordingMode.off.rawValue)
    static let recordOwnVoice = WGSetting<Bool>("calls.recordOwnVoice", default: false)
    static let silentMute = WGSetting<Bool>("calls.silentMute", default: false)
    static let disableRating = WGSetting<Bool>("calls.disableRating", default: false)
    static let statsOverlay = WGSetting<Bool>("calls.statsOverlay", default: false)
    /// Origin of the dragged stats panel, `[x, y]` relative to the screen; empty = default corner.
    static let statsPanelOrigin = WGSetting<[Double]>("calls.statsPanelOrigin", default: [], flags: [.noExport])
    static let soundboard = WGSetting<Bool>("calls.soundboard", default: false)
    /// 0.1…1.0.
    static let soundboardVolume = WGSetting<Double>("calls.soundboardVolume", default: 0.8)
    static let soundboardDuck = WGSetting<Bool>("calls.soundboardDuck", default: false)
    /// Files stay on this device, so the list is not exported.
    static let soundboardItems = WGSetting<[WGCallSoundItem]>("calls.soundboardItems", default: [], flags: [.noExport])
    static let forceTcp = WGSetting<Bool>("calls.forceTcp", default: false)
    /// Recordings of the account (files in the account's directory).
    static let recordings = WGAccountSetting<[WGCallRecordingItem]>("calls.recordings", default: [], flags: [.noExport])

    /// What «Записывать звонки» is set to.
    static var recordingMode: WGCallRecordingMode {
        return WGCallRecordingMode.resolved(WGCallsMediaSettings.recordCalls.value)
    }

    // MARK: Downloads and quality

    static let statusInChatList = WGSetting<Bool>("downloads.statusInChatList", default: false)
    static let statusInChat = WGSetting<Bool>("downloads.statusInChat", default: false)
    static let uploadBoost = WGSetting<Bool>("downloads.uploadBoost", default: false)
    /// `WGDownloadBoostMode` raw value.
    static let downloadBoost = WGSetting<String>("downloads.downloadBoost", default: WGDownloadBoostMode.off.rawValue)
    /// Declared in WGFeaturesShared (App Group): the share extension follows them too.
    static let photoQuality = WGOutgoingPhotoSettings.quality
    static let largePhotos = WGOutgoingPhotoSettings.largePhotos

    // MARK: Gallery

    /// On by default: Swiftgram adds both items always (W6-SGD, owner's decision 2026-10-29).
    static let copyPhotoItem = WGSetting<Bool>("gallery.copyPhoto", default: true)
    static let airPlayItem = WGSetting<Bool>("gallery.airPlay", default: true)

    // MARK: Subtitles

    static let subtitles = WGSetting<Bool>("subtitles.enabled", default: false)
    static let subtitlesTranslate = WGSetting<Bool>("subtitles.translate", default: false)
    /// Target language code; "" = the language of the app.
    static let subtitlesLanguage = WGSetting<String>("subtitles.language", default: "")

    static func declare() {
        let _ = WGCallsMediaSettings.recordCalls
        let _ = WGCallsMediaSettings.recordOwnVoice
        let _ = WGCallsMediaSettings.silentMute
        let _ = WGCallsMediaSettings.disableRating
        let _ = WGCallsMediaSettings.statsOverlay
        let _ = WGCallsMediaSettings.statsPanelOrigin
        let _ = WGCallsMediaSettings.soundboard
        let _ = WGCallsMediaSettings.soundboardVolume
        let _ = WGCallsMediaSettings.soundboardDuck
        let _ = WGCallsMediaSettings.soundboardItems
        let _ = WGCallsMediaSettings.forceTcp
        let _ = WGCallsMediaSettings.recordings

        let _ = WGCallsMediaSettings.statusInChatList
        let _ = WGCallsMediaSettings.statusInChat
        let _ = WGCallsMediaSettings.uploadBoost
        let _ = WGCallsMediaSettings.downloadBoost
        let _ = WGCallsMediaSettings.photoQuality
        let _ = WGCallsMediaSettings.largePhotos

        let _ = WGCallsMediaSettings.copyPhotoItem
        let _ = WGCallsMediaSettings.airPlayItem

        let _ = WGCallsMediaSettings.subtitles
        let _ = WGCallsMediaSettings.subtitlesTranslate
        let _ = WGCallsMediaSettings.subtitlesLanguage
    }
}
