// The attributed text of a text bubble after entities are applied and before layout (color
// swatches after hex colors…). Call site: ChatMessageTextBubbleContentNode, for every layout of a
// text bubble: handlers cache their own work per message version.

import Foundation
import UIKit
import Postbox
import TelegramCore
import AccountContext
import WGCore

public struct WGMessageTextContext {
    public let message: Message
    public let context: AccountContext
}

public enum WGMessageTextHooks {
    /// Transformer of the attributed text of a text bubble. Return the same object when nothing applies.
    public static let attributedText = WGHookPoint<(NSAttributedString, WGMessageTextContext) -> NSAttributedString>("messageText.attributedText")

    public static func attributedText(_ text: NSAttributedString, message: Message, context: AccountContext) -> NSAttributedString {
        if WGMessageTextHooks.attributedText.isEmpty {
            return text
        }
        let textContext = WGMessageTextContext(message: message, context: context)
        var result = text
        for handler in WGMessageTextHooks.attributedText.handlers {
            result = handler(result, textContext)
        }
        return result
    }
}
