import Foundation
import Postbox
import TelegramCore
import WGCore

/// The part of WGAntiDelete that the extensions (notification service, share) also link: settings with
/// `.extensions`, NSE handlers, attribute declarations. Owner: W2-2.
public enum WGAntiDeleteShared {
    /// Called from `WGFeaturesShared.registerForApp()` and `.registerForExtension()`; check
    /// `WGCore.environment?.process` for what only one of them needs.
    public static func register() {
        WGAntiDeleteSettings.declare()

        // Attributes: before any Postbox opens, in every process that decodes messages.
        WGMessageAttributeHooks.declareEncodables.register({
            wgDeclareAntiDeleteAttributes()
        })

        // Capture, the same in the app and in the notification service (which marks the shared
        // Postbox itself and hands the index entries to the app).
        WGUpdateHooks.messagesWillBeDeleted.register({ request in
            return WGAntiDeleteCapture.messagesWillBeDeleted(request)
        })
        WGUpdateHooks.historyWillBeCleared.register({ request in
            return WGAntiDeleteCapture.historyWillBeCleared(request)
        })
        WGUpdateHooks.messageWillBeEdited.register({ request, attributes in
            return WGAntiDeleteCapture.messageWillBeEdited(request, attributes)
        })
        // A message stored again from the server (holes, validation) keeps its local attributes.
        WGMessageAttributeHooks.mergeAttributes.register({ previous, updated in
            WGAntiDeleteCapture.carryOverLocalAttributes(from: previous, into: &updated)
        })

        let isApp = WGCore.environment?.process.isApp ?? true
        if isApp {
            WGAccountHooks.accountWillStart.register({ context in
                WGAntiDeleteAccounts.shared.accountDidStart(context)
                if !context.isSupplementary {
                    WGAntiDeleteLegacyImport.importIfNeeded(accountId: context.id, postbox: context.postbox)
                }
            })
            WGAccountHooks.accountWillBeRemoved.register({ id in
                WGAntiDeleteAccounts.shared.accountWillBeRemoved(id)
            })
        }
    }
}
