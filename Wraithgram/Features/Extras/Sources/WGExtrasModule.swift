import Foundation
import WGCore
import WGFeaturesShared

/// Entry point of WGExtras: the Swiftgram user features Wraithgram did not have yet (W5-SG), written
/// as Wraithgram features. Settings and the TelegramCore points are in WGFeaturesShared
/// (`Sources/Extras/`, registered before this module); here — the menu and the app's handlers.
public enum WGExtrasModule {
    /// Declares menu rows and hook handlers. Called once on the main thread from
    /// `WGFeatures.registerAll()`, before `WGHookRegistry.freeze()`.
    public static func register() {
        WGExtrasMenu.register()
        WGExtrasProfileMenu.register()
        WGExtrasSelection.register()
        WGExtrasLinks.register()
        WGExtrasAutolock.register()
        WGExtrasRoutes.register()
        WGExtrasMigrations.register()
    }
}
