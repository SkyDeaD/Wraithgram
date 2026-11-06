// The chat screen: lifecycle, the gate before a chat opens (chat lock), capture protection,
// overlays above the wallpaper / above the history (GIF wallpaper, blur, snow, quick buttons),
// pre-processing of the composed text before sending (translation), the reply subject and the
// default quote, items of the Send button's menu, documents a feature opens itself.
// Call sites: ChatController.swift, ChatControllerNode.swift, ChatControllerLoadDisplayNode.swift,
// NavigateToChatController.swift, ChatMessageDisplaySendMessageOptions.swift, OpenChatMessage.swift
// (helpers needing internal types: WGHooks/TelegramUI/).

import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import ContextUI
import WGCore

public enum WGChatScreenEvent {
    case willAppear
    case didAppear
    case willDisappear
}

/// One chat screen as features see it.
public struct WGChatScreen {
    public let context: AccountContext
    public let chatLocation: ChatLocation
    public weak var controller: ChatController?
    /// The chat is shown as a peek preview (long press in the chat list).
    public let isPreview: Bool

    public init(context: AccountContext, chatLocation: ChatLocation, controller: ChatController?, isPreview: Bool) {
        self.context = context
        self.chatLocation = chatLocation
        self.controller = controller
        self.isPreview = isPreview
    }
}

/// Where an overlay node goes on the chat screen.
public enum WGChatOverlayPlacement {
    /// Above the wallpaper, below the messages (GIF wallpaper, snow, blur).
    case aboveWallpaper
    /// Above the messages (quick-action buttons). Leave the rest of the screen tappable.
    case aboveHistory
}

/// A feature-owned node on the chat screen, created once per screen and laid out with it.
public protocol WGChatOverlay: AnyObject {
    var node: ASDisplayNode { get }
    var placement: WGChatOverlayPlacement { get }
    /// `bounds` = the wallpaper area; `insets` = the history's insets (navigation bar, input panel).
    func updateLayout(bounds: CGRect, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition)
}

public struct WGCaptureProtectionRequest {
    public let context: AccountContext
    public let chatLocation: ChatLocation
    /// What upstream decided (copy protection, secret chat, verification codes).
    public let upstreamValue: Bool
}

/// The text in the composer when the user taps Send.
public struct WGComposedTextRequest {
    public let context: AccountContext
    public let chatLocation: ChatLocation
    public let state: ChatTextInputState
    /// Replaces the composer content (keeps it undoable for the user); call before `proceed`.
    public let replace: (ChatTextInputState) -> Void

    public init(context: AccountContext, chatLocation: ChatLocation, state: ChatTextInputState, replace: @escaping (ChatTextInputState) -> Void) {
        self.context = context
        self.chatLocation = chatLocation
        self.state = state
        self.replace = replace
    }
}

public struct WGReplyRequest {
    public let context: AccountContext
    public let chatLocation: ChatLocation
    public let messageId: EngineMessage.Id
}

/// The long-press menu of the Send button (the text in the composer, not sent yet).
public struct WGSendMenuContext {
    public let context: AccountContext
    public let peerId: EnginePeer.Id
    /// The chat's language as Telegram predicts it, if known.
    public let predictedLanguage: String?
    public let inputText: NSAttributedString
    /// Replaces the composer's text.
    public let replaceInput: (NSAttributedString) -> Void
    /// Closes the menu.
    public let dismiss: () -> Void
    /// Presents a controller over the chat.
    public let present: (ViewController) -> Void

    public init(context: AccountContext, peerId: EnginePeer.Id, predictedLanguage: String?, inputText: NSAttributedString, replaceInput: @escaping (NSAttributedString) -> Void, dismiss: @escaping () -> Void, present: @escaping (ViewController) -> Void) {
        self.context = context
        self.peerId = peerId
        self.predictedLanguage = predictedLanguage
        self.inputText = inputText
        self.replaceInput = replaceInput
        self.dismiss = dismiss
        self.present = present
    }
}

/// A downloaded document tapped in a chat.
public struct WGOpenDocumentRequest {
    public let context: AccountContext
    /// The file name as sent (`TelegramMediaFile.fileName`).
    public let fileName: String
    /// Local path of the downloaded file (`mediaBox.completedResourcePath`).
    public let path: String
    public weak var controller: ViewController?

    public init(context: AccountContext, fileName: String, path: String, controller: ViewController?) {
        self.context = context
        self.fileName = fileName
        self.path = path
        self.controller = controller
    }
}

public enum WGChatScreenHooks {
    /// Set once by the app (TelegramUI launch): scrolls a chat to its very first message (loads the
    /// history from the start if needed, with Telegram's loading indicator).
    public static var scrollToStartOfHistory: ((ChatController) -> Void)?

    /// Observers of the chat screen's appearance (chat lock cover, stats, "read on open"…). Main thread.
    public static let lifecycle = WGHookPoint<(WGChatScreenEvent, WGChatScreen) -> Void>("chatScreen.lifecycle")

    /// Gate before a chat opens (`navigateToChatController`). Return `true` to take over and
    /// call `proceed()` after your check (the second pass is not asked again).
    public static let openChat = WGHookPoint<(NavigateToChatControllerParams, @escaping () -> Void) -> Bool>("chatScreen.openChat")

    /// Policy: whether the chat hides its content from screenshots / recording.
    public static let captureProtection = WGHookPoint<(WGCaptureProtectionRequest) -> Bool?>("chatScreen.captureProtection")

    /// Policy (any `true`): the chat's chrome — header, input panel and the panels above it,
    /// navigation buttons, overlays above the history — comes out empty on screenshots and screen
    /// recordings; the messages stay as they are (that is `captureProtection`), and the send
    /// animation is skipped (it would carry the typed text through an unprotected layer). Asked on
    /// every layout of the chat screen: answer from a snapshot (W3-4 «Скрывать чат на скриншотах»).
    public static let hidesChromeFromCapture = WGHookPoint<(AccountContext, ChatLocation) -> Bool>("chatScreen.hidesChromeFromCapture")

    /// Provider of overlays for a chat screen; called once when the screen's node is created.
    public static let overlays = WGHookPoint<(WGChatScreen) -> [WGChatOverlay]>("chatScreen.overlays")

    /// Gate on Send for composed text. Return `true` to take over (e.g. translate first):
    /// `replace` the text, then call `proceed()`, which sends without asking again.
    public static let willSendText = WGHookPoint<(WGComposedTextRequest, @escaping () -> Void) -> Bool>("chatScreen.willSendText")

    /// Transformer of the reply subject when the user starts a reply (quote the text, …).
    public static let replySubject = WGHookPoint<(EngineMessageReplyInnerSubject?, WGReplyRequest) -> EngineMessageReplyInnerSubject?>("chatScreen.replySubject")

    /// Policy (first non-nil wins): the quote a new reply starts with («Отвечать цитатой»).
    /// nil = no quote, as upstream.
    public static let replyQuote = WGHookPoint<(Message, WGReplyRequest) -> EngineMessageReplyQuote?>("chatScreen.replyQuote")

    /// Providers of extra items in the long-press menu of the Send button. Main thread.
    public static let sendMenuItems = WGHookPoint<(WGSendMenuContext) -> [ContextMenuItem]>("chatScreen.sendMenuItems")

    /// Policy (first `true` wins): a feature opens a downloaded document itself (icon packs,
    /// badges). Main thread.
    public static let openDocument = WGHookPoint<(WGOpenDocumentRequest) -> Bool>("chatScreen.openDocument")

    /// Providers of attributes added to a message that repeats a bot keyboard button's text
    /// (`ChatControllerInteraction.sendMessage`): the bot expects the text exactly, so a feature
    /// marks it to skip its outgoing transformations.
    public static let botButtonReplyAttributes = WGHookPoint<() -> [MessageAttribute]>("chatScreen.botButtonReplyAttributes")

    /// Policy (any `true`): a chat's translation is shown in the bubbles without Telegram Premium
    /// (WGMessages: always, as in Swiftgram). Asked on every history update: answer from a snapshot.
    public static let translatesChatsWithoutPremium = WGHookPoint<() -> Bool>("chatScreen.translatesChatsWithoutPremium")

    /// Policy: `false` = no sponsored messages in this chat.
    public static let showsAdMessages = WGHookPoint<(AccountContext, EnginePeer.Id) -> Bool?>("chatScreen.showsAdMessages")

    /// Policy (any `true`): hide a message from the chat history (messages of blocked users).
    /// Asked for every message on every history update: answer from a snapshot (a set of ids).
    public static let hidesMessage = WGHookPoint<(Message, AccountContext, ChatLocation) -> Bool>("chatScreen.hidesMessage")

    /// Policy: `false` = no "dust" effect when messages are deleted (new chat screens).
    public static let deleteEffect = WGHookPoint<(AccountContext) -> Bool?>("chatScreen.deleteEffect")

    /// Policy: the maximum content width of a message bubble (wide channel posts). Called in the
    /// bubble's layout for every message: answer from a snapshot. nil = upstream width.
    public static let bubbleMaxWidth = WGHookPoint<(CGFloat, Message, AccountContext) -> CGFloat?>("chatScreen.bubbleMaxWidth")

    // MARK: Call-site helpers

    public static func notify(_ event: WGChatScreenEvent, screen: @autoclosure () -> WGChatScreen) {
        if WGChatScreenHooks.lifecycle.isEmpty {
            return
        }
        let value = screen()
        for handler in WGChatScreenHooks.lifecycle.handlers {
            handler(event, value)
        }
    }

    private static var openChatBypass: ObjectIdentifier?

    /// Main thread. `true` = a gate took over; the call site returns.
    public static func interceptOpenChat(_ params: NavigateToChatControllerParams, proceed: @escaping () -> Void) -> Bool {
        if WGChatScreenHooks.openChat.isEmpty {
            return false
        }
        let id = ObjectIdentifier(params)
        if WGChatScreenHooks.openChatBypass == id {
            WGChatScreenHooks.openChatBypass = nil
            return false
        }
        let continuation: () -> Void = {
            WGChatScreenHooks.openChatBypass = id
            proceed()
        }
        for handler in WGChatScreenHooks.openChat.handlers {
            if handler(params, continuation) {
                return true
            }
        }
        return false
    }

    public static func captureProtection(_ upstreamValue: Bool, context: AccountContext, chatLocation: ChatLocation) -> Bool {
        if WGChatScreenHooks.captureProtection.isEmpty {
            return upstreamValue
        }
        let request = WGCaptureProtectionRequest(context: context, chatLocation: chatLocation, upstreamValue: upstreamValue)
        for handler in WGChatScreenHooks.captureProtection.handlers {
            if let value = handler(request) {
                return value
            }
        }
        return upstreamValue
    }

    /// `false` while the point is empty (upstream).
    public static func hidesChromeFromCapture(context: AccountContext, chatLocation: ChatLocation) -> Bool {
        if WGChatScreenHooks.hidesChromeFromCapture.isEmpty {
            return false
        }
        for handler in WGChatScreenHooks.hidesChromeFromCapture.handlers {
            if handler(context, chatLocation) {
                return true
            }
        }
        return false
    }

    public static func makeOverlays(_ screen: WGChatScreen) -> [WGChatOverlay] {
        if WGChatScreenHooks.overlays.isEmpty {
            return []
        }
        var result: [WGChatOverlay] = []
        for handler in WGChatScreenHooks.overlays.handlers {
            result.append(contentsOf: handler(screen))
        }
        return result
    }

    private static var sendBypass: ObjectIdentifier?

    /// Main thread. `owner` identifies the screen (its node); `true` = a gate took over.
    public static func interceptSend(owner: AnyObject, request: @autoclosure () -> WGComposedTextRequest, proceed: @escaping () -> Void) -> Bool {
        if WGChatScreenHooks.willSendText.isEmpty {
            return false
        }
        let id = ObjectIdentifier(owner)
        if WGChatScreenHooks.sendBypass == id {
            WGChatScreenHooks.sendBypass = nil
            return false
        }
        let value = request()
        let continuation: () -> Void = {
            WGChatScreenHooks.sendBypass = id
            proceed()
        }
        for handler in WGChatScreenHooks.willSendText.handlers {
            if handler(value, continuation) {
                return true
            }
        }
        return false
    }

    public static func transformReply(_ subject: EngineMessageReplyInnerSubject?, messageId: EngineMessage.Id?, context: AccountContext, chatLocation: ChatLocation) -> EngineMessageReplyInnerSubject? {
        guard let messageId, !WGChatScreenHooks.replySubject.isEmpty else {
            return subject
        }
        let request = WGReplyRequest(context: context, chatLocation: chatLocation, messageId: messageId)
        var result = subject
        for handler in WGChatScreenHooks.replySubject.handlers {
            result = handler(result, request)
        }
        return result
    }

    /// The quote of a new reply; `message` is evaluated only when a feature answers.
    public static func defaultReplyQuote(_ message: @autoclosure () -> Message?, messageId: EngineMessage.Id, context: AccountContext, chatLocation: ChatLocation) -> EngineMessageReplyQuote? {
        if WGChatScreenHooks.replyQuote.isEmpty {
            return nil
        }
        guard let message = message() else {
            return nil
        }
        let request = WGReplyRequest(context: context, chatLocation: chatLocation, messageId: messageId)
        for handler in WGChatScreenHooks.replyQuote.handlers {
            if let quote = handler(message, request) {
                return quote
            }
        }
        return nil
    }

    /// Items for the Send button's menu; `context` is built only when a feature provides items.
    public static func sendMenuItems(_ context: @autoclosure () -> WGSendMenuContext) -> [ContextMenuItem] {
        if WGChatScreenHooks.sendMenuItems.isEmpty {
            return []
        }
        let value = context()
        var result: [ContextMenuItem] = []
        for handler in WGChatScreenHooks.sendMenuItems.handlers {
            result.append(contentsOf: handler(value))
        }
        return result
    }

    /// `true` = a feature opened the document; the call site does nothing else.
    public static func handleOpenDocument(_ request: @autoclosure () -> WGOpenDocumentRequest?) -> Bool {
        if WGChatScreenHooks.openDocument.isEmpty {
            return false
        }
        guard let value = request() else {
            return false
        }
        for handler in WGChatScreenHooks.openDocument.handlers {
            if handler(value) {
                return true
            }
        }
        return false
    }

    public static func collectBotButtonReplyAttributes() -> [MessageAttribute] {
        if WGChatScreenHooks.botButtonReplyAttributes.isEmpty {
            return []
        }
        var result: [MessageAttribute] = []
        for handler in WGChatScreenHooks.botButtonReplyAttributes.handlers {
            result.append(contentsOf: handler())
        }
        return result
    }

    public static func translatesWithoutPremium() -> Bool {
        for handler in WGChatScreenHooks.translatesChatsWithoutPremium.handlers {
            if handler() {
                return true
            }
        }
        return false
    }

    public static func hidesMessage(_ message: Message, context: AccountContext, location: ChatLocation) -> Bool {
        if WGChatScreenHooks.hidesMessage.isEmpty {
            return false
        }
        for handler in WGChatScreenHooks.hidesMessage.handlers {
            if handler(message, context, location) {
                return true
            }
        }
        return false
    }

    public static func bubbleMaxWidth(_ width: CGFloat, message: Message, context: AccountContext) -> CGFloat {
        if WGChatScreenHooks.bubbleMaxWidth.isEmpty {
            return width
        }
        for handler in WGChatScreenHooks.bubbleMaxWidth.handlers {
            if let value = handler(width, message, context) {
                return max(0.0, value)
            }
        }
        return width
    }

    public static func allowsDeleteEffect(context: AccountContext) -> Bool {
        for handler in WGChatScreenHooks.deleteEffect.handlers {
            if let value = handler(context) {
                return value
            }
        }
        return true
    }

    public static func showsAdMessages(context: AccountContext, peerId: EnginePeer.Id) -> Bool {
        for handler in WGChatScreenHooks.showsAdMessages.handlers {
            if let value = handler(context, peerId) {
                return value
            }
        }
        return true
    }
}
