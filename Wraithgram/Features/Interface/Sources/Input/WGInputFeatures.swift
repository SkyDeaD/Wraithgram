import Foundation
import UIKit
import ObjectiveC
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ChatTextInputPanelNode
import AttachmentTextInputPanelNode
import ChatTextInputActionButtonsNode
import EntityKeyboard
import WGCore
import WGHooks

/// Input panel (input_bar_editor, typing_animation, SG-F11, auto formatting, character counter).
/// Everything per layout / keystroke reads one published snapshot; nothing is written per frame
/// (the geometry editor writes on release, see WGInputBarEditor).
enum WGInputFeature {
    static func register() {
        WGInputBarHooks.geometry.register({
            if let draft = WGInputBarEditorDraft.current {
                return draft.layoutGeometry
            }
            return InterfaceSnapshots.shared.current.inputBarGeometry.layoutGeometry
        })

        WGInputPanelHooks.sendButtonSlotWidth.register({ panel, context in
            return WGCharacterCounter.slotWidth(panel: panel, context: context)
        })

        WGInputPanelHooks.didLayout.register({ layout in
            let snapshot = InterfaceSnapshots.shared.current
            WGCharacterCounter.update(layout, isEnabled: snapshot.characterCounter)
            // The chat panel places the toolbar under its field itself (bottomAccessory below);
            // the attachment caption gets it above the field, in the panel's own coordinates.
            guard let panel = layout.panel as? AttachmentTextInputPanelNode else {
                return
            }
            if snapshot.formattingToolbar || WGFormattingToolbar.hasToolbar(panel.view) {
                let presentationData = layout.context?.sharedContext.currentPresentationData.with { $0 }
                guard let theme = presentationData?.theme else {
                    return
                }
                WGFormattingToolbar.update(WGFormattingToolbarRequest(hostView: panel.view, panelFrame: CGRect(origin: CGPoint(), size: CGSize(width: layout.width, height: layout.height)), isFocused: panel.isFocused, theme: theme, transition: layout.transition))
            }
        })

        // The toolbar over a composer's top edge is outside its bounds: the composers ask for it first.
        WGInputPanelHooks.overlayHitTest.register({ view, point, event in
            return WGFormattingToolbar.hitTest(in: view, point: point, event: event)
        })
        WGInputBarHooks.toolbarHitTest.register({ view, point, event in
            return WGFormattingToolbar.hitTest(in: view, point: point, event: event)
        })

        WGInputBarHooks.bottomAccessory.register({ request in
            return WGFormattingToolbar.layoutBelow(request)
        })

        // The composers that are components (stories, gift message) call this point themselves.
        WGInputBarHooks.formattingToolbar.register({ request in
            WGFormattingToolbar.update(request)
        })

        WGInputPanelHooks.textDidChange.register({ panel, _ in
            WGTypingAnimation.play(panel: panel)
        })

        // SG-G9.
        WGEmojiKeyboardHooks.style.register({
            return WGEmojiKeyboardStyle(emojiTabFirst: InterfaceSettings.emojiTabFirst.value, standardEmojiFirst: InterfaceSettings.standardEmojiFirst.value)
        })

        // Auto formatting: the whole text of a sent message / caption in one style. Last in the
        // chain, after W2-3's text stages (which may change the text).
        WGOutgoingHooks.textStages.register({ text, _ in
            guard InterfaceSettings.autoFormatting.value, !text.text.isEmpty else {
                return
            }
            guard let type = WGAutoFormatting.entityType(InterfaceSettings.autoFormattingStyle.value) else {
                return
            }
            let length = (text.text as NSString).length
            if text.entities.contains(where: { $0.range == 0 ..< length && $0.type == type }) {
                return
            }
            text.entities.append(MessageTextEntity(range: 0 ..< length, type: type))
        }, order: 900)
    }
}

extension WGInputBarGeometry {
    var layoutGeometry: WGInputBarLayoutGeometry {
        return WGInputBarLayoutGeometry(
            heightPadding: CGFloat(self.heightPadding),
            leftMargin: CGFloat(self.leftMargin),
            rightMargin: CGFloat(self.rightMargin),
            bottomOffset: CGFloat(self.bottomOffset),
            attachOffset: CGPoint(x: self.attachX, y: self.attachY),
            accessoryOffset: CGPoint(x: self.accessoryX, y: self.accessoryY),
            sendOffset: CGPoint(x: self.sendX, y: self.sendY)
        )
    }
}

enum WGAutoFormatting {
    static let styles = ["bold", "italic", "monospace", "strikethrough", "underline", "spoiler", "quote", "code"]

    static func entityType(_ style: String) -> MessageTextEntityType? {
        switch style {
        case "bold":
            return .Bold
        case "italic":
            return .Italic
        case "monospace":
            return .Code
        case "strikethrough":
            return .Strikethrough
        case "underline":
            return .Underline
        case "spoiler":
            return .Spoiler
        case "quote":
            return .BlockQuote(isCollapsed: false)
        case "code":
            return .Pre(language: nil)
        default:
            return nil
        }
    }

    static func title(_ style: String) -> String {
        switch style {
        case "bold":
            return WGStrings.Interface.Input.styleBold
        case "italic":
            return WGStrings.Interface.Input.styleItalic
        case "monospace":
            return WGStrings.Interface.Input.styleMonospace
        case "strikethrough":
            return WGStrings.Interface.Input.styleStrikethrough
        case "underline":
            return WGStrings.Interface.Input.styleUnderline
        case "spoiler":
            return WGStrings.Interface.Input.styleSpoiler
        case "quote":
            return WGStrings.Interface.Input.styleQuote
        default:
            return WGStrings.Interface.Input.styleCode
        }
    }
}

private var wgCharacterCounterKey: UInt8 = 0

/// «Счётчик символов»: the length of the text from its first character (owner, build 189). While the
/// text is one line it stands right before the send button — the panel moves the emoji button left for
/// it (`WGInputPanelHooks.sendButtonSlotWidth`); past one line it goes back to the field's top-right
/// corner, above the buttons, or — when Telegram's article-editor button stands there — right before
/// that button (`WGInputPanelLayout.slot`). The font is Telegram's `Font`, so a custom font applies to it
/// as to the rest of the panel.
enum WGCharacterCounter {
    /// Room on each side of the counter beyond what the panel already leaves between the glyphs.
    private static let spacing: CGFloat = 3.0

    static func font(baseFontSize: CGFloat) -> UIFont {
        return Font.with(size: floor(baseFontSize * 13.0 / 17.0), traits: .monospacedNumbers)
    }

    /// The room the counter asks for in the text row, pt (0 = none).
    static func slotWidth(count: Int, font: UIFont) -> CGFloat {
        if count == 0 {
            return 0.0
        }
        return ceil(("\(count)" as NSString).size(withAttributes: [.font: font]).width) + WGCharacterCounter.spacing
    }

    private static func baseFontSize(_ context: AccountContext?) -> CGFloat {
        let presentationData = context?.sharedContext.currentPresentationData.with({ $0 })
        return presentationData.flatMap { chatTextInputBaseFontSize(for: $0.chatFontSize) } ?? 17.0
    }

    /// WGInputPanelHooks.sendButtonSlotWidth: asked on every text measurement of the chat panel.
    static func slotWidth(panel: ASDisplayNode, context: AccountContext?) -> CGFloat {
        guard InterfaceSnapshots.shared.current.characterCounter, let panel = panel as? ChatTextInputPanelNode else {
            return 0.0
        }
        return WGCharacterCounter.slotWidth(count: panel.inputTextState.inputText.string.count, font: WGCharacterCounter.font(baseFontSize: WGCharacterCounter.baseFontSize(context)))
    }

    static func update(_ layout: WGInputPanelLayout, isEnabled: Bool) {
        let existing = objc_getAssociatedObject(layout.panel, &wgCharacterCounterKey) as? UILabel
        guard isEnabled, let panel = layout.panel as? ChatTextInputPanelNode, layout.slot != .none else {
            existing?.isHidden = true
            return
        }
        let count = panel.inputTextState.inputText.string.count
        guard count > 0 else {
            existing?.isHidden = true
            return
        }
        let label: UILabel
        if let existing {
            label = existing
        } else {
            label = UILabel()
            label.isHidden = true
            label.isUserInteractionEnabled = false
            panel.view.addSubview(label)
            objc_setAssociatedObject(layout.panel, &wgCharacterCounterKey, label, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let font = WGCharacterCounter.font(baseFontSize: WGCharacterCounter.baseFontSize(layout.context))
        if label.font != font {
            label.font = font
        }
        if let presentationData = layout.context?.sharedContext.currentPresentationData.with({ $0 }) {
            label.textColor = presentationData.theme.chat.inputPanel.panelControlColor
        }
        label.text = "\(count)"
        let size = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let frame: CGRect
        switch layout.slot {
        case .none:
            return
        case let .beforeSendButton(rect), let .beforeCornerButton(rect):
            frame = CGRect(origin: CGPoint(x: floorToScreenPixels(rect.midX - size.width * 0.5), y: floorToScreenPixels(rect.midY - size.height * 0.5)), size: size)
        case let .textCorner(rect):
            frame = CGRect(origin: CGPoint(x: rect.maxX - size.width - 11.0, y: rect.minY + 4.0), size: size)
        }
        if label.isHidden {
            label.isHidden = false
            label.frame = frame
        } else {
            layout.transition.updateFrame(view: label, frame: frame)
        }
        panel.view.bringSubviewToFront(label)
    }
}
