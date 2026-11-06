import Foundation
import Display
import AccountContext
import WGCore
import WGHooks

/// Shortcut links (Swiftgram's `tg://sg/…` routes, the ones a user has a use for):
/// `wraithgram://contacts` (also `wg://contacts`) opens the contacts, `wraithgram://ios_settings` the
/// app's page in the iOS Settings. Handy for Shortcuts and widgets. `wraithgram://settings` (the menu)
/// is WGSettingsUI's own.
enum WGExtrasRoutes {
    static func register() {
        WGLifecycleHooks.openURL.register({ url, context, _ in
            guard let scheme = url.scheme?.lowercased(), scheme == "wraithgram" || scheme == "wg" else {
                return false
            }
            switch url.host?.lowercased() ?? "" {
            case "contacts":
                guard let rootController = context.sharedContext.mainWindow?.viewController as? TelegramRootControllerInterface else {
                    return false
                }
                rootController.openContacts()
                return true
            case "ios_settings", "iossettings":
                context.sharedContext.applicationBindings.openSettings()
                return true
            default:
                return false
            }
        }, order: 900)
    }
}
