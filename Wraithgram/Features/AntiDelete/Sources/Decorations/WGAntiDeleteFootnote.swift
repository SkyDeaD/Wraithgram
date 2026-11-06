import Foundation
import UIKit
import TelegramCore
import AccountContext
import WGHooks
import WGFeaturesShared

/// «Показывать прежние версии под текстом»: the versions go into their own node under the text
/// of the bubble (`WGMessageDecoration.footnote`), so they are neither selected nor copied with
/// the message text and keep their own transparency.
/// Drawn by ChatMessageTextBubbleContentNode (`WGMessageFootnote`, `WGMessageDecoration.footnote`).
func wgApplyEditHistoryFootnote(_ decoration: inout WGMessageDecoration, history: WGEditHistoryMessageAttribute, context: AccountContext) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let value = WGAntiDeleteDecorations.versionsText(history, presentationData: presentationData)
    if value.text.isEmpty {
        return
    }
    let alpha = WGAntiDeleteSettings.alpha(forTransparency: WGAntiDeleteSettings.versionsTransparency.value)
    decoration.footnote = WGMessageFootnote(text: value.text, entities: value.entities, alpha: alpha)
}
