import Foundation
import WGSettingsUI
import WGFeaturesShared
import WGGhostMode
import WGAntiDelete
import WGMessages
import WGAppearance
import WGInterface
import WGVoice
import WGCameraMasks
import WGCallsMedia
import WGSecurity
import WGNetworkSpoof
import WGVless
import WGProfileExport
import WGExtras
import WGRegDate

/// Aggregator of the feature modules, called from `AppDelegate` (see FOUNDATION_SPEC §2):
/// `WGCore.bootstrap` → `WGFeatures.registerAll()` → `WGCore.runGlobalMigrations()` →
/// `WGHookRegistry.freeze()`. Only `register()` calls live here; nobody edits it after wave 1.
public enum WGFeatures {
    public static func registerAll() {
        assert(Thread.isMainThread)
        // The menu skeleton first: features add rows to its sections.
        WGSettingsUI.register()
        WGFeaturesShared.registerForApp()
        WGGhostModeModule.register()
        WGAntiDeleteModule.register()
        WGMessagesModule.register()
        WGAppearanceModule.register()
        WGInterfaceModule.register()
        WGVoiceModule.register()
        WGCameraMasksModule.register()
        WGCallsMediaModule.register()
        WGSecurityModule.register()
        WGNetworkSpoofModule.register()
        WGVlessModule.register()
        WGProfileExportModule.register()
        // W5-SG: Swiftgram-parity features.
        WGExtrasModule.register()
        // W7-RD2: «Дата регистрации».
        WGRegDateModule.register()
    }
}
