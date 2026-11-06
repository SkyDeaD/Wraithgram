import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import AccountContext
import UIKitRuntimeUtils
import WGCore
import WGHooks
import WGFeaturesShared

/// «Скрывать чат на скриншотах»: one setting (`security.screenshotPrivacy`), one point that applies
/// it (`WGChatScreenHooks.hidesChromeFromCapture` → header, input panel, the panels over it,
/// navigation buttons, quick buttons come out empty on screenshots and screen recordings; the
/// messages stay; no send animation). The menu row and the chat's quick button write the same
/// setting — the button no longer flips any master switch. «И список чатов» does the same for the
/// whole chat list screen (rows, header, folder tabs).
enum WGScreenshotPrivacy {
    private static var chatListKey: UInt8 = 0

    static func register() {
        WGChatScreenHooks.hidesChromeFromCapture.register({ _, _ in
            return WGSecuritySettings.screenshotPrivacy.value
        })
        WGQuickActions.actions.register(WGQuickAction(
            id: WGQuickActionIds.screenshotPrivacy,
            order: 700,
            title: { WGStrings.Security.Screenshot.quickAction },
            iconName: "Chat/Context Menu/Lock",
            isOn: { _ in
                return WGSecuritySettings.screenshotPrivacy.value
            },
            perform: { context in
                WGSecuritySettings.screenshotPrivacy.set(!WGSecuritySettings.screenshotPrivacy.value)
                // The chat applies it on its next layout: ask for one now.
                (context.chatController as? ViewController)?.requestLayout(transition: .immediate)
            }
        ))
        WGChatListChromeHooks.containerDidLayout.register({ layout in
            let hides = WGSecuritySettings.screenshotPrivacy.value && WGSecuritySettings.screenshotPrivacyChatList.value
            let node = layout.node
            let applied = (objc_getAssociatedObject(node, &WGScreenshotPrivacy.chatListKey) as? NSNumber)?.boolValue ?? false
            if hides == applied {
                return
            }
            objc_setAssociatedObject(node, &WGScreenshotPrivacy.chatListKey, NSNumber(value: hides), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            setLayerDisableScreenshots(node.layer, hides)
        })
    }
}
