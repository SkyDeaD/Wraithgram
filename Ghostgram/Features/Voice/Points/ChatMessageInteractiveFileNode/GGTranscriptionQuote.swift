import Foundation
import UIKit
import TelegramCore
import AccountContext
import TextFormat
import LocalizedPeerData
import ChatControllerInteraction
import ChatPresentationInterfaceState

// Compiled into ChatMessageInteractiveFileNode (filegroup
// //Ghostgram/Features/Voice:ChatMessageInteractiveFileNodeSources), owner W3-1.

/// Inserts the selected words of a transcription into the chat's input field as a block quote with the
/// author's name. The source is explicit (the transcription's own selection), so a caption on the voice
/// message can never turn this into a reply quote of the caption. A reply quote is not used at all: the
/// server only accepts quotes of the message text, and a transcription is not the message text.
func ggInsertTranscriptionQuote(controllerInteraction: ChatControllerInteraction, message: EngineRawMessage, text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return
    }
    var quoted = trimmed
    if let author = message.author {
        quoted = EnginePeer(author).compactDisplayTitle + ":\n" + trimmed
    }
    let quote = NSMutableAttributedString(string: quoted, attributes: [ChatTextInputAttributes.block: ChatTextInputTextQuoteAttribute(kind: .quote, isCollapsed: false)])
    if let author = message.author {
        let nameLength = (EnginePeer(author).compactDisplayTitle as NSString).length
        quote.addAttribute(ChatTextInputAttributes.bold, value: true as NSNumber, range: NSRange(location: 0, length: nameLength))
    }
    let insertion = NSMutableAttributedString(attributedString: quote)
    insertion.append(NSAttributedString(string: "\n"))
    controllerInteraction.updateInputState { state in
        let selection = state.selectionRange
        return state.replacingFlatRange(NSRange(location: selection.lowerBound, length: selection.count), with: insertion)
    }
    controllerInteraction.updateInputMode { _ in
        return .text
    }
}
