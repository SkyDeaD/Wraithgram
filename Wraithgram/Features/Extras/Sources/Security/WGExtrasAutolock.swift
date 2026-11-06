import Foundation
import WGCore
import WGHooks
import WGFeaturesShared

/// «Через 5 секунд» in Telegram's auto-lock menu (WGPasscodeUIHooks, the points W3-4's extra values
/// use). The app lock renews its «last active» mark every 2.5 s while 5 s is the chosen timeout
/// (`WGExtrasPolicy.appLockActivityRenewInterval(autolockTimeout:)`), so a short leave is measured fairly.
enum WGExtrasAutolock {
    static let fiveSeconds: Int32 = 5

    static func register() {
        WGPasscodeUIHooks.autolockValues.register({ values in
            if !WGExtrasSettings.autolockFiveSeconds.value {
                return values
            }
            var result = values.filter { $0 != 0 }
            result.append(WGExtrasAutolock.fiveSeconds)
            return [0] + Set(result).sorted()
        }, order: -100)
        // Before W3-4's titles: they count whole minutes and would call 5 s «1 minute».
        WGPasscodeUIHooks.autolockTitle.register({ timeout in
            if timeout > 0 && timeout < 60 {
                return WGStrings.Extras.Autolock.seconds(count: Int(timeout))
            }
            return nil
        }, order: -100)
    }
}
