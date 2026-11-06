import Foundation
import WGCore
import WGCameraPipeline
import WGFeaturesShared

/// One-time moves of the old app's settings of this zone. Only values the user really stored are
/// moved (a missing key keeps the new default, which is Telegram's behaviour). Files (own masks,
/// virtual camera media) are moved separately, off the launch thread, by the stores.
enum WGCameraMasksMigrations {
    static func register() {
        WGMigrations.registerGlobal(id: "cameraMasks.roundVideo.v1", WGCameraMasksMigrations.migrateRoundVideo)
        WGMigrations.registerGlobal(id: "cameraMasks.photoWatermark.v1", WGCameraMasksMigrations.migratePhotoWatermark)
        WGMigrations.registerGlobal(id: "cameraMasks.masks.v1", WGCameraMasksMigrations.migrateMasks)
        WGMigrations.registerGlobal(id: "cameraMasks.virtualCamera.v1", WGCameraMasksMigrations.migrateVirtualCamera)
        // Repairs of what builds up to 13.0 (190) carried over (MEDIA-11, MEDIA-13).
        WGMigrations.registerGlobal(id: "cameraMasks.photoWatermark.appGroup.v1", WGCameraMasksMigrations.movePhotoWatermarkToAppGroup)
        WGMigrations.registerGlobal(id: "cameraMasks.roundVideo.halfZoom.v1", WGCameraMasksMigrations.repairStartZoom)
        WGMigrations.registerGlobal(id: "cameraMasks.masks.catalogSelection.v1", WGCameraMasksMigrations.dropUnavailableCatalogMasks)
    }

    // MARK: Helpers

    private static func moveBool(_ legacy: WGLegacyDefaults, _ key: String, _ setting: WGSetting<Bool>) {
        if let value = legacy.bool(key) {
            setting.set(value)
        }
        legacy.removeLegacyKey(key)
    }

    private static func moveText(_ legacy: WGLegacyDefaults, _ key: String, _ setting: WGSetting<String>, limit: Int) {
        if let value = legacy.string(key) {
            setting.set(String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit)))
        }
        legacy.removeLegacyKey(key)
    }

    private static func moveNumber(_ legacy: WGLegacyDefaults, _ key: String, _ setting: WGSetting<Double>, range: ClosedRange<Double>) {
        if let value = legacy.double(key) {
            setting.set(min(range.upperBound, max(range.lowerBound, value.rounded())))
        }
        legacy.removeLegacyKey(key)
    }

    /// An old integer code → the new string value; unknown codes keep the default.
    private static func moveCode(_ legacy: WGLegacyDefaults, _ key: String, _ setting: WGSetting<String>, _ map: [Int: String]) {
        if let code = legacy.int(key), let value = map[code] {
            setting.set(value)
        }
        legacy.removeLegacyKey(key)
    }

    private static let fontCodes: [Int: String] = [0: WGWatermarkFont.regular.rawValue, 1: WGWatermarkFont.bold.rawValue, 2: WGWatermarkFont.mono.rawValue, 3: WGWatermarkFont.italic.rawValue]
    private static let colorCodes: [Int: String] = [0: WGWatermarkColor.white.rawValue, 1: WGWatermarkColor.black.rawValue, 2: WGWatermarkColor.red.rawValue, 3: WGWatermarkColor.yellow.rawValue]

    // MARK: Round videos (`RoundVideo.*`, two `MiscSettings.*` keys)

    private static func migrateRoundVideo(_ legacy: WGLegacyDefaults) {
        // 400 is Telegram's own side; 720 was offered but is above what the server takes as a
        // round video, so it becomes the largest side that still is one.
        if let side = legacy.int("RoundVideo.resolution") {
            switch side {
            case 512:
                WGRoundVideoSettings.resolution.set("512")
            case 640, 720:
                WGRoundVideoSettings.resolution.set("640")
            default:
                break
            }
        }
        legacy.removeLegacyKey("RoundVideo.resolution")
        // 1000 kbit/s was the old default and is Telegram's own rate: it stays «standard».
        if let kbps = legacy.int("RoundVideo.bitrateKbps"), kbps != 1000 {
            WGRoundVideoSettings.bitrate.set(min(4000.0, max(500.0, (Double(kbps) / 500.0).rounded() * 500.0)))
        }
        legacy.removeLegacyKey("RoundVideo.bitrateKbps")
        WGCameraMasksMigrations.moveCode(legacy, "RoundVideo.fps", WGRoundVideoSettings.frameRate, [60: "60"])
        WGCameraMasksMigrations.moveCode(legacy, "RoundVideo.codec", WGRoundVideoSettings.codec, [1: WGRoundVideoCodec.hevc.rawValue])
        WGCameraMasksMigrations.moveCode(legacy, "RoundVideo.stabilization", WGRoundVideoSettings.stabilization, [0: WGRoundVideoStabilization.off.rawValue, 2: WGRoundVideoStabilization.cinematic.rawValue])
        // Code 0 (start at 0.5×) is «0,5× на задней камере» here: 0.5× exists only on the back camera.
        if legacy.int("RoundVideo.startZoom") == 0 {
            WGRoundVideoSettings.rearHalfZoom.set(true)
        }
        WGCameraMasksMigrations.moveCode(legacy, "RoundVideo.startZoom", WGRoundVideoSettings.startZoom, [2: WGRoundVideoStartZoom.two.rawValue, 3: WGRoundVideoStartZoom.last.rawValue])
        WGCameraMasksMigrations.moveBool(legacy, "RoundVideo.rememberZoom", WGRoundVideoSettings.rememberZoom)
        WGCameraMasksMigrations.moveBool(legacy, "RoundVideo.zoomSlider", WGRoundVideoSettings.zoomSlider)
        if let zoom = legacy.double("RoundVideo.lastZoomFactor") {
            WGRoundVideoSettings.lastZoom.set(min(WGRoundVideoConfig.maximumZoom, max(0.5, zoom)))
        }
        legacy.removeLegacyKey("RoundVideo.lastZoomFactor")
        WGCameraMasksMigrations.moveBool(legacy, "RoundVideo.sendAsRegularVideo", WGRoundVideoSettings.sendAsRegularVideo)
        WGCameraMasksMigrations.moveBool(legacy, "RoundVideo.countdownEnabled", WGRoundVideoSettings.countdown)
        WGCameraMasksMigrations.moveBool(legacy, "RoundVideo.viewOnceByDefault", WGRoundVideoSettings.viewOnceByDefault)
        WGCameraMasksMigrations.moveBool(legacy, "RoundVideo.saveCopyToGallery", WGRoundVideoSettings.saveCopyToGallery)
        // Code 0 («video recording») was the old default; the new default leaves the session as
        // Telegram sets it, so only the explicit «conversation» choice is carried over.
        WGCameraMasksMigrations.moveCode(legacy, "RoundVideo.micMode", WGRoundVideoSettings.microphoneMode, [1: WGRoundVideoMicrophoneMode.voiceChat.rawValue])
        WGCameraMasksMigrations.moveBool(legacy, "RoundVideo.normalizeAudio", WGRoundVideoSettings.normalizeAudio)
        WGCameraMasksMigrations.moveBool(legacy, "RoundVideo.muteAudio", WGRoundVideoSettings.muteAudio)
        WGCameraMasksMigrations.moveBool(legacy, "RoundVideo.watermarkEnabled", WGRoundVideoSettings.watermark)
        WGCameraMasksMigrations.moveText(legacy, "RoundVideo.watermarkText", WGRoundVideoSettings.watermarkText, limit: 48)
        WGCameraMasksMigrations.moveCode(legacy, "RoundVideo.watermarkPosition", WGRoundVideoSettings.watermarkPosition, [0: WGRoundWatermarkPosition.bottom.rawValue, 1: WGRoundWatermarkPosition.top.rawValue, 2: WGRoundWatermarkPosition.center.rawValue])
        WGCameraMasksMigrations.moveCode(legacy, "RoundVideo.watermarkFontStyle", WGRoundVideoSettings.watermarkFont, WGCameraMasksMigrations.fontCodes)
        WGCameraMasksMigrations.moveNumber(legacy, "RoundVideo.watermarkSize", WGRoundVideoSettings.watermarkSize, range: 2.0 ... 12.0)
        WGCameraMasksMigrations.moveNumber(legacy, "RoundVideo.watermarkOpacity", WGRoundVideoSettings.watermarkOpacity, range: 10.0 ... 100.0)
        WGCameraMasksMigrations.moveCode(legacy, "RoundVideo.watermarkColor", WGRoundVideoSettings.watermarkColor, WGCameraMasksMigrations.colorCodes)

        WGCameraMasksMigrations.moveBool(legacy, "MiscSettings.autoSendVideosAsRoundVideo", WGRoundVideoSettings.galleryVideosAsRound)
        // The one-shot «send the next video as a round video» flag is replaced by per-asset marks.
        legacy.removeLegacyKey("MiscSettings.sendNextAsRoundVideo")
        WGCameraMasksMigrations.moveBool(legacy, "MiscSettings.roundVideoFlipAnimation", WGRoundVideoSettings.flipAnimation)

        // SG-F4, round videos from the rear camera.
        WGCameraMasksMigrations.moveBool(legacy, "startTelescopeWithRearCam", WGRoundVideoSettings.startWithRearCamera)
        // SG-F5, the camera tile of the attachment gallery.
        WGCameraMasksMigrations.moveBool(legacy, "disableGalleryCamera", WGGalleryCameraSettings.hideCamera)
        WGCameraMasksMigrations.moveBool(legacy, "disableGalleryCameraPreview", WGGalleryCameraSettings.noLivePreview)
    }

    // MARK: Photo watermark (`MiscSettings.photoWatermark*`)

    private static func migratePhotoWatermark(_ legacy: WGLegacyDefaults) {
        WGCameraMasksMigrations.moveBool(legacy, "MiscSettings.photoWatermarkEnabled", WGPhotoWatermarkSettings.enabled)
        WGCameraMasksMigrations.moveText(legacy, "MiscSettings.photoWatermarkText", WGPhotoWatermarkSettings.text, limit: 40)
        WGCameraMasksMigrations.moveCode(legacy, "MiscSettings.photoWatermarkPosition", WGPhotoWatermarkSettings.position, [
            0: WGPhotoWatermarkPosition.bottomRight.rawValue,
            1: WGPhotoWatermarkPosition.topLeft.rawValue,
            2: WGPhotoWatermarkPosition.topRight.rawValue,
            3: WGPhotoWatermarkPosition.center.rawValue,
            4: WGPhotoWatermarkPosition.bottomLeft.rawValue
        ])
        WGCameraMasksMigrations.moveCode(legacy, "MiscSettings.photoWatermarkFontStyle", WGPhotoWatermarkSettings.font, WGCameraMasksMigrations.fontCodes)
        WGCameraMasksMigrations.moveNumber(legacy, "MiscSettings.photoWatermarkSize", WGPhotoWatermarkSettings.size, range: 2.0 ... 12.0)
        WGCameraMasksMigrations.moveNumber(legacy, "MiscSettings.photoWatermarkOpacity", WGPhotoWatermarkSettings.opacity, range: 10.0 ... 100.0)
        WGCameraMasksMigrations.moveCode(legacy, "MiscSettings.photoWatermarkColor", WGPhotoWatermarkSettings.color, WGCameraMasksMigrations.colorCodes)
        WGCameraMasksMigrations.moveBool(legacy, "MiscSettings.photoWatermarkTiled", WGPhotoWatermarkSettings.tiled)
    }

    // MARK: Masks and the anonymous mode

    /// A catalog mask can be used only while the catalog can be downloaded; the old app's copies of
    /// catalog masks are not carried over (`WGMaskStore.migrateLegacyMasks` drops them).
    private static func isUsable(_ selection: WGMaskSelection) -> Bool {
        switch selection {
        case .none:
            return false
        case .catalog:
            return WGMaskCatalog.isAvailable
        case .builtIn, .user:
            return true
        }
    }

    private static func migrateMasks(_ legacy: WGLegacyDefaults) {
        // A chosen mask applied to every round video in the old app: the new switch is turned on
        // only for users who had one this build can show (a catalog mask can not be prepared while
        // the catalog is off: the switch would be on and nothing would happen).
        if let stored = legacy.string("selectedVideoMaskSelection"), let selection = WGMaskSelection.fromLegacy(stored), WGCameraMasksMigrations.isUsable(selection) {
            WGMaskSettings.selection.set(selection.storage)
            WGMaskSettings.enabled.set(true)
        }
        legacy.removeLegacyKey("selectedVideoMaskSelection")
        if let megabytes = legacy.int("maskCacheDiskLimitMB") {
            let options = [50, 100, 200, 400, 800, 1024]
            let nearest = options.min(by: { abs($0 - megabytes) < abs($1 - megabytes) }) ?? 200
            WGMaskSettings.cacheLimit.set("\(nearest)")
        }
        legacy.removeLegacyKey("maskCacheDiskLimitMB")
        // «Apply automatically» never did anything (no reader in the old app): dropped.
        legacy.removeLegacyKey("videoMaskAutoApply")
        WGCameraMasksMigrations.moveBool(legacy, "videoMaskCallsEnabled", WGMaskSettings.inCalls)

        if let id = legacy.string("anonymousModeMaskId") {
            // An unusable one keeps the default anonymous mask, so the face is always covered.
            let selection = WGMaskSelection.fromLegacyMaskId(id)
            if WGCameraMasksMigrations.isUsable(selection) {
                WGAnonymousMode.mask.set(selection.storage)
            }
        }
        legacy.removeLegacyKey("anonymousModeMaskId")
        WGCameraMasksMigrations.moveText(legacy, "anonymousModeVoicePreset", WGAnonymousMode.voice, limit: 64)
        // The old mode was one switch for every account plus a snapshot of the voice changer it
        // restored on exit. The new mode is per account and never touches the user's own preset,
        // so the old state is not carried over: the mode starts off.
        for key in ["GG.anonymous.video.active", "GG.anonymous.voice.savedPresetId", "GG.anonymous.voice.savedEnabled", "GG.anonymous.voice.didSaveState"] {
            legacy.removeLegacyKey(key)
        }
        // The old catalog cache lived in UserDefaults; the new one is a file in Caches.
        legacy.removeLegacyKey("GG.masks.catalog.json")
        legacy.removeLegacyKey("GG.masks.catalog.fetchedAt")
    }

    // MARK: Repairs

    /// The photo watermark moved from global.json to the App Group file the share extension reads
    /// (MEDIA-12), under new keys: the values stored under the old ones are carried over.
    private static func movePhotoWatermarkToAppGroup(_ legacy: WGLegacyDefaults) {
        let prefix = "cameraMasks.photoWatermark."
        if let value = WGRetiredSettings.value(prefix + "enabled", as: Bool.self) {
            WGPhotoWatermarkSettings.enabled.set(value)
        }
        if let value = WGRetiredSettings.value(prefix + "text", as: String.self) {
            WGPhotoWatermarkSettings.text.set(value)
        }
        if let value = WGRetiredSettings.value(prefix + "position", as: String.self) {
            WGPhotoWatermarkSettings.position.set(value)
        }
        if let value = WGRetiredSettings.value(prefix + "font", as: String.self) {
            WGPhotoWatermarkSettings.font.set(value)
        }
        if let value = WGRetiredSettings.value(prefix + "size", as: Double.self) {
            WGPhotoWatermarkSettings.size.set(value)
        }
        if let value = WGRetiredSettings.value(prefix + "opacity", as: Double.self) {
            WGPhotoWatermarkSettings.opacity.set(value)
        }
        if let value = WGRetiredSettings.value(prefix + "color", as: String.self) {
            WGPhotoWatermarkSettings.color.set(value)
        }
        if let value = WGRetiredSettings.value(prefix + "tiled", as: Bool.self) {
            WGPhotoWatermarkSettings.tiled.set(value)
        }
        WGRetiredSettings.remove(prefixes: [prefix])
    }

    /// Builds up to 190 carried the old 0.5× start over as a start zoom no menu row offers; it is
    /// «0,5× на задней камере» now. A remembered zoom above the slider's end is cut to it.
    private static func repairStartZoom(_ legacy: WGLegacyDefaults) {
        if WGRoundVideoSettings.startZoom.value == "half" {
            WGRoundVideoSettings.startZoom.reset()
            WGRoundVideoSettings.rearHalfZoom.set(true)
        }
        if WGRoundVideoSettings.lastZoom.value > WGRoundVideoConfig.maximumZoom {
            WGRoundVideoSettings.lastZoom.set(WGRoundVideoConfig.maximumZoom)
        }
    }

    /// Builds up to 190 carried a catalog mask over and switched masks on, although the catalog is
    /// off and the old copies are gone: the choice is dropped (and masks switched off with it), the
    /// anonymous mask goes back to its default.
    private static func dropUnavailableCatalogMasks(_ legacy: WGLegacyDefaults) {
        if WGMaskCatalog.isAvailable {
            return
        }
        if case .catalog = WGMaskSelection(storage: WGMaskSettings.selection.value) {
            WGMaskSettings.selection.reset()
            WGMaskSettings.enabled.set(false)
        }
        if case .catalog = WGMaskSelection(storage: WGAnonymousMode.mask.value) {
            WGAnonymousMode.mask.reset()
        }
    }

    // MARK: Virtual camera (`wgCallVirtualCamera*`)

    private struct LegacyCallMediaItem: Decodable {
        let id: String
        let title: String
        let fileName: String
        let kind: String
        let createdAt: Double
    }

    private static func migrateVirtualCamera(_ legacy: WGLegacyDefaults) {
        if let raw = legacy.string("ggCallVirtualCameraItems"), let data = raw.data(using: .utf8), let items = try? JSONDecoder().decode([LegacyCallMediaItem].self, from: data) {
            // Audio items belong to the soundboard (calls zone), not to the camera.
            let converted: [WGVirtualCameraItem] = items.compactMap { item in
                guard let kind = WGVirtualCameraItem.Kind(rawValue: item.kind) else {
                    return nil
                }
                return WGVirtualCameraItem(id: item.id, title: item.title, fileName: item.fileName, kind: kind, createdAt: item.createdAt)
            }
            if !converted.isEmpty {
                WGVirtualCameraSettings.items.set(converted)
            }
        }
        legacy.removeLegacyKey("ggCallVirtualCameraItems")
        WGCameraMasksMigrations.moveBool(legacy, "ggCallVirtualCameraEnabled", WGVirtualCameraSettings.enabled)
        if let selected = legacy.string("ggCallVirtualCameraSelectedId"), WGVirtualCameraSettings.items.value.contains(where: { $0.id == selected }) {
            WGVirtualCameraSettings.selected.set(selected)
        }
        legacy.removeLegacyKey("ggCallVirtualCameraSelectedId")
        WGCameraMasksMigrations.moveBool(legacy, "ggCallVirtualCameraLoop", WGVirtualCameraSettings.loop)
    }
}
