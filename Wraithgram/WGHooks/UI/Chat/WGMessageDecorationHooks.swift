// Per-message decorations, computed ONCE per message version and handed to every cell type:
// transparency of deleted messages and keyword-filtered ones, a status prefix («удалено»,
// «изменено ×3»), a local text (local edit, previous versions), revealed spoilers, hidden "via".
// Call sites: ChatMessageItemView.setupItem (alpha, all message types),
// stringForMessageTimestampStatus (status prefix, all content nodes),
// ChatMessageTextBubbleContentNode (text override, spoilers, footnote), ChatMessageBubbleItemNode
// (via, the quick translate button beside the bubble).
//
// Computation: the handlers form a transformer chain over `WGMessageDecoration`. The result is
// cached by (message id, stable version, generation); the generation moves on every settings
// change (WGSettingsStore.revision) and on `invalidate()`. Handlers read snapshots only.

import Foundation
import UIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import WGCore

public struct WGMessageTextOverride: Equatable {
    public var text: String
    public var entities: [MessageTextEntity]

    public init(text: String, entities: [MessageTextEntity]) {
        self.text = text
        self.entities = entities
    }
}

/// A secondary text under the message text (previous versions), drawn by the text bubble in its
/// own node: it is not selected or copied with the message and has its own opacity.
public struct WGMessageFootnote: Equatable {
    public var text: String
    public var entities: [MessageTextEntity]
    public var alpha: CGFloat

    public init(text: String, entities: [MessageTextEntity], alpha: CGFloat) {
        self.text = text
        self.entities = entities
        self.alpha = alpha
    }
}

/// A flat icon a feature puts in the status line instead of an emoji: its marker character goes
/// into `WGMessageDecoration.statusPrefix`, and ChatMessageDateAndStatusNode draws the icon before
/// the time in the time's color (a consumer that only reads the text drops the marker).
public enum WGStatusIcon: Character, CaseIterable {
    /// A message deleted for everyone and kept by Wraithgram.
    case deleted = "\u{E8D0}"

    /// Bundle image of the icon (a 24 pt context-menu template).
    public var imageName: String {
        switch self {
        case .deleted:
            return "Chat/Context Menu/Delete"
        }
    }

    /// The text without markers and the icons it carried, in order.
    public static func split(_ text: String) -> (text: String, icons: [WGStatusIcon]) {
        var icons: [WGStatusIcon] = []
        var result = ""
        for character in text {
            if let icon = WGStatusIcon(rawValue: character) {
                icons.append(icon)
            } else {
                result.append(character)
            }
        }
        if icons.isEmpty {
            return (text, [])
        }
        return (result, icons)
    }
}

public struct WGMessageDecoration: Equatable {
    /// Opacity of the whole message (deleted, keyword-filtered). 1 = upstream.
    public var alpha: CGFloat = 1.0
    /// Text put before the time in the status line («✎3 », «🔖 »); `WGStatusIcon` markers in it
    /// become flat icons.
    public var statusPrefix: String?
    /// Replaces the shown text of a text message (local edit, inline history).
    public var textOverride: WGMessageTextOverride?
    /// Show spoilers uncovered.
    public var revealsSpoilers: Bool = false
    /// Hide "via @bot" in the bubble header.
    public var hidesViaBot: Bool = false
    /// Free-form markers for feature-owned UI that reads them (bookmark, badge ids…).
    public var markers: Set<String> = Set()
    /// A secondary text under the message text (text bubbles only).
    public var footnote: WGMessageFootnote?
    /// The language to translate from when the bubble shows a quick translate button beside it.
    /// Filled from `WGMessageDecorationHooks.translateButtonLanguage` (or by a decoration handler).
    public var translateButtonLanguage: String?

    public init() {
    }

    public static let none = WGMessageDecoration()
}

public struct WGMessageDecorationContext {
    public let context: AccountContext
    public let message: Message
}

public enum WGMessageDecorationHooks {
    /// Transformer chain over the decoration of one message.
    public static let decorations = WGHookPoint<(inout WGMessageDecoration, WGMessageDecorationContext) -> Void>("messageDecoration.decorations")

    /// Policy (first non-nil wins): the source language of a message that gets a quick translate
    /// button beside its bubble (SG-E2). Evaluated once per message version together with the
    /// decorations (cached): language detection may be slow, the bubble layout must not be.
    public static let translateButtonLanguage = WGHookPoint<(Message, AccountContext) -> String?>("messageDecoration.translateButtonLanguage")

    /// True when some feature decorates messages (a plain load when nobody does).
    public static var isActive: Bool {
        return !WGMessageDecorationHooks.decorations.isEmpty || !WGMessageDecorationHooks.translateButtonLanguage.isEmpty
    }

    /// The decoration of `message`, cached. `.none` when nobody decorates.
    public static func decoration(for message: Message, context: AccountContext) -> WGMessageDecoration {
        if !WGMessageDecorationHooks.isActive {
            return .none
        }
        return wgMessageDecorationCache.decoration(for: message, context: context)
    }

    /// Drops cached decorations (a feature's own state changed outside the settings registry).
    public static func invalidate() {
        wgMessageDecorationCache.invalidate()
    }

    /// For state kept outside the message (bookmark toggled, local edit saved): drops the cache
    /// and re-lays out these messages in every open chat. Without it a shown bubble keeps its old
    /// decoration until the history updates. Albums are redrawn on the next history update.
    public static func redraw(messageIds: [EngineMessage.Id]) {
        wgMessageDecorationCache.invalidate()
        if !messageIds.isEmpty {
            wgMessageDecorationRedrawPipe.putNext(messageIds)
        }
    }

    /// Redraw requests; the chat history listens (helper in WGHooks/TelegramUI).
    public static var redrawRequests: Signal<[EngineMessage.Id], NoError> {
        return wgMessageDecorationRedrawPipe.signal()
    }

    /// For state that changes many messages at once outside the settings registry (the badge list
    /// arrived): drops the cache and re-lays out every visible bubble of every open chat, once,
    /// 0.3 s after the last request (the same pass a settings change triggers).
    public static func redrawAll() {
        wgMessageDecorationCache.invalidate()
        wgMessageDecorationRedrawAllPipe.putNext(Void())
    }

    /// Requests of `redrawAll()`; the chat history listens (helper in WGHooks/TelegramUI).
    public static var redrawAllRequests: Signal<Void, NoError> {
        return wgMessageDecorationRedrawAllPipe.signal()
    }

    /// True when open chats must listen for redraws: something decorates messages.
    public static var needsRedraws: Bool {
        return WGMessageDecorationHooks.isActive
    }

    // MARK: Call-site helpers

    public static func alpha(for message: Message, context: AccountContext) -> CGFloat {
        if WGMessageDecorationHooks.decorations.isEmpty {
            return 1.0
        }
        return WGMessageDecorationHooks.decoration(for: message, context: context).alpha
    }

    public static func statusText(_ text: String, message: Message, context: AccountContext) -> String {
        if let previewPrefix = WGPreviewMessageDecorations.statusPrefix(for: message) {
            return previewPrefix + text
        }
        if WGMessageDecorationHooks.decorations.isEmpty {
            return text
        }
        guard let prefix = WGMessageDecorationHooks.decoration(for: message, context: context).statusPrefix else {
            return text
        }
        return prefix + text
    }

    /// Text bubble: the text and entities to show.
    public static func applyText(_ text: inout String, entities: inout [MessageTextEntity]?, message: Message, context: AccountContext) {
        if WGMessageDecorationHooks.decorations.isEmpty {
            return
        }
        let decoration = WGMessageDecorationHooks.decoration(for: message, context: context)
        if let textOverride = decoration.textOverride {
            text = textOverride.text
            entities = textOverride.entities
        }
        if decoration.revealsSpoilers, let current = entities {
            entities = current.filter { entity in
                if case .Spoiler = entity.type {
                    return false
                }
                return true
            }
        }
    }

    public static func hidesViaBot(_ message: Message, context: AccountContext) -> Bool {
        if WGMessageDecorationHooks.decorations.isEmpty {
            return false
        }
        return WGMessageDecorationHooks.decoration(for: message, context: context).hidesViaBot
    }

    /// The footnote under a text bubble's text, if any.
    public static func footnote(for message: Message, context: AccountContext) -> WGMessageFootnote? {
        if WGMessageDecorationHooks.decorations.isEmpty {
            return nil
        }
        return WGMessageDecorationHooks.decoration(for: message, context: context).footnote
    }

    /// The source language when the bubble shows a quick translate button, nil = no button.
    public static func translateButtonLanguage(for message: Message, context: AccountContext) -> String? {
        if !WGMessageDecorationHooks.isActive {
            return nil
        }
        return WGMessageDecorationHooks.decoration(for: message, context: context).translateButtonLanguage
    }

    /// Redraw requests for every visible message (settings that change decorations: the chat in
    /// the navigation stack under the settings re-lays out its bubbles). Debounced by the listener.
    public static var settingsRevisions: Signal<Void, NoError> {
        return WGSettingsStore.shared.revision
        |> distinctUntilChanged
        |> map { _ -> Void in
            return Void()
        }
    }
}

private struct WGMessageDecorationKey: Hashable {
    let id: MessageId
    let stableVersion: UInt32
    let accountPeerId: PeerId
}

private let wgMessageDecorationRedrawPipe = ValuePipe<[EngineMessage.Id]>()
private let wgMessageDecorationRedrawAllPipe = ValuePipe<Void>()

/// Menu previews (WGSettingsUI) draw fake messages that no feature store knows about. Their status
/// prefix (the same «🗑 » / «✎2 » the chat shows) is registered here by `globallyUniqueId`, so the
/// preview bubble lays its status line out exactly like the chat does. Bypasses the cache: preview
/// messages reuse ids. The same id marks an outgoing preview message as not yet read (one check):
/// Telegram's preview item is always «read».
public enum WGPreviewMessageDecorations {
    /// High half of every preview message's `globallyUniqueId` ("WGPR").
    public static let globallyUniqueIdBase: Int64 = 0x4747_5052 << 32

    private static let lock = NSLock()
    private static var prefixes: [Int64: String] = [:]
    private static var unreadIds = Set<Int64>()

    public static func setUnread(_ isUnread: Bool, globallyUniqueId: Int64) {
        WGPreviewMessageDecorations.lock.lock()
        if isUnread {
            WGPreviewMessageDecorations.unreadIds.insert(globallyUniqueId)
        } else {
            WGPreviewMessageDecorations.unreadIds.remove(globallyUniqueId)
        }
        WGPreviewMessageDecorations.lock.unlock()
    }

    /// A message of a Wraithgram menu preview (every one carries the base in its `globallyUniqueId`).
    /// Telegram's own previews (context menu, forwarding) show the full date; the menu's mini chats
    /// look like the chat: the time only and the «edited» label.
    public static func isMenuPreview(_ message: Message) -> Bool {
        guard let id = message.globallyUniqueId else {
            return false
        }
        return id >> 32 == WGPreviewMessageDecorations.globallyUniqueIdBase >> 32
    }

    /// For `makeChatMessagePreviewItem`: false for every message that is not a menu preview's.
    public static func isUnread(_ message: Message) -> Bool {
        guard let id = message.globallyUniqueId, id >> 32 == WGPreviewMessageDecorations.globallyUniqueIdBase >> 32 else {
            return false
        }
        WGPreviewMessageDecorations.lock.lock()
        let isUnread = WGPreviewMessageDecorations.unreadIds.contains(id)
        WGPreviewMessageDecorations.lock.unlock()
        return isUnread
    }

    public static func setStatusPrefix(_ prefix: String?, globallyUniqueId: Int64) {
        WGPreviewMessageDecorations.lock.lock()
        WGPreviewMessageDecorations.prefixes[globallyUniqueId] = prefix
        WGPreviewMessageDecorations.lock.unlock()
    }

    static func statusPrefix(for message: Message) -> String? {
        guard let id = message.globallyUniqueId, id >> 32 == WGPreviewMessageDecorations.globallyUniqueIdBase >> 32 else {
            return nil
        }
        WGPreviewMessageDecorations.lock.lock()
        let prefix = WGPreviewMessageDecorations.prefixes[id]
        WGPreviewMessageDecorations.lock.unlock()
        return prefix
    }
}

private final class WGMessageDecorationCache {
    private let lock = NSLock()
    private var values: [WGMessageDecorationKey: WGMessageDecoration] = [:]
    /// Moves on every `invalidate()`: a value computed from snapshots taken before it is not stored
    /// (a layout thread could otherwise put an old decoration into the just cleared cache).
    private var generation: UInt64 = 0
    private var revisionDisposable: Disposable?
    private let maximumCount = 4096

    func decoration(for message: Message, context: AccountContext) -> WGMessageDecoration {
        let key = WGMessageDecorationKey(id: message.id, stableVersion: message.stableVersion, accountPeerId: context.account.peerId)
        self.lock.lock()
        let subscribe = self.revisionDisposable == nil
        if subscribe {
            self.revisionDisposable = EmptyDisposable
        }
        if let value = self.values[key] {
            self.lock.unlock()
            return value
        }
        self.lock.unlock()
        if subscribe {
            // Outside the lock: the signal delivers its current value synchronously.
            let disposable = (WGSettingsStore.shared.revision
            |> distinctUntilChanged).start(next: { [weak self] _ in
                self?.invalidate()
            })
            self.lock.lock()
            self.revisionDisposable = disposable
            self.lock.unlock()
        }
        self.lock.lock()
        let generation = self.generation
        self.lock.unlock()

        var value = WGMessageDecoration()
        let decorationContext = WGMessageDecorationContext(context: context, message: message)
        for handler in WGMessageDecorationHooks.decorations.handlers {
            handler(&value, decorationContext)
        }
        if value.translateButtonLanguage == nil {
            for handler in WGMessageDecorationHooks.translateButtonLanguage.handlers {
                if let language = handler(message, context) {
                    value.translateButtonLanguage = language
                    break
                }
            }
        }

        self.lock.lock()
        if self.generation == generation {
            if self.values.count >= self.maximumCount {
                self.values.removeAll(keepingCapacity: true)
            }
            self.values[key] = value
        }
        self.lock.unlock()
        return value
    }

    func invalidate() {
        self.lock.lock()
        self.generation &+= 1
        self.values.removeAll(keepingCapacity: true)
        self.lock.unlock()
    }
}

private let wgMessageDecorationCache = WGMessageDecorationCache()
