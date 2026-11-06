// Message layout: size and time of stickers, the text inset inside bubbles, full-width bubbles.
// Call sites: ChatMessageStickerItemNode / ChatMessageAnimatedStickerItemNode (sticker),
// chatMessageItemLayoutConstants in ChatMessageItemView (text inset), ChatMessageBubbleItemNode
// (full width). All of them run on the layout path for every message: answer from snapshots.

import Foundation
import UIKit
import Postbox
import TelegramCore
import AccountContext
import WGCore

public struct WGStickerLayout: Equatable {
    /// Multiplier of the sticker's display size (1 = upstream, below 1 smaller, above 1 bigger).
    public var scale: CGFloat
    /// The time / status under the sticker (true = upstream).
    public var showsTime: Bool

    public init(scale: CGFloat, showsTime: Bool) {
        self.scale = scale
        self.showsTime = showsTime
    }

    public static let upstream = WGStickerLayout(scale: 1.0, showsTime: true)

    /// `size` with `scale` applied. A bigger sticker never grows past `maxWidth` (the call site
    /// passes the chat's width minus the avatar, the bubble edges and the share button), so even
    /// at the largest setting it stays on screen.
    public func scaledSize(_ size: CGSize, maxWidth: CGFloat) -> CGSize {
        if self.scale == 1.0 {
            return size
        }
        var result = CGSize(width: floor(size.width * self.scale), height: floor(size.height * self.scale))
        if self.scale > 1.0 && result.width > maxWidth {
            let width = max(size.width, maxWidth)
            result = CGSize(width: floor(width), height: floor(result.height * width / result.width))
        }
        return result
    }
}

public enum WGMessageLayoutHooks {
    /// Transformer: size and time of a sticker / animated sticker / dice message.
    public static let sticker = WGHookPoint<(inout WGStickerLayout, Message, AccountContext) -> Void>("messageLayout.sticker")

    /// Policy (first non-nil wins): the horizontal text inset inside bubbles; nil = upstream.
    /// Asked by `chatMessageItemLayoutConstants`, i.e. for every bubble layout.
    public static let bubbleTextInset = WGHookPoint<(CGFloat) -> CGFloat?>("messageLayout.bubbleTextInset")

    /// Policy (any `true`): the bubble takes the full width and has no side share button.
    public static let fullWidthBubble = WGHookPoint<(Message, AccountContext) -> Bool>("messageLayout.fullWidthBubble")

    /// True when a feature changes stickers (call sites leave the sticker's status alone otherwise).
    public static var adjustsStickers: Bool {
        return !WGMessageLayoutHooks.sticker.isEmpty
    }

    public static func stickerLayout(message: Message, context: AccountContext) -> WGStickerLayout {
        if WGMessageLayoutHooks.sticker.isEmpty {
            return .upstream
        }
        var result = WGStickerLayout.upstream
        for handler in WGMessageLayoutHooks.sticker.handlers {
            handler(&result, message, context)
        }
        result.scale = min(3.0, max(0.1, result.scale))
        return result
    }

    public static func bubbleTextInset(_ upstream: CGFloat) -> CGFloat {
        if WGMessageLayoutHooks.bubbleTextInset.isEmpty {
            return upstream
        }
        for handler in WGMessageLayoutHooks.bubbleTextInset.handlers {
            if let value = handler(upstream) {
                return max(0.0, value)
            }
        }
        return upstream
    }

    public static func isFullWidthBubble(_ message: Message, context: AccountContext) -> Bool {
        if WGMessageLayoutHooks.fullWidthBubble.isEmpty {
            return false
        }
        for handler in WGMessageLayoutHooks.fullWidthBubble.handlers {
            if handler(message, context) {
                return true
            }
        }
        return false
    }
}
