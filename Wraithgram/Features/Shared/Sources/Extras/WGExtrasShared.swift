import Foundation
import TelegramCore
import WGCore

/// The part of WGExtras (Swiftgram-parity features, W5-SG) that the extensions also link: the
/// settings (the notification service reads `hideAccountInNotifications`) and the handlers of the
/// points compiled into TelegramCore.
public enum WGExtrasShared {
    /// Called from `WGFeaturesShared.registerForApp()` and `.registerForExtension()`.
    public static func register() {
        WGExtrasSettings.declare()

        WGExtrasCoreHooks.restrictionText.register({ text, reason, platform in
            if !WGExtrasSettings.restrictionReasonCode.value || reason.isEmpty {
                return text
            }
            return text + "\n" + reason + "-" + platform
        })

        if WGCore.environment?.process.isApp ?? false {
            WGExtrasCoreHooks.searchesPartialWords.register({
                return WGExtrasSettings.searchPartialWords.value
            })
        }
    }
}
