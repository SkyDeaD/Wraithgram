import Foundation
import SwiftSignalKit
import TelegramCore
import WGCore
import WGFeaturesShared

/// Entry point of the WGGhostMode feature module. Owner: W2-1.
///
/// The decisions about what leaves the device live in `WGFeaturesShared` (`WGGhostModeShared`,
/// registered by the aggregator for the app and the extensions alike). This module is the app's
/// side: the menu, the chat-screen tracking, the explicit reads and the menu items.
public enum WGGhostModeModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `WGFeatures.registerAll()`, before `WGHookRegistry.freeze()`.
    public static func register() {
        WGGhostMigrations.register()
        WGGhostMenu.register()
        WGGhostMenuItems.register()
        WGGhostChatTracking.register()
        WGGhostBlockedPeers.register()
        WGGhostTraces.register()
        WGGhostQuickActions.register()

        WGAccountHooks.accountWillBeRemoved.register({ id in
            let account = id.wg
            Queue.mainQueue().async {
                WGGhostAccounts.shared.accountWillBeRemoved(account)
                WGGhostBlockedPeers.shared.clear(account: account)
            }
        }, order: 100)

        // Throttled work on return to the app (never on every activation, never in the background):
        // the blocked lists of the accounts that hide them, and «Прочитать локально» re-applied
        // after a server reset of the read state.
        WGForegroundTaskScheduler.shared.register(id: "ghostMode.refresh", minimumInterval: 30.0 * 60.0, delay: 4.0, task: { done in
            let contexts = WGGhostAccounts.shared.contexts
            var signals: [Signal<Never, NoError>] = []
            for context in contexts {
                let account = context.account.id.wg
                if WGGhostSettings.hideBlockedMessages.value(for: account) {
                    // The current list stays in use until the new one is complete.
                    WGGhostBlockedPeers.shared.reload(context: context)
                }
                signals.append(WGGhostAccounts.reapplyLocalReads(context: context))
            }
            if signals.isEmpty {
                done()
                return EmptyDisposable
            }
            return combineLatest(signals).start(completed: {
                done()
            })
        })
    }
}
