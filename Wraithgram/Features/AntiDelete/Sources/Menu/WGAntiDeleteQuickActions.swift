import Foundation
import Display
import AccountContext
import WGCore
import WGFeaturesShared

/// The zone's buttons of «Кнопки быстрого доступа» in a chat (W2-5's `WGQuickActions`): the deleted
/// and the edited messages of this chat, the same screens as the profile's «…» menu opens.
enum WGAntiDeleteQuickActions {
    static func register() {
        WGQuickActions.actions.register(WGQuickAction(
            id: WGQuickActionIds.deletedMessages,
            order: 200,
            title: { WGStrings.AntiDelete.QuickActions.deleted },
            iconName: "Chat/Context Menu/Delete",
            perform: { context in
                WGAntiDeleteQuickActions.open(.deleted, context: context)
            }
        ))
        WGQuickActions.actions.register(WGQuickAction(
            id: WGQuickActionIds.editedMessages,
            order: 300,
            title: { WGStrings.AntiDelete.QuickActions.edited },
            iconName: "Chat/Context Menu/Edit",
            perform: { context in
                WGAntiDeleteQuickActions.open(.edited, context: context)
            }
        ))
    }

    private static func open(_ kind: WGAntiDeleteLogKind, context: WGQuickActionContext) {
        guard let accountContext = context.accountContext as? AccountContext else {
            return
        }
        let screen = wgMakeAntiDeleteChatHistoryController(context: accountContext, kind: kind, peerId: context.peerId)
        if let navigationController = (context.chatController as? ViewController)?.navigationController as? NavigationController {
            navigationController.pushViewController(screen)
        } else {
            WGAntiDeleteMessageMenu.rootNavigationController(accountContext)?.pushViewController(screen)
        }
    }
}
