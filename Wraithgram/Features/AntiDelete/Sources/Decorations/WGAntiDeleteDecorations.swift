import Foundation
import UIKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import AccountContext
import WGCore
import WGHooks
import WGFeaturesShared

/// `WGMessageDecorationHooks.decorations`: computed once per message version (the point caches it)
/// for every cell type. Everything comes from the message's own attributes and the settings
/// snapshot; a message without Wraithgram attributes costs one pass over its attribute list.
enum WGAntiDeleteDecorations {
    static func decorate(_ decoration: inout WGMessageDecoration, _ context: WGMessageDecorationContext) {
        let message = context.message
        var hasLocalAttributes = false
        for attribute in message.attributes where attribute is WGAntiDeleteLocalAttribute {
            hasLocalAttributes = true
            break
        }
        if !hasLocalAttributes {
            return
        }
        let state = WGAntiDeleteMessageState(attributes: message.attributes)
        var prefix = ""

        if state.deleted != nil {
            decoration.alpha = min(decoration.alpha, WGAntiDeleteSettings.alpha(forTransparency: WGAntiDeleteSettings.transparency.value))
            prefix += WGAntiDeleteDecorations.deletedMark
            WGAntiDeleteReplyQuote.remember(message, context: context.context)
        }
        if let history = state.history {
            prefix += WGAntiDeleteDecorations.historyMark(versionCount: history.versions.count)
            if WGAntiDeleteSettings.editHistoryInline.value {
                wgApplyEditHistoryFootnote(&decoration, history: history, context: context.context)
            }
        }
        if state.bookmark != nil && WGBookmarkSettings.enabled.value {
            prefix += "🔖 "
        }
        if !prefix.isEmpty {
            // Appended to what other features put there (the point's contract), never replaced.
            decoration.statusPrefix = (decoration.statusPrefix ?? "") + prefix
        }
        if let localEdit = state.localEdit {
            decoration.textOverride = WGMessageTextOverride(text: localEdit.text, entities: localEdit.entities)
        }
    }

    /// Status-line marks; the menu preview shows the same ones. Deleted = a flat trash icon before
    /// the time (`WGStatusIcon`), not an emoji.
    static let deletedMark = String(WGStatusIcon.deleted.rawValue)

    static func historyMark(versionCount: Int) -> String {
        return "✎\(versionCount) "
    }

    /// The previous versions as text: «12:30 — text», oldest first.
    static func versionsText(_ history: WGEditHistoryMessageAttribute, presentationData: PresentationData) -> (text: String, entities: [MessageTextEntity]) {
        var text = ""
        var entities: [MessageTextEntity] = []
        for version in history.versions {
            if !text.isEmpty {
                text += "\n"
            }
            let time = stringForMediumDate(timestamp: version.date, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
            let start = (text as NSString).length
            text += time
            entities.append(MessageTextEntity(range: start ..< (text as NSString).length, type: .Italic))
            text += " — "
            var body = version.text
            if body.isEmpty, let media = version.mediaDescription {
                body = wgAntiDeleteMediaTitle(media)
            }
            let bodyStart = (text as NSString).length
            text += body
            for entity in version.entities {
                if case .BlockQuote = entity.type {
                    continue
                }
                let lower = entity.range.lowerBound + bodyStart
                let upper = entity.range.upperBound + bodyStart
                if upper <= (text as NSString).length {
                    entities.append(MessageTextEntity(range: lower ..< upper, type: entity.type))
                }
            }
        }
        return (text, entities)
    }
}
