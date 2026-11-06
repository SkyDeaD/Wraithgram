import Foundation
import WGCore

/// Every setting of the camera zone that the upstream camera modules read (round videos, the
/// gallery camera tile, watermarks). Declared once here, in a module that depends on WGCore only,
/// so `Camera`, `CameraNeo`, `CameraLegacy`, `MediaEditor` and the picker read the same registry the
/// menu writes. Defaults are Telegram's own behaviour: with every value at its default, all upstream
/// call sites take their original path.
///
/// Recording reads a snapshot (`WGRoundVideoConfig.recording()`) once per camera session, never
/// these values per frame.
public enum WGRoundVideoSettings {
    // MARK: Quality — 0 means «as Telegram does it»

    /// Side of the square in pixels: "standard" (Telegram's), "400", "512", "640".
    public static let resolution = WGSetting<String>("cameraMasks.roundVideo.resolution", default: "standard")
    /// Average video bitrate, kbit/s: 0 (Telegram's) or 500…4000 (a slider, step 500).
    public static let bitrate = WGSetting<Double>("cameraMasks.roundVideo.bitrate", default: 0.0)
    /// `WGRoundVideoCodec.rawValue`.
    public static let codec = WGSetting<String>("cameraMasks.roundVideo.codec", default: "h264")
    /// "30" or "60".
    public static let frameRate = WGSetting<String>("cameraMasks.roundVideo.frameRate", default: "30")
    /// `WGRoundVideoStabilization.rawValue`.
    public static let stabilization = WGSetting<String>("cameraMasks.roundVideo.stabilization", default: "standard")

    // MARK: Camera

    /// SG-F4: start round videos with the rear camera.
    public static let startWithRearCamera = WGSetting<Bool>("cameraMasks.roundVideo.rearCamera", default: false)
    /// `WGRoundVideoStartZoom.rawValue`.
    public static let startZoom = WGSetting<String>("cameraMasks.roundVideo.startZoom", default: "one")
    public static let rememberZoom = WGSetting<Bool>("cameraMasks.roundVideo.rememberZoom", default: false)
    public static let zoomSlider = WGSetting<Bool>("cameraMasks.roundVideo.zoomSlider", default: false)
    /// The back camera opens at 0.5× (the ultra-wide lens), at the start and after a flip
    /// (owner, 2026-10-28).
    public static let rearHalfZoom = WGSetting<Bool>("cameraMasks.roundVideo.rearHalfZoom", default: false)
    /// The zoom multiplier the user left the camera at (only kept while `rememberZoom` is on).
    public static let lastZoom = WGSetting<Double>("cameraMasks.roundVideo.lastZoom", default: 1.0, flags: [.noExport])
    public static let flipAnimation = WGSetting<Bool>("cameraMasks.roundVideo.flipAnimation", default: false)

    // MARK: Recording

    public static let countdown = WGSetting<Bool>("cameraMasks.roundVideo.countdown", default: false)
    public static let viewOnceByDefault = WGSetting<Bool>("cameraMasks.roundVideo.viewOnce", default: false)
    public static let sendAsRegularVideo = WGSetting<Bool>("cameraMasks.roundVideo.sendAsVideo", default: false)
    public static let saveCopyToGallery = WGSetting<Bool>("cameraMasks.roundVideo.saveToGallery", default: false)

    // MARK: Sound

    /// `WGRoundVideoMicrophoneMode.rawValue`; "default" leaves the audio session as Telegram sets it.
    public static let microphoneMode = WGSetting<String>("cameraMasks.roundVideo.microphone", default: "default")
    public static let normalizeAudio = WGSetting<Bool>("cameraMasks.roundVideo.normalize", default: false)
    public static let muteAudio = WGSetting<Bool>("cameraMasks.roundVideo.mute", default: false)

    // MARK: Watermark over the circle

    public static let watermark = WGSetting<Bool>("cameraMasks.roundVideo.watermark", default: false)
    public static let watermarkText = WGSetting<String>("cameraMasks.roundVideo.watermarkText", default: "")
    /// `WGRoundWatermarkPosition.rawValue`.
    public static let watermarkPosition = WGSetting<String>("cameraMasks.roundVideo.watermarkPosition", default: "bottom")
    /// `WGWatermarkFont.rawValue`.
    public static let watermarkFont = WGSetting<String>("cameraMasks.roundVideo.watermarkFont", default: "bold")
    /// % of the side, 2…12.
    public static let watermarkSize = WGSetting<Double>("cameraMasks.roundVideo.watermarkSize", default: 6.0)
    /// %, 10…100.
    public static let watermarkOpacity = WGSetting<Double>("cameraMasks.roundVideo.watermarkOpacity", default: 55.0)
    /// `WGWatermarkColor.rawValue`.
    public static let watermarkColor = WGSetting<String>("cameraMasks.roundVideo.watermarkColor", default: "white")

    // MARK: Gallery

    /// Every video picked from the gallery goes out as a round video.
    public static let galleryVideosAsRound = WGSetting<Bool>("cameraMasks.roundVideo.galleryAsRound", default: false)
    /// «Send as a round video» in the attachment picker's «…» menu (for the chosen videos only).
    public static let galleryMenuItem = WGSetting<Bool>("cameraMasks.roundVideo.galleryMenuItem", default: false)

    /// Settings the «reset the round video settings» row resets (the watermark and the gallery keys
    /// have their own rows and are reset with it as well).
    public static var resettableKeys: [WGRoundVideoAnySetting] {
        return [
            WGRoundVideoAnySetting(WGRoundVideoSettings.resolution),
            WGRoundVideoAnySetting(WGRoundVideoSettings.bitrate),
            WGRoundVideoAnySetting(WGRoundVideoSettings.codec),
            WGRoundVideoAnySetting(WGRoundVideoSettings.frameRate),
            WGRoundVideoAnySetting(WGRoundVideoSettings.stabilization),
            WGRoundVideoAnySetting(WGRoundVideoSettings.startWithRearCamera),
            WGRoundVideoAnySetting(WGRoundVideoSettings.startZoom),
            WGRoundVideoAnySetting(WGRoundVideoSettings.rememberZoom),
            WGRoundVideoAnySetting(WGRoundVideoSettings.zoomSlider),
            WGRoundVideoAnySetting(WGRoundVideoSettings.rearHalfZoom),
            WGRoundVideoAnySetting(WGRoundVideoSettings.lastZoom),
            WGRoundVideoAnySetting(WGRoundVideoSettings.flipAnimation),
            WGRoundVideoAnySetting(WGRoundVideoSettings.countdown),
            WGRoundVideoAnySetting(WGRoundVideoSettings.viewOnceByDefault),
            WGRoundVideoAnySetting(WGRoundVideoSettings.sendAsRegularVideo),
            WGRoundVideoAnySetting(WGRoundVideoSettings.saveCopyToGallery),
            WGRoundVideoAnySetting(WGRoundVideoSettings.microphoneMode),
            WGRoundVideoAnySetting(WGRoundVideoSettings.normalizeAudio),
            WGRoundVideoAnySetting(WGRoundVideoSettings.muteAudio),
            WGRoundVideoAnySetting(WGRoundVideoSettings.watermark),
            WGRoundVideoAnySetting(WGRoundVideoSettings.watermarkText),
            WGRoundVideoAnySetting(WGRoundVideoSettings.watermarkPosition),
            WGRoundVideoAnySetting(WGRoundVideoSettings.watermarkFont),
            WGRoundVideoAnySetting(WGRoundVideoSettings.watermarkSize),
            WGRoundVideoAnySetting(WGRoundVideoSettings.watermarkOpacity),
            WGRoundVideoAnySetting(WGRoundVideoSettings.watermarkColor),
            WGRoundVideoAnySetting(WGRoundVideoSettings.galleryVideosAsRound),
            WGRoundVideoAnySetting(WGRoundVideoSettings.galleryMenuItem)
        ]
    }

    static func declare() {
        let _ = WGRoundVideoSettings.resettableKeys
    }
}

/// A type-erased setting for the reset row.
public struct WGRoundVideoAnySetting {
    public let key: String
    public let isDefault: () -> Bool
    public let reset: () -> Void

    init<Value>(_ setting: WGSetting<Value>) {
        self.key = setting.key
        self.isDefault = {
            return setting.isDefault
        }
        self.reset = {
            setting.reset()
        }
    }
}

/// SG-F5: the camera tile in the attachment gallery.
public enum WGGalleryCameraSettings {
    /// No camera tile at all (the picker never starts the camera).
    public static let hideCamera = WGSetting<Bool>("cameraMasks.gallery.hideCamera", default: false)
    /// The tile stays but shows no live feed until it is tapped.
    public static let noLivePreview = WGSetting<Bool>("cameraMasks.gallery.noLivePreview", default: false)

    static func declare() {
        let _ = WGGalleryCameraSettings.hideCamera
        let _ = WGGalleryCameraSettings.noLivePreview
    }
}

/// «Водяной знак на фото». Read once per photo as a snapshot (`WGPhotoWatermarkConfig.current()`).
/// App Group settings: photos sent from other apps through the share extension get the mark too.
/// (Until 13.0 (190) they were global, under `cameraMasks.photoWatermark.*`; moved by the migration
/// `cameraMasks.photoWatermark.appGroup.v1`.)
public enum WGPhotoWatermarkSettings {
    public static let enabled = WGSetting<Bool>("cameraMasks.outgoingWatermark.enabled", default: false, scope: .appGroup, flags: [.extensions])
    public static let text = WGSetting<String>("cameraMasks.outgoingWatermark.text", default: "", scope: .appGroup, flags: [.extensions])
    /// `WGPhotoWatermarkPosition.rawValue`.
    public static let position = WGSetting<String>("cameraMasks.outgoingWatermark.position", default: "bottomRight", scope: .appGroup, flags: [.extensions])
    /// `WGWatermarkFont.rawValue`.
    public static let font = WGSetting<String>("cameraMasks.outgoingWatermark.font", default: "bold", scope: .appGroup, flags: [.extensions])
    /// % of the short side, 2…12.
    public static let size = WGSetting<Double>("cameraMasks.outgoingWatermark.size", default: 4.0, scope: .appGroup, flags: [.extensions])
    /// %, 10…100.
    public static let opacity = WGSetting<Double>("cameraMasks.outgoingWatermark.opacity", default: 55.0, scope: .appGroup, flags: [.extensions])
    /// `WGWatermarkColor.rawValue`.
    public static let color = WGSetting<String>("cameraMasks.outgoingWatermark.color", default: "white", scope: .appGroup, flags: [.extensions])
    public static let tiled = WGSetting<Bool>("cameraMasks.outgoingWatermark.tiled", default: false, scope: .appGroup, flags: [.extensions])

    /// Also from the share extension's launch: the extension reads these.
    public static func declare() {
        let _ = WGPhotoWatermarkSettings.enabled
        let _ = WGPhotoWatermarkSettings.text
        let _ = WGPhotoWatermarkSettings.position
        let _ = WGPhotoWatermarkSettings.font
        let _ = WGPhotoWatermarkSettings.size
        let _ = WGPhotoWatermarkSettings.opacity
        let _ = WGPhotoWatermarkSettings.color
        let _ = WGPhotoWatermarkSettings.tiled
    }
}

public enum WGRoundVideoCodec: String, CaseIterable {
    case h264
    case hevc
}

public enum WGRoundVideoStabilization: String, CaseIterable {
    case standard
    case off
    case cinematic
}

/// 0.5× is not a start zoom: it is «0,5× на задней камере» (`WGRoundVideoSettings.rearHalfZoom`).
public enum WGRoundVideoStartZoom: String, CaseIterable {
    case one
    case two
    case last

    /// Fixed multiplier of the camera's neutral (1×) zoom; `last` is resolved by the config.
    public var multiplier: Double? {
        switch self {
        case .one:
            return 1.0
        case .two:
            return 2.0
        case .last:
            return nil
        }
    }
}

public enum WGRoundVideoMicrophoneMode: String, CaseIterable {
    /// The audio session as Telegram configures it.
    case standard = "default"
    /// `AVAudioSession.Mode.videoRecording`: no voice processing.
    case videoRecording
    /// `AVAudioSession.Mode.voiceChat`: the system's noise and echo cancellation.
    case voiceChat
}

public enum WGWatermarkFont: String, CaseIterable {
    case regular
    case bold
    case mono
    case italic
}

public enum WGWatermarkColor: String, CaseIterable {
    case white
    case black
    case red
    case yellow
}

/// Positions inside the circle: only horizontally centred ones, corners would be cut by the mask.
public enum WGRoundWatermarkPosition: String, CaseIterable {
    case bottom
    case top
    case center
}

public enum WGPhotoWatermarkPosition: String, CaseIterable {
    case bottomRight
    case bottomLeft
    case topRight
    case topLeft
    case center
}

public enum WGCameraPipelineSettings {
    /// Touches every declaration of this module (called from `WGCameraMasksModule.register()`).
    public static func declare() {
        WGRoundVideoSettings.declare()
        WGGalleryCameraSettings.declare()
        WGPhotoWatermarkSettings.declare()
    }
}
