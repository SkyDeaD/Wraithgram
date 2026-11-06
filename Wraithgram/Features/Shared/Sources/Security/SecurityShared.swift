import Foundation
import WGCore

/// The part of WGSecurity that the extensions (notification service, share) also link: settings with
/// `.extensions`, NSE handlers, attribute declarations. Owner: W3-4.
public enum WGSecurityShared {
    /// Called from `WGFeaturesShared.registerForApp()` and `.registerForExtension()`; check
    /// `WGCore.environment?.process` for what only one of them needs.
    public static func register() {
        // Account limit (W3-4b): 100 with and without Premium, app process only.
        WGAccountLimit.register()

        // W3-4: every setting of the zone, then what the extensions need — which chats are protected
        // (push text, Siri, banners, widget). Migrations only in the app, before the feature modules.
        WGSecuritySharedSettings.declare()
        WGSecuritySettings.declare()
        WGChatProtection.register()
        if WGCore.environment?.process.isApp ?? false {
            WGSecurityMigrations.register()
        }
    }
}
