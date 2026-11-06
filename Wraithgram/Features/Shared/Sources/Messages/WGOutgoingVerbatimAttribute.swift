import Foundation
import Postbox
import TelegramCore

/// Marks an outgoing message whose text must be sent exactly as built: the copy that replaces a
/// forward from a protected chat, service sends. The text stages of the outgoing pipeline skip such
/// messages, and WGMessages removes the marker in `WGOutgoingHooks.messages` before the message is
/// stored. It is still declared encodable (app and extensions) in case a path stores it first.
public final class WGOutgoingVerbatimAttribute: MessageAttribute {
    public init() {
    }

    public required init(decoder: PostboxDecoder) {
    }

    public func encode(_ encoder: PostboxEncoder) {
    }

    public static func isPresent(in attributes: [MessageAttribute]) -> Bool {
        for attribute in attributes {
            if attribute is WGOutgoingVerbatimAttribute {
                return true
            }
        }
        return false
    }
}

/// Marks an outgoing sound (voice, music, round video) that came from an inline bot and is sent
/// without «via»: the upload sends the file as a new document instead of by the bot's reference
/// (`WGOutgoingHooks.reuploadsCloudFile`), the way the old client did — sent by reference, such a
/// message never went out. Stored with the message, so a retry uploads it the same way.
public final class WGInlineReuploadAttribute: MessageAttribute {
    public init() {
    }

    public required init(decoder: PostboxDecoder) {
    }

    public func encode(_ encoder: PostboxEncoder) {
    }

    public static func isPresent(in attributes: [MessageAttribute]) -> Bool {
        for attribute in attributes {
            if attribute is WGInlineReuploadAttribute {
                return true
            }
        }
        return false
    }
}

func wgDeclareMessagesEncodables() {
    declareEncodable(WGOutgoingVerbatimAttribute.self, f: { WGOutgoingVerbatimAttribute(decoder: $0) })
    declareEncodable(WGInlineReuploadAttribute.self, f: { WGInlineReuploadAttribute(decoder: $0) })
}
