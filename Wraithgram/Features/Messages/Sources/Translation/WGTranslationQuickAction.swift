import Foundation
import WGCore
import WGFeaturesShared

/// The zone's button of «Кнопки быстрого доступа» in a chat (W2-5's `WGQuickActions`):
/// «Переводить перед отправкой» as a switch.
enum WGTranslationQuickAction {
    static func register() {
        WGQuickActions.actions.register(WGQuickAction(
            id: WGQuickActionIds.translateBeforeSend,
            order: 600,
            title: { WGStrings.Translation.Menu.beforeSending },
            iconName: "Chat/Context Menu/Translate",
            isOn: { _ in
                return WGMessagesSettings.translateBeforeSending.value
            },
            perform: { _ in
                WGMessagesSettings.translateBeforeSending.set(!WGMessagesSettings.translateBeforeSending.value)
            }
        ))
    }
}
