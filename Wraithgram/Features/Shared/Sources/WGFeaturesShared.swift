import Foundation

/// Light aggregator linked into the app and into the extensions (notification service, share).
/// Each zone owns its `Sources/<Zone>/<Zone>Shared.swift`; nobody edits this file after wave 1.
public enum WGFeaturesShared {
    /// App process: called by `WGFeatures.registerAll()` before the feature modules register.
    public static func registerForApp() {
        WGFeaturesShared.registerZones()
    }

    /// Extension processes: called instead of `WGFeatures.registerAll()`, after `WGCore.bootstrap`
    /// and before `WGHookRegistry.freeze()`.
    public static func registerForExtension() {
        WGFeaturesShared.registerZones()
    }

    private static func registerZones() {
        WGGhostModeShared.register()
        WGAntiDeleteShared.register()
        WGMessagesShared.register()
        WGAppearanceShared.register()
        WGInterfaceShared.register()
        WGVoiceShared.register()
        WGCameraMasksShared.register()
        WGCallsMediaShared.register()
        WGSecurityShared.register()
        WGNetworkSpoofShared.register()
        WGProfileExportShared.register()
        // W5-SG: Swiftgram-parity features (settings, NSE flag, TelegramCore points).
        WGExtrasShared.register()
    }
}
