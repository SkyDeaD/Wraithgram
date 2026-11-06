// Compiled into TelegramCore (filegroup //Wraithgram/WGHooks:TelegramCoreHookSources).
// Features declare their own Postbox-coded types (message attributes: deleted, versions,
// local edit, bookmark, previous reactions…) in the same place TelegramCore declares its own,
// before any Postbox opens — in the app and in every extension.

import Foundation
import Postbox
import WGCore

public enum WGMessageAttributeHooks {
    /// Observer, called once per process from TelegramCore's `declaredEncodables`
    /// (`initializeAccountManagement()`), on the thread that initializes account management.
    /// Handlers call `declareEncodable(MyAttribute.self, f: { MyAttribute(decoder: $0) })`.
    /// Register from `WG<Zone>Shared.register()` so extensions decode the attributes too.
    public static let declareEncodables = WGHookPoint<() -> Void>("attributes.declareEncodables")

    /// Transformer: when the server stores a message again over an existing one (holes, history
    /// validation, `storeMessages`), Postbox merges the stored version's local attributes into the
    /// new one (`SeedConfiguration.mergeMessageAttributes`). Handlers copy their own local
    /// attributes from `previous` into `updated` (deleted, versions, local edit, bookmark…).
    /// Called inside the Postbox transaction for every such message: one cheap pass, no I/O.
    public static let mergeAttributes = WGHookPoint<([MessageAttribute], inout [MessageAttribute]) -> Void>("attributes.merge")
}

func wgDeclareFeatureEncodables() {
    for handler in WGMessageAttributeHooks.declareEncodables.handlers {
        handler()
    }
}

/// WRAITH hook target: `telegramPostboxSeedConfiguration.mergeMessageAttributes`.
func wgMergeFeatureAttributes(_ previous: [MessageAttribute], _ updated: inout [MessageAttribute]) {
    if WGMessageAttributeHooks.mergeAttributes.isEmpty || previous.isEmpty {
        return
    }
    for handler in WGMessageAttributeHooks.mergeAttributes.handlers {
        handler(previous, &updated)
    }
}
