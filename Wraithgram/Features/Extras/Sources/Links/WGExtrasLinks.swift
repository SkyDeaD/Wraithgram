import Foundation
import UIKit
import SafariServices
import Display
import TelegramCore
import AccountContext
import WGCore
import WGFeaturesShared
import WGExtrasHooks

/// Links: «Переслать» / «Поделиться» in the menu of a long-pressed link, and «Safari в приложении»
/// as a browser (Telegram's «Браузер» settings list it while «Больше браузеров» is on).
enum WGExtrasLinks {
    static func register() {
        WGExtrasUIHooks.linkActions.register({ link in
            if !WGExtrasSettings.linkMenuShare.value {
                return []
            }
            // Web and Telegram links only: an e-mail address or a phone number is not «shared» as a link.
            let lowercasedUrl = link.url.lowercased()
            if lowercasedUrl.hasPrefix("mailto:") || lowercasedUrl.hasPrefix("tel:") {
                return []
            }
            let context = link.context
            let url = link.url
            let present = link.present
            return [
                WGExtrasLinkAction(title: WGStrings.Extras.Link.forward, iconName: "Chat/Context Menu/Forward", action: {
                    present(context.sharedContext.makeShareController(context: context, params: ShareControllerParams(subject: .url(url))))
                }),
                WGExtrasLinkAction(title: WGStrings.Extras.Link.share, iconName: "Chat/Context Menu/Share", action: {
                    present(context.sharedContext.makeShareController(context: context, params: ShareControllerParams(subject: .url(url), externalShare: true, immediateExternalShare: true)))
                })
            ]
        })

        WGExtrasUIHooks.openInAppBrowser.register({ url, context, _ in
            if !WGExtrasPolicy.allowsMoreBrowsers {
                return false
            }
            // SFSafariViewController takes http(s) only (anything else is an exception).
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return false
            }
            // No bar tint: deprecated since iOS 26, where the system draws the bars itself.
            // `presentNativeController` presents over whatever is on top (a sheet included).
            context.sharedContext.applicationBindings.presentNativeController(SFSafariViewController(url: url))
            return true
        })
    }
}
