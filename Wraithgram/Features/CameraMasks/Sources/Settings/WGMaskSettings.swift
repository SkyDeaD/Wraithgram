import Foundation
import WGCore

/// Settings of the masks themselves (round videos, calls, the catalog, the virtual camera). The
/// camera-pipeline settings (round video quality, watermarks, gallery camera) live in
/// WGCameraPipeline, the anonymous mode in WGFeaturesShared.
enum WGMaskSettings {
    /// Masks in round videos: the button and panel on the camera screen, and processing.
    static let enabled = WGSetting<Bool>("cameraMasks.masks.enabled", default: false)
    /// `WGMaskSelection.storage`.
    static let selection = WGSetting<String>("cameraMasks.masks.selection", default: "")
    /// The same mask in calls (front camera).
    static let inCalls = WGSetting<Bool>("cameraMasks.masks.calls", default: false)
    /// Disk limit of downloaded catalog masks, MB: "50", "100", "200", "400", "800", "1024".
    static let cacheLimit = WGSetting<String>("cameraMasks.masks.cacheLimit", default: "200")
    /// Service state of the catalog: never exported.
    static let catalogETag = WGSetting<String>("cameraMasks.masks.catalogETag", default: "", flags: [.noExport])
    static let catalogFetchedAt = WGSetting<Double>("cameraMasks.masks.catalogFetchedAt", default: 0.0, flags: [.noExport])

    static func declare() {
        let _ = WGMaskSettings.enabled
        let _ = WGMaskSettings.selection
        let _ = WGMaskSettings.inCalls
        let _ = WGMaskSettings.cacheLimit
        let _ = WGMaskSettings.catalogETag
        let _ = WGMaskSettings.catalogFetchedAt
    }
}

/// One item of the virtual camera library: metadata here, the file in the app container.
struct WGVirtualCameraItem: Codable, Equatable, WGSettingValue {
    enum Kind: String, Codable {
        case image
        case gif
        case video
    }

    var id: String
    var title: String
    /// File name only (the container path changes between installs).
    var fileName: String
    var kind: Kind
    var createdAt: Double
}

enum WGVirtualCameraSettings {
    /// Calls send a picture, GIF or video instead of the camera.
    static let enabled = WGSetting<Bool>("cameraMasks.virtualCamera.enabled", default: false)
    /// Id of the chosen item; "" = none (the real camera).
    static let selected = WGSetting<String>("cameraMasks.virtualCamera.selected", default: "")
    /// A video starts over at the end (otherwise its last frame stays).
    static let loop = WGSetting<Bool>("cameraMasks.virtualCamera.loop", default: false)
    /// The library (files stay on this device: not exported).
    static let items = WGSetting<[WGVirtualCameraItem]>("cameraMasks.virtualCamera.items", default: [], flags: [.noExport])

    static func declare() {
        let _ = WGVirtualCameraSettings.enabled
        let _ = WGVirtualCameraSettings.selected
        let _ = WGVirtualCameraSettings.loop
        let _ = WGVirtualCameraSettings.items
    }

    static var selectedItem: WGVirtualCameraItem? {
        guard WGVirtualCameraSettings.enabled.value else {
            return nil
        }
        let id = WGVirtualCameraSettings.selected.value
        if id.isEmpty {
            return nil
        }
        return WGVirtualCameraSettings.items.value.first(where: { $0.id == id })
    }
}
