import Foundation
import WGCore

/// The part of WGGhostMode that the extensions (notification service, share) also link: the
/// settings and the policy that decides what leaves the device (read receipts, story views,
/// "typing", online, send delay). Owner: W2-1.
public enum WGGhostModeShared {
    /// Called from `WGFeaturesShared.registerForApp()` and `.registerForExtension()`; check
    /// `WGCore.environment?.process` for what only one of them needs.
    public static func register() {
        WGGhostSettings.declare()
        WGGhostCoreHandlers.register()
    }
}
