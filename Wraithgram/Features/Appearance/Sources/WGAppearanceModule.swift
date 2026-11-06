import Foundation
import WGAppearanceSettings

/// Entry point of the WGAppearance feature module (owner W2-4): appearance of messages, theme and
/// backgrounds, the profile's info rows and header.
///
/// One snapshot (`WGAppearanceSnapshot`) carries everything that changes the theme or the layout of
/// messages; it rebuilds the theme once per change (WGThemeHooks.invalidate). Decorations that need
/// no relayout (animated backgrounds, snowfall, screen-edge bands) follow their own settings' signals.
public enum WGAppearanceModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `WGFeatures.registerAll()`, before `WGHookRegistry.freeze()`.
    public static func register() {
        assert(Thread.isMainThread)
        WGAppearanceSettings.declare()
        WGAppearanceMigration.register()

        WGFonts.register()
        WGCustomFonts.registerProvider()
        WGAppearanceTheme.register()
        WGAmoledKeyboard.register()
        WGChatMessages.register()
        WGChatDecor.register()
        WGChatListDecor.register()
        WGProfileDecor.register()
        WGAppearancePendingPoints.register()

        WGAppearanceMenu.register()
    }
}
