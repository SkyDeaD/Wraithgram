import Foundation
import WGCore
import WGHooks
import WGFeaturesShared

/// Entry point of the WGMessages feature module (W2-3): restriction bypasses, the outgoing text
/// pipeline, translation, the message menu and gestures, the «Чаты» and «Уведомления» sections.
public enum WGMessagesModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `WGFeatures.registerAll()`, before `WGHookRegistry.freeze()`.
    public static func register() {
        // Settings shared with upstream modules and the extensions are declared by
        // WGMessagesShared.register() (called before this one by WGFeaturesShared.registerForApp()).
        let _ = WGOutgoingPipeline.replacementRules

        WGRestrictionHandlers.register()
        WGKeptMediaMenu.register()
        WGMessageDecorations.register()
        WGOutgoingPipeline.register()
        WGOutgoingTransforms.register()
        WGTranslationProviders.register()
        WGTranslateBeforeSending.register()
        WGPhotoTranslation.register()
        WGTranslationMenu.register()
        WGTranslationQuickAction.register()
        WGMessageMenuCustomization.register()
        WGInputAndGestures.register()
        WGAutoQuote.register()
        WGOutgoingLanguageMenu.register()
        WGChatsHandlers.register()
        WGPinnedChats.register()
        WGLocalCreatorMode.register()

        WGMessagesMenu.register()
        WGMessagesMigrations.register()

        // Placeholders of dropped pushes the notification extension did not live to remove
        // (WGEmptyNotifications); one async query, nothing when there are none.
        WGLifecycleHooks.applicationDidBecomeActive.register({
            WGEmptyNotifications.removeDelivered()
        })
    }
}
