import Foundation

/// Entry point of the WGInterface feature module. Owner: W2-5.
public enum WGInterfaceModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `WGFeatures.registerAll()`, before `WGHookRegistry.freeze()`.
    public static func register() {
        assert(Thread.isMainThread)
        InterfaceSettings.declare()
        InterfaceMigrations.register()
        // Hot paths read this snapshot; it follows every settings change from here on.
        InterfaceSnapshots.shared.start()

        WGChatListFeature.register()
        WGFoldersFeature.register()
        WGTabBarFeature.register()
        WGSettingsTabLayout.register()
        WGInputFeature.register()
        WGInputBarEditor.register()
        WGQuickButtonsFeature.register()
        WGCustomReactions.register()
        WGIconPackResolver.shared.register()
        WGIconPackStorage.shared.migrateLegacyPacksIfNeeded()
        WGIslandBadge.shared.register()
        // Handlers of points that request R4/R9 add to WGHooks (Sources/Pending).
        WGInterfacePending.register()

        InterfaceMenu.register()
    }
}
