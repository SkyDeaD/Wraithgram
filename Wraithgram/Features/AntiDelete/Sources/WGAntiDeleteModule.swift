import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import WGCore
import WGHooks
import WGSettingsUI
import WGFeaturesShared
import ChatListUI

/// Entry point of the WGAntiDelete feature module. Owner: W2-2.
/// The capture itself (Postbox attributes, the index, the notification service) is registered by
/// `WGAntiDeleteShared` (WGFeaturesShared); this module adds the menu, the chat UI and the
/// background maintenance of the app.
public enum WGAntiDeleteModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `WGFeatures.registerAll()`, before `WGHookRegistry.freeze()`.
    public static func register() {
        WGAntiDeleteMenu.register()
        WGAntiDeleteMigrations.register()
        WGAntiDeleteQuickActions.register()

        // Bubbles of every type: transparency, status marks, the local edit, previous versions.
        WGMessageDecorationHooks.decorations.register({ decoration, context in
            WGAntiDeleteDecorations.decorate(&decoration, context)
        }, order: 100)

        // Message menu.
        WGMessageMenuHooks.items.register({ context in
            return WGAntiDeleteMessageMenu.items(context)
        })
        WGMessageMenuHooks.filter.register({ items, context in
            return WGAntiDeleteMessageMenu.filter(items, context)
        }, order: 100)

        // Profile «…».
        WGPeerInfoHooks.menuItems.register({ context in
            return WGAntiDeletePeerMenu.items(context)
        })

        // Chat list preview with the local edit; late, so a locked chat's hidden preview wins.
        WGChatListHooks.previewText.register({ row in
            return WGAntiDeleteChatList.previewText(row)
        }, order: 1000)

        // Reply to a deleted message → a quote, before the other outgoing transformers.
        WGOutgoingHooks.messages.register({ messages, context in
            WGAntiDeleteReplyQuote.transform(&messages, context: context)
        }, order: -100)
        WGChatScreenHooks.replySubject.register({ subject, request in
            WGAntiDeleteReplyQuote.warmUp(request)
            return subject
        })

        // A chat opens: archived media of its kept messages go back into the cache if it lost them.
        WGChatScreenHooks.lifecycle.register({ event, screen in
            guard case .willAppear = event, !screen.isPreview, let peerId = screen.chatLocation.peerId else {
                return
            }
            let context = screen.context
            if WGAntiDeleteAccounts.shared.count(account: context.account.id, kind: .deleted, peerId: peerId) == 0 {
                return
            }
            guard let basePath = WGAntiDeleteAccounts.shared.basePath(for: context.account.id) else {
                return
            }
            WGAntiDeleteMediaArchive.restore(postbox: context.account.postbox, basePath: basePath, peerId: peerId, completion: { restored in
                if !restored.isEmpty {
                    Queue.mainQueue().async {
                        WGMessageDecorationHooks.redraw(messageIds: restored)
                    }
                }
            })
        })

        // Excluded folders follow folder changes of every running account.
        WGLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            WGAntiDeleteFolderSync.start(sharedContext: context.sharedContext)
            WGAntiDeleteModule.sharedContext = context.sharedContext
        })

        // Background work only on return to the app, throttled (WGCore scheduler).
        WGForegroundTaskScheduler.shared.register(id: "antiDelete.inbox", minimumInterval: 60.0, delay: 1.0, task: { done in
            WGAntiDeleteIndexQueue.shared.drainInbox(completion: {
                Queue.mainQueue().async {
                    done()
                }
            })
            return EmptyDisposable
        })
        WGForegroundTaskScheduler.shared.register(id: "antiDelete.autoClear", minimumInterval: 6.0 * 60.0 * 60.0, delay: 8.0, task: { done in
            return (WGAntiDeleteOperations.pruneAllAccounts()
            |> deliverOnMainQueue).start(completed: {
                done()
            })
        })
        WGForegroundTaskScheduler.shared.register(id: "antiDelete.folders", minimumInterval: 15.0 * 60.0, delay: 5.0, task: { done in
            guard let sharedContext = WGAntiDeleteModule.sharedContext else {
                done()
                return EmptyDisposable
            }
            return (WGAntiDeleteFolderSync.refreshAll(sharedContext: sharedContext)
            |> deliverOnMainQueue).start(completed: {
                done()
            })
        })
    }

    /// Set when the first account's UI is up (main thread); used by the foreground refresh.
    fileprivate static weak var sharedContext: SharedAccountContext?
}
