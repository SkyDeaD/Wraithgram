import Foundation
import UIKit
import Postbox
import TelegramCore
import AccountContext
import WGCore
import WGHooks
import WGFeaturesShared

/// Per-message decisions of this zone, computed once per message version by the shared decoration
/// cache (WGMessageDecorationHooks) and read by every cell type: revealed spoilers, keyword-filter
/// dimming, the mark on kept view-once media, hidden «via @bot» on own messages, the mark on
/// messages written in the local creator mode.
enum WGMessageDecorations {
    static let keptMediaMark = "🔥 "
    static let localOnlyMark = "📍 "
    static let filteredAlpha: CGFloat = 0.3

    static func register() {
        WGMessageDecorationHooks.decorations.register({ decoration, context in
            WGMessageDecorations.decorate(&decoration, context: context)
        }, order: 300)
    }

    static func decorate(_ decoration: inout WGMessageDecoration, context: WGMessageDecorationContext) {
        let message = context.message
        let accountPeerId = context.context.account.peerId
        let isIncoming = message.effectivelyIncoming(accountPeerId)

        if WGMessagesSettings.revealSpoilers.value {
            decoration.revealsSpoilers = true
        }
        if isIncoming && WGMessagesSettings.keywordFilter.value && WGKeywordMatcher.shared.matches(message.text) {
            decoration.alpha = min(decoration.alpha, WGMessageDecorations.filteredAlpha)
        }
        if isIncoming && WGMessagesSettings.keepSelfDestructingMedia.value && message.wgRawContainsSecretMedia { // raw: the media itself is drawn as ordinary
            decoration.statusPrefix = (decoration.statusPrefix ?? "") + WGMessageDecorations.keptMediaMark
        }
        if !isIncoming && WGMessagesSettings.sendWithoutViaBot.value {
            decoration.hidesViaBot = true
        }
        if message.id.namespace == Namespaces.Message.Local && WGMessagesPolicy.isLocalCreatorMode(accountId: context.context.account.id, peerId: message.id.peerId) {
            decoration.statusPrefix = (decoration.statusPrefix ?? "") + WGMessageDecorations.localOnlyMark
        }
    }
}

/// Case-insensitive keyword matching; the lowercased word list is rebuilt only when the setting
/// changes, the text of each message is checked once (the decoration cache keeps the answer).
final class WGKeywordMatcher {
    static let shared = WGKeywordMatcher()

    private let lock = NSLock()
    private var source: [String] = []
    private var prepared: [String] = []

    func matches(_ text: String) -> Bool {
        if text.isEmpty {
            return false
        }
        let keywords = WGMessagesSettings.keywords.value
        if keywords.isEmpty {
            return false
        }
        self.lock.lock()
        if self.source != keywords {
            self.source = keywords
            self.prepared = keywords.compactMap { keyword in
                let value = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        let words = self.prepared
        self.lock.unlock()
        for word in words {
            if text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return true
            }
        }
        return false
    }
}
