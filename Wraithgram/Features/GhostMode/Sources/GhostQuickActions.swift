import Foundation
import WGCore
import WGFeaturesShared

/// The zone's buttons of «Кнопки быстрого доступа» in a chat (W2-5's `WGQuickActions`): ghost mode
/// and delayed sending of the account, as switches. The buttons themselves are drawn by WGInterface.
enum WGGhostQuickActions {
    static func register() {
        WGQuickActions.actions.register(WGQuickAction(
            id: WGQuickActionIds.ghostMode,
            order: 100,
            title: { WGStrings.GhostMode.Menu.group },
            iconName: "Chat/Context Menu/EyeLocked",
            isOn: { context in
                return WGGhostSettings.isEnabled.value(for: context.accountID)
            },
            perform: { context in
                let account = context.accountID
                WGGhostSettings.isEnabled.set(!WGGhostSettings.isEnabled.value(for: account), for: account)
            }
        ))
        WGQuickActions.actions.register(WGQuickAction(
            id: WGQuickActionIds.sendDelay,
            order: 400,
            title: { WGStrings.Menu.Tab.Privacy.sendDelay },
            iconName: "Chat/Context Menu/Schedule",
            isOn: { context in
                return WGGhostSettings.sendDelayEnabled.value(for: context.accountID)
            },
            perform: { context in
                let account = context.accountID
                WGGhostSettings.sendDelayEnabled.set(!WGGhostSettings.sendDelayEnabled.value(for: account), for: account)
            }
        ))
    }
}
