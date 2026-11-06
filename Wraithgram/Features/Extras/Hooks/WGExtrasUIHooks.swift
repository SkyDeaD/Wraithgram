// swift_library WGExtrasHooks: UI points of the Swiftgram-parity features (W5-SG) that need
// AccountContext. Below every module that calls them (the chat selection panel, TelegramUI): only
// WGCore, TelegramCore, AccountContext, Display. Handlers are registered by WGExtras. An empty
// point = upstream.

import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import WGCore

/// A button WGExtras puts on the chat's selection panel.
public enum WGExtrasSelectionAction {
    /// Forward the selected messages to «Избранное» without opening it.
    case saveToCloud
    /// Pick a chat and forward the selected messages there without the author's name.
    case forwardWithoutAuthor
}

/// A long-pressed link in a chat: what WGExtras may add to its menu.
public struct WGExtrasLinkContext {
    public let context: AccountContext
    public let url: String
    /// Presents a controller over the chat (`in: .window(.root)`).
    public let present: (ViewController) -> Void

    public init(context: AccountContext, url: String, present: @escaping (ViewController) -> Void) {
        self.context = context
        self.url = url
        self.present = present
    }
}

/// One extra action of a link menu, drawn by the call site as a context menu item or an action sheet
/// button (both menus exist upstream).
public struct WGExtrasLinkAction {
    public let title: String
    /// Bundle image name of the context menu icon.
    public let iconName: String
    public let action: () -> Void

    public init(title: String, iconName: String, action: @escaping () -> Void) {
        self.title = title
        self.iconName = iconName
        self.action = action
    }
}

public enum WGExtrasUIHooks {
    /// Policy: perform a selection-panel action for these messages (main thread). `true` = handled.
    public static let selectionAction = WGHookPoint<(WGExtrasSelectionAction, AccountContext, [EngineMessage.Id]) -> Bool>("extras.selectionAction")

    /// Providers of extra actions for a long-pressed link (main thread).
    public static let linkActions = WGHookPoint<(WGExtrasLinkContext) -> [WGExtrasLinkAction]>("extras.linkActions")

    /// Policy: open an external link inside the app (SFSafariViewController) instead of Safari.
    /// `true` = handled. Main thread.
    public static let openInAppBrowser = WGHookPoint<(URL, AccountContext, NavigationController?) -> Bool>("extras.openInAppBrowser")

    /// WRAITH hook target: ChatMessageSelectionInputPanelNode.
    public static func performSelectionAction(_ action: WGExtrasSelectionAction, context: AccountContext, messageIds: [EngineMessage.Id]) {
        for handler in WGExtrasUIHooks.selectionAction.handlers {
            if handler(action, context, messageIds) {
                return
            }
        }
    }

    /// WRAITH hook target: ChatControllerOpenLinkContextMenu. Empty without handlers.
    public static func actions(forLink context: @autoclosure () -> WGExtrasLinkContext) -> [WGExtrasLinkAction] {
        if WGExtrasUIHooks.linkActions.isEmpty {
            return []
        }
        let value = context()
        var result: [WGExtrasLinkAction] = []
        for handler in WGExtrasUIHooks.linkActions.handlers {
            result.append(contentsOf: handler(value))
        }
        return result
    }

    /// WRAITH hook target: OpenUrl, before the link leaves for an external browser.
    public static func handledInAppBrowser(_ url: URL, context: AccountContext, navigationController: NavigationController?) -> Bool {
        for handler in WGExtrasUIHooks.openInAppBrowser.handlers {
            if handler(url, context, navigationController) {
                return true
            }
        }
        return false
    }
}
