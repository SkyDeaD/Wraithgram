// The chat list screen's chrome: its container node after layout (search field, folder panel,
// Android-style buttons) and the navigation bar component after layout (gradient, snow, folder
// tabs placement). Here, not in ChatListUI, because ChatListNavigationBar lives in
// ChatListHeaderComponent, below ChatListUI. Row-level points: `WGChatListHooks` (ChatListUI).

import Foundation
import UIKit
import AsyncDisplayKit
import Display
import AccountContext
import WGCore

public struct WGChatListContainerLayout {
    public let context: AccountContext
    /// ChatListControllerNode.
    public let node: ASDisplayNode
    public let layout: ContainerViewLayout
    public let navigationBarHeight: CGFloat
    public let transition: ContainedViewLayoutTransition
    /// Height Wraithgram's own bottom chrome takes above `layout.intrinsicInsets.bottom` (the
    /// «Папки внизу» strip with its gaps); 0 = none. Floating buttons go above it.
    public let bottomAccessoryHeight: CGFloat
    /// The list itself (the container of the chat list pages), a subview of `node.view`. Decorations
    /// of the list's content belong right above it — under the folder strip, search and the rest.
    public let contentView: UIView?
}

public struct WGChatListNavigationBarLayout {
    /// ChatListNavigationBar.View.
    public let view: UIView
    public let size: CGSize
    public let isAnimated: Bool
}

public enum WGChatListChromeHooks {
    /// Observer after the chat list container's layout (main thread).
    public static let containerDidLayout = WGHookPoint<(WGChatListContainerLayout) -> Void>("chatListChrome.containerDidLayout")

    /// Observer after the chat list navigation bar's layout (main thread, scroll path).
    public static let navigationBarDidLayout = WGHookPoint<(WGChatListNavigationBarLayout) -> Void>("chatListChrome.navigationBarDidLayout")

    /// Policy: `false` turns off "swipe right to record a story" on the chat list.
    public static let storyCameraSwipe = WGHookPoint<(AccountContext) -> Bool?>("chatListChrome.storyCameraSwipe")

    public static func notifyContainerDidLayout(context: AccountContext, node: ASDisplayNode, layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition, bottomAccessoryHeight: CGFloat = 0.0, contentView: UIView? = nil) {
        if WGChatListChromeHooks.containerDidLayout.isEmpty {
            return
        }
        let value = WGChatListContainerLayout(context: context, node: node, layout: layout, navigationBarHeight: navigationBarHeight, transition: transition, bottomAccessoryHeight: bottomAccessoryHeight, contentView: contentView)
        for handler in WGChatListChromeHooks.containerDidLayout.handlers {
            handler(value)
        }
    }

    public static func notifyNavigationBarDidLayout(view: UIView, size: CGSize, isAnimated: Bool) {
        if WGChatListChromeHooks.navigationBarDidLayout.isEmpty {
            return
        }
        let value = WGChatListNavigationBarLayout(view: view, size: size, isAnimated: isAnimated)
        for handler in WGChatListChromeHooks.navigationBarDidLayout.handlers {
            handler(value)
        }
    }

    public static func allowsStoryCameraSwipe(context: AccountContext) -> Bool {
        for handler in WGChatListChromeHooks.storyCameraSwipe.handlers {
            if let value = handler(context) {
                return value
            }
        }
        return true
    }
}
