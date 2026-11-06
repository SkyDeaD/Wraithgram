// App lifecycle for features that must react immediately (chat lock on leaving the app,
// overlays). Background work on return goes through `WGForegroundTaskScheduler` (WGCore), which
// throttles it — do not use `applicationDidBecomeActive` for network or disk work.

import Foundation
import UIKit
import Display
import AccountContext
import WGCore

public enum WGLifecycleHooks {
    /// Observers on the main thread.
    public static let applicationDidBecomeActive = WGHookPoint<() -> Void>("lifecycle.didBecomeActive")
    public static let applicationWillResignActive = WGHookPoint<() -> Void>("lifecycle.willResignActive")
    public static let applicationDidEnterBackground = WGHookPoint<() -> Void>("lifecycle.didEnterBackground")

    /// Observer: an account's root controllers (tab bar) were built — the place to start a
    /// feature's per-account UI machinery. Main thread.
    public static let rootControllersDidLoad = WGHookPoint<(AccountContext, NavigationController) -> Void>("lifecycle.rootControllersDidLoad")

    /// Policy: handle an opened URL (`wraithgram://`, `wg://`, or any other) before Telegram does.
    /// `true` = handled. Main thread.
    public static let openURL = WGHookPoint<(URL, AccountContext, NavigationController) -> Bool>("lifecycle.openURL")

    public static func handleURL(_ url: URL, context: AccountContext, navigationController: NavigationController) -> Bool {
        for handler in WGLifecycleHooks.openURL.handlers {
            if handler(url, context, navigationController) {
                return true
            }
        }
        return false
    }

    public static func notifyDidBecomeActive() {
        for handler in WGLifecycleHooks.applicationDidBecomeActive.handlers {
            handler()
        }
    }

    public static func notifyWillResignActive() {
        for handler in WGLifecycleHooks.applicationWillResignActive.handlers {
            handler()
        }
    }

    public static func notifyDidEnterBackground() {
        for handler in WGLifecycleHooks.applicationDidEnterBackground.handlers {
            handler()
        }
    }

    public static func notifyRootControllersDidLoad(context: AccountContext, navigationController: NavigationController) {
        for handler in WGLifecycleHooks.rootControllersDidLoad.handlers {
            handler(context, navigationController)
        }
    }
}

/// Order, visibility and extra tabs of the main tab bar. Height, labels and width are W2-5's
/// own edits in TabBarUI (not a frozen module).
public struct WGRootTabContext {
    public let context: AccountContext
    /// Telegram's controllers, for identification (`===`).
    public let contacts: ViewController
    public let calls: ViewController?
    public let chatList: ViewController
    public let settings: ViewController

    public init(context: AccountContext, contacts: ViewController, calls: ViewController?, chatList: ViewController, settings: ViewController) {
        self.context = context
        self.contacts = contacts
        self.calls = calls
        self.chatList = chatList
        self.settings = settings
    }
}

public enum WGRootHooks {
    /// Transformer of the tab controllers before they are set (reorder, hide, append).
    /// Keep the chat list: the app expects it.
    public static let tabControllers = WGHookPoint<(inout [ViewController], WGRootTabContext) -> Void>("root.tabControllers")

    public static func arrangeTabs(_ controllers: [ViewController], context: WGRootTabContext) -> [ViewController] {
        if WGRootHooks.tabControllers.isEmpty {
            return controllers
        }
        var result = controllers
        for handler in WGRootHooks.tabControllers.handlers {
            handler(&result, context)
        }
        if !result.contains(where: { $0 === context.chatList }) {
            assertionFailure("WGRootHooks.tabControllers removed the chat list")
            return controllers
        }
        return result
    }

    /// The index to select after `arrangeTabs`: where `preferred` ended up, or `fallback`.
    public static func selectedIndex(_ controllers: [ViewController], preferred: ViewController, fallback: Int) -> Int {
        if WGRootHooks.tabControllers.isEmpty {
            return fallback
        }
        return controllers.firstIndex(where: { $0 === preferred }) ?? fallback
    }
}
