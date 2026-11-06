import Foundation
import UIKit
import Display
import TelegramPresentationData
import AccountContext
import WGCore
import WGHooks

/// Entry point of the module. `WGFeatures.registerAll()` calls `register()` first, before any
/// feature registers its rows (FOUNDATION_SPEC §2, §5.4).
public enum WGSettingsUI {
    private static var isRegistered = false

    public static func register() {
        assert(Thread.isMainThread)
        if self.isRegistered {
            return
        }
        self.isRegistered = true

        // The «Wraithgram» row in Telegram's Settings: a section of its own right after «My Profile»
        // (owner, 2026-10-28), the standard 30 pt tile.
        WGSettingsTabHooks.rows.register(WGSettingsTabRow(
            id: "wraithgram.menu",
            placement: .ownSectionAfterMyProfile,
            order: 0,
            icon: { _ in
                return wgSettingsTileIcon()
            },
            title: {
                return WGStrings.Menu.title
            },
            action: { context, navigationController in
                navigationController?.pushViewController(wgMakeSettingsController(context: context))
            }
        ), order: 0)

        wgRegisterMenuSkeleton()
        wgRegisterBuiltInRows()
        wgRegisterLicensesTab()
    }

    /// Categories and tabs without rows are hidden, so nothing dead is ever reachable. The demo
    /// registration (`Demo/`) turns this on to show the whole skeleton before the features exist.
    public static var showsEmptyScreens: Bool {
        get {
            return WGMenuStorage.shared.showsEmptyTabs
        }
        set {
            WGMenuStorage.shared.showsEmptyTabs = newValue
        }
    }
}

/// Screens that live above this module in the dependency graph. Filled at launch from TelegramUI
/// (W1-2 / orchestrator, see USAGE.md). A `nil` closure hides the row that needs it.
public final class WGSettingsUIEnvironment {
    public static let shared = WGSettingsUIEnvironment()

    /// Telegram's own language screen (`SettingsUI.LocalizationListController`), linked from
    /// «Настройки Wraithgram › Язык»: Wraithgram's language follows Telegram's by default.
    public var makeTelegramLanguageController: ((AccountContext) -> ViewController)?

    private init() {
    }
}
