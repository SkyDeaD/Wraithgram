import Foundation

/// Entry point of the WGCallsMedia feature module. Owner: W3-3.
public enum WGCallsMediaModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `WGFeatures.registerAll()`, before `WGHookRegistry.freeze()`.
    public static func register() {
        assert(Thread.isMainThread)
        WGCallsMediaSettings.declare()
        WGCallsMediaMigrations.register()

        WGTransferTuning.register()
        WGGalleryTweaks.register()
        WGSubtitlesFeature.register()
        WGDownloadStatusViews.register()
        WGCallFeatures.register()
        WGCallsMediaMenu.register()

        // Handlers of the points that requests R1 and R2 add to WGHooks (Sources/Pending).
        WGCallsMediaPending.register()
    }
}
