// Compiled into ChatMessageBubbleItemNode (filegroup //Wraithgram/WGHooks:ChatMessageBubbleItemNodeHookSources):
// call-site helpers of the bubble that need the chat item types (ChatMessageItem,
// ChatControllerInteraction): multi-tap gestures (WGMessageGestureHooks), the quick translate
// button beside the bubble (WGMessageDecorationHooks.translateButtonLanguage). No feature logic.

import Foundation
import UIKit
import ObjectiveC
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import AppBundle
import TextSelectionNode
import ChatControllerInteraction
import ChatMessageItem
import ChatMessageItemView
import WGHooks

// MARK: - Taps

/// The triple-tap branch: `true` = a feature handled it.
func wgBubbleHandleTap(_ item: ChatMessageItem, message: Message, tapCount: Int) -> Bool {
    if !wgBubbleIsInteractive(item) {
        return false
    }
    return WGMessageGestureHooks.handleTap(message: message, context: item.context, tapCount: tapCount, chatNode: item.controllerInteraction.chatControllerNode())
}

/// WRAITH hook target: the double-tap branches of the bubble's tap recognizer. `true` = handled, the
/// bubble does nothing else now. `upstream` is the bubble's own double-tap action (the quick
/// reaction or the message menu). While a feature acts on triple taps on this message, the double
/// tap — the features' and `upstream` — is held back until the bubble's triple-tap recognizer failed,
/// and dropped when it recognized: the second tap of a triple tap must not send a reaction.
func wgBubbleHandleDoubleTap(_ node: ChatMessageItemView, item: ChatMessageItem, message: Message, upstream: @escaping () -> Void) -> Bool {
    if !wgBubbleIsInteractive(item) {
        return false
    }
    let context = item.context
    if WGMessageGestureHooks.isTripleTapWanted(message: message) {
        weak let chatNode = item.controllerInteraction.chatControllerNode()
        let stableId = item.message.stableId
        let deferred = WGMessageGestureHooks.deferDoubleTap(on: node.view, { [weak node] in
            // The cell may show another message by now.
            guard let node, node.item?.message.stableId == stableId else {
                return
            }
            if WGMessageGestureHooks.handleTap(message: message, context: context, tapCount: 2, chatNode: chatNode) {
                return
            }
            upstream()
        })
        if deferred {
            return true
        }
    }
    return WGMessageGestureHooks.handleTap(message: message, context: context, tapCount: 2, chatNode: item.controllerInteraction.chatControllerNode())
}

/// WRAITH hook target: `didLoad` of the bubble. Adds a triple-tap recognizer only when a feature
/// handles taps.
func wgInstallBubbleTripleTap(_ node: ChatMessageItemView) {
    guard let recognizer = WGMessageGestureHooks.makeTripleTapRecognizer({ [weak node] in
        guard let node, let item = node.item else {
            return false
        }
        return wgBubbleHandleTap(item, message: item.message, tapCount: 3)
    }) else {
        return
    }
    node.view.addGestureRecognizer(recognizer)
}

/// Not a preview and not the message shown inside its own context menu.
private func wgBubbleIsInteractive(_ item: ChatMessageItem) -> Bool {
    if item.presentationData.isPreview {
        return false
    }
    if let subject = item.associatedData.subject, case .messageOptions = subject {
        return false
    }
    return true
}

// MARK: - Quick translate button

private var wgTranslateButtonKey: UInt8 = 0

private final class WGBubbleTranslateButtonNode: HighlightTrackingButtonNode {
    let iconNode: ASImageNode
    private var backgroundBlurView: PortalView?
    private var theme: PresentationTheme?
    var action: (() -> Void)?

    init() {
        self.iconNode = ASImageNode()
        self.iconNode.displaysAsynchronously = false
        self.iconNode.isUserInteractionEnabled = false
        super.init()
        self.addSubnode(self.iconNode)
        self.addTarget(self, action: #selector(self.pressed), forControlEvents: .touchUpInside)
        self.highligthedChanged = { [weak self] highlighted in
            guard let self else {
                return
            }
            self.iconNode.alpha = highlighted ? 0.4 : 1.0
        }
    }

    @objc private func pressed() {
        self.action?()
    }

    func update(item: ChatMessageItem, size: CGSize) {
        let theme = item.presentationData.theme
        if self.theme !== theme.theme {
            self.theme = theme.theme
            let color = bubbleVariableColor(variableColor: theme.theme.chat.message.shareButtonForegroundColor, wallpaper: theme.wallpaper)
            self.iconNode.image = generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Translate"), color: color)
        }
        if self.backgroundBlurView == nil, let backgroundBlurView = item.controllerInteraction.presentationContext.backgroundNode?.makeFreeBackground() {
            self.backgroundBlurView = backgroundBlurView
            backgroundBlurView.view.clipsToBounds = true
            backgroundBlurView.view.isUserInteractionEnabled = false
            self.view.insertSubview(backgroundBlurView.view, at: 0)
        }
        if let backgroundBlurView = self.backgroundBlurView {
            backgroundBlurView.view.frame = CGRect(origin: CGPoint(), size: size)
            backgroundBlurView.view.layer.cornerRadius = size.width / 2.0
        }
        if let image = self.iconNode.image {
            let iconSize = CGSize(width: min(22.0, image.size.width), height: min(22.0, image.size.height))
            self.iconNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - iconSize.width) / 2.0), y: floorToScreenPixels((size.height - iconSize.height) / 2.0)), size: iconSize)
        }
    }
}

/// WRAITH hook target: the bubble's apply, after the share buttons are placed. Shows the button
/// beside the bubble (above the share button when there is one) when a feature gives a source
/// language and there is room at the side of the screen; removes it otherwise.
func wgLayoutBubbleTranslateButton(_ node: ChatMessageItemView, item: ChatMessageItem, backgroundFrame: CGRect, incoming: Bool, shareButtonFrame: CGRect?, isHidden: Bool, width: CGFloat) {
    var language: String?
    // The menu's «Перевод» preview shows the button too (it stays inert there: previews take no taps).
    if wgBubbleIsInteractive(item) || (item.presentationData.isPreview && WGPreviewMessageDecorations.isMenuPreview(item.message)) {
        language = WGMessageDecorationHooks.translateButtonLanguage(for: item.message, context: item.context)
    }
    let current = objc_getAssociatedObject(node, &wgTranslateButtonKey) as? WGBubbleTranslateButtonNode
    let size = CGSize(width: 30.0, height: 30.0)
    var frame = CGRect(origin: CGPoint(x: incoming ? backgroundFrame.maxX + 8.0 : backgroundFrame.minX - size.width - 8.0, y: backgroundFrame.maxY - size.height - 1.0), size: size)
    if let shareButtonFrame {
        frame.origin.y = shareButtonFrame.minY - size.height - 8.0
    }
    let fits = frame.minX >= 4.0 && frame.maxX <= width - 4.0 && frame.minY >= backgroundFrame.minY - 8.0
    guard language != nil, fits else {
        if let current {
            current.removeFromSupernode()
            objc_setAssociatedObject(node, &wgTranslateButtonKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        return
    }
    let button: WGBubbleTranslateButtonNode
    if let current {
        button = current
    } else {
        button = WGBubbleTranslateButtonNode()
        node.addSubnode(button)
        objc_setAssociatedObject(node, &wgTranslateButtonKey, button, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    button.action = { [weak node] in
        guard let item = node?.item else {
            return
        }
        let message = item.message
        item.controllerInteraction.performTextSelectionAction(message, !message.isCopyProtected(), NSAttributedString(string: message.text), message.textEntitiesAttribute?.entities, .translate)
    }
    button.update(item: item, size: size)
    button.frame = frame
    button.alpha = isHidden ? 0.0 : 1.0
}

/// WRAITH hook target: the bubble's `hitTest`, before the share button.
func wgBubbleTranslateButtonHitTest(_ node: ASDisplayNode, point: CGPoint, event: UIEvent?) -> UIView? {
    guard let button = objc_getAssociatedObject(node, &wgTranslateButtonKey) as? WGBubbleTranslateButtonNode, button.alpha > 0.0, button.frame.contains(point) else {
        return nil
    }
    return button.view.hitTest(node.view.convert(point, to: button.view), with: event)
}

/// WRAITH hook target: the bubble's tap recognizer must not take taps on the button.
func wgBubbleTranslateButtonContains(_ node: ASDisplayNode, point: CGPoint) -> Bool {
    guard let button = objc_getAssociatedObject(node, &wgTranslateButtonKey) as? WGBubbleTranslateButtonNode else {
        return false
    }
    return button.alpha > 0.0 && button.frame.contains(point)
}
