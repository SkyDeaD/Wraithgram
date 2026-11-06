import Foundation
import SwiftSignalKit
import GGCore

/// Entry point of the GGProfileExport feature module (W4-1): fake gifts, chat export.
public enum GGProfileExportModule {
    private static var fakeGiftsDisposable: Disposable?

    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `GGFeatures.registerAll()`, before `GGHookRegistry.freeze()`.
    public static func register() {
        assert(Thread.isMainThread)
        GGFakeGiftsSettings.declare()
        GGLocalStars.declare()
        GGChatExportSettings.declare()
        GGFakeGiftsLegacy.registerMigrations()

        // The nick badges were removed: their switch and their cached table and pictures go once.
        GGMigrations.registerGlobal(id: "nickBadge.removed.v1") { _ in
            GGRetiredSettings.remove(keys: ["nickBadge.isEnabled"])
            if let cache = GGProfileExportPaths.cachesDirectory("nickBadge") {
                DispatchQueue.global(qos: .utility).async {
                    try? FileManager.default.removeItem(at: cache)
                }
            }
        }

        // Fake gifts: the profile's list, the gift screen's menu, the store per account.
        GGFakeGiftsHooks.register()
        GGFakeGiftsMenu.register()
        GGProfileExportModule.fakeGiftsDisposable = (GGFakeGiftsSettings.isEnabled.signal
        |> distinctUntilChanged).start(next: { enabled in
            GGFakeGiftsStore.shared.setEnabled(enabled)
        })
        // Local stars: the Stars balance shown on this device (same tab, own section).
        GGLocalStars.register()

        // Chat export: entry points; temporary trees of old jobs are removed off the main thread.
        GGChatExportMenu.register()
        GGChatExportManager.shared.removeStaleJobs()
    }
}
