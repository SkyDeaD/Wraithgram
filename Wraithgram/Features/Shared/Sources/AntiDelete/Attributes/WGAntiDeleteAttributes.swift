import Foundation
import Postbox
import TelegramCore
import WGCore

// Local message attributes in the account's Postbox — the single source of truth for «deleted»,
// previous versions, the local edit, the bookmark and previous reactions. They never leave the
// device (Telegram does not send local attributes anywhere) and live in the encrypted database
// together with the message, so secret chat content is not copied anywhere else.
//
// Removing one of them is done by writing an inactive instance (a tombstone): when the server
// stores the message again, the local attributes of the previous version are carried over, and
// a removed attribute must not come back that way.

/// Marker of the Wraithgram attributes that are carried over when a message is stored again.
public protocol WGAntiDeleteLocalAttribute: MessageAttribute {
}

private func wgEncodePeerId(_ peerId: PeerId, encoder: PostboxEncoder, prefix: String) {
    let key = peerId.wgKey
    encoder.encodeInt32(key.namespace, forKey: prefix + "n")
    encoder.encodeInt64(key.id, forKey: prefix + "i")
}

private func wgDecodePeerId(decoder: PostboxDecoder, prefix: String) -> PeerId? {
    guard let id = decoder.decodeOptionalInt64ForKey(prefix + "i") else {
        return nil
    }
    let namespace = decoder.decodeInt32ForKey(prefix + "n", orElse: 0)
    guard let key = WGPeerKey(namespace: namespace, id: id) else {
        return nil
    }
    return PeerId(wgKey: key)
}

// MARK: - Deleted

public final class WGDeletedMessageAttribute: WGAntiDeleteLocalAttribute, Equatable {
    public let deletedAt: Int32
    public let source: WGAntiDeleteSource

    public init(deletedAt: Int32, source: WGAntiDeleteSource) {
        self.deletedAt = deletedAt
        self.source = source
    }

    public init(decoder: PostboxDecoder) {
        self.deletedAt = decoder.decodeInt32ForKey("d", orElse: 0)
        self.source = WGAntiDeleteSource(rawValue: UInt8(clamping: decoder.decodeInt32ForKey("s", orElse: 0))) ?? .remote
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.deletedAt, forKey: "d")
        encoder.encodeInt32(Int32(self.source.rawValue), forKey: "s")
    }

    public static func ==(lhs: WGDeletedMessageAttribute, rhs: WGDeletedMessageAttribute) -> Bool {
        return lhs.deletedAt == rhs.deletedAt && lhs.source == rhs.source
    }
}

// MARK: - Edit history

/// One previous version of a message: its text with formatting and the date it was created
/// (the server's edit date of that version, or the message date for the first one).
public struct WGEditVersion: PostboxCoding, Equatable {
    public let text: String
    public let entities: [MessageTextEntity]
    public let date: Int32
    /// Short description of the media the version had («Фото», file name) when it differed.
    public let mediaDescription: String?

    public init(text: String, entities: [MessageTextEntity], date: Int32, mediaDescription: String?) {
        self.text = text
        self.entities = entities
        self.date = date
        self.mediaDescription = mediaDescription
    }

    public init(decoder: PostboxDecoder) {
        self.text = decoder.decodeStringForKey("t", orElse: "")
        self.entities = decoder.decodeObjectArrayWithDecoderForKey("e")
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
        self.mediaDescription = decoder.decodeOptionalStringForKey("m")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.text, forKey: "t")
        encoder.encodeObjectArray(self.entities, forKey: "e")
        encoder.encodeInt32(self.date, forKey: "d")
        if let mediaDescription = self.mediaDescription {
            encoder.encodeString(mediaDescription, forKey: "m")
        } else {
            encoder.encodeNil(forKey: "m")
        }
    }
}

public final class WGEditHistoryMessageAttribute: WGAntiDeleteLocalAttribute, Equatable {
    /// Versions kept per message; the oldest go first (a ticker bot edits forever).
    public static let maximumVersions = 30

    /// Oldest first. Empty = history cleared (tombstone).
    public let versions: [WGEditVersion]

    public init(versions: [WGEditVersion]) {
        if versions.count > WGEditHistoryMessageAttribute.maximumVersions {
            self.versions = Array(versions.suffix(WGEditHistoryMessageAttribute.maximumVersions))
        } else {
            self.versions = versions
        }
    }

    public init(decoder: PostboxDecoder) {
        self.versions = decoder.decodeObjectArrayWithDecoderForKey("v")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeObjectArray(self.versions, forKey: "v")
    }

    public var associatedMediaIds: [MediaId] {
        var result: [MediaId] = []
        for version in self.versions {
            for entity in version.entities {
                if case let .CustomEmoji(_, fileId) = entity.type {
                    result.append(MediaId(namespace: Namespaces.Media.CloudFile, id: fileId))
                }
            }
        }
        return result
    }

    public static func ==(lhs: WGEditHistoryMessageAttribute, rhs: WGEditHistoryMessageAttribute) -> Bool {
        return lhs.versions == rhs.versions
    }
}

// MARK: - Local edit

public final class WGLocalEditMessageAttribute: WGAntiDeleteLocalAttribute, Equatable {
    public let text: String
    public let entities: [MessageTextEntity]
    public let date: Int32
    /// false = the local edit was reset (tombstone).
    public let isActive: Bool

    public init(text: String, entities: [MessageTextEntity], date: Int32, isActive: Bool) {
        self.text = text
        self.entities = entities
        self.date = date
        self.isActive = isActive
    }

    public init(decoder: PostboxDecoder) {
        self.text = decoder.decodeStringForKey("t", orElse: "")
        self.entities = decoder.decodeObjectArrayWithDecoderForKey("e")
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
        self.isActive = decoder.decodeBoolForKey("a", orElse: false)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.text, forKey: "t")
        encoder.encodeObjectArray(self.entities, forKey: "e")
        encoder.encodeInt32(self.date, forKey: "d")
        encoder.encodeBool(self.isActive, forKey: "a")
    }

    public static func ==(lhs: WGLocalEditMessageAttribute, rhs: WGLocalEditMessageAttribute) -> Bool {
        return lhs.text == rhs.text && lhs.entities == rhs.entities && lhs.date == rhs.date && lhs.isActive == rhs.isActive
    }
}

// MARK: - Bookmark

public final class WGBookmarkMessageAttribute: WGAntiDeleteLocalAttribute, Equatable {
    public let title: String
    public let createdAt: Int32
    /// false = the bookmark was removed (tombstone).
    public let isActive: Bool

    public init(title: String, createdAt: Int32, isActive: Bool) {
        self.title = title
        self.createdAt = createdAt
        self.isActive = isActive
    }

    public init(decoder: PostboxDecoder) {
        self.title = decoder.decodeStringForKey("t", orElse: "")
        self.createdAt = decoder.decodeInt32ForKey("c", orElse: 0)
        self.isActive = decoder.decodeBoolForKey("a", orElse: false)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.title, forKey: "t")
        encoder.encodeInt32(self.createdAt, forKey: "c")
        encoder.encodeBool(self.isActive, forKey: "a")
    }

    public static func ==(lhs: WGBookmarkMessageAttribute, rhs: WGBookmarkMessageAttribute) -> Bool {
        return lhs.title == rhs.title && lhs.createdAt == rhs.createdAt && lhs.isActive == rhs.isActive
    }
}

/// The Wraithgram state of a message, read in one pass over its attributes.
public struct WGAntiDeleteMessageState {
    public var deleted: WGDeletedMessageAttribute?
    /// Only a non-empty history.
    public var history: WGEditHistoryMessageAttribute?
    /// Only an active local edit.
    public var localEdit: WGLocalEditMessageAttribute?
    /// Only an active bookmark.
    public var bookmark: WGBookmarkMessageAttribute?

    public init(attributes: [MessageAttribute]) {
        for attribute in attributes {
            guard attribute is WGAntiDeleteLocalAttribute else {
                continue
            }
            if let value = attribute as? WGDeletedMessageAttribute {
                self.deleted = value
            } else if let value = attribute as? WGEditHistoryMessageAttribute {
                self.history = value.versions.isEmpty ? nil : value
            } else if let value = attribute as? WGLocalEditMessageAttribute {
                self.localEdit = value.isActive ? value : nil
            } else if let value = attribute as? WGBookmarkMessageAttribute {
                self.bookmark = value.isActive ? value : nil
            }
        }
    }

    public var isEmpty: Bool {
        return self.deleted == nil && self.history == nil && self.localEdit == nil && self.bookmark == nil
    }
}

public extension Message {
    /// Kept by anti-delete although the server deleted it.
    var wgIsDeleted: Bool {
        return self.attributes.contains(where: { $0 is WGDeletedMessageAttribute })
    }

    /// The text the user sees: the local edit when there is one.
    var wgEffectiveText: (text: String, entities: [MessageTextEntity]) {
        for attribute in self.attributes {
            if let attribute = attribute as? WGLocalEditMessageAttribute, attribute.isActive {
                return (attribute.text, attribute.entities)
            }
        }
        return (self.text, self.textEntitiesAttribute?.entities ?? [])
    }
}

/// `attributes` with `attribute` instead of any attribute of the same type.
public func wgReplacingAttribute<T: MessageAttribute>(_ attributes: [MessageAttribute], with attribute: T) -> [MessageAttribute] {
    var result = attributes.filter { !($0 is T) }
    result.append(attribute)
    return result
}

/// Declared before any Postbox opens, in the app and in the extensions.
func wgDeclareAntiDeleteAttributes() {
    declareEncodable(WGDeletedMessageAttribute.self, f: { WGDeletedMessageAttribute(decoder: $0) })
    declareEncodable(WGEditHistoryMessageAttribute.self, f: { WGEditHistoryMessageAttribute(decoder: $0) })
    declareEncodable(WGLocalEditMessageAttribute.self, f: { WGLocalEditMessageAttribute(decoder: $0) })
    declareEncodable(WGBookmarkMessageAttribute.self, f: { WGBookmarkMessageAttribute(decoder: $0) })
    // «Убранные и заменённые реакции» were removed (owner, 2026-10-27). Their attribute is no longer
    // declared: Postbox skips an attribute of an undeclared type, so messages that carry one read
    // as if they had none.
    // Messages the old Wraithgram kept carry its own attribute, declared as "DeletedMessageAttribute"
    // with {d: deletedAt}. Read it as ours, so they stay kept (in their own account, by their own
    // id — no key matching) and are rewritten in the new form on their next update.
    declareEncodable(typeHash: persistentHash32("DeletedMessageAttribute"), { decoder in
        return WGDeletedMessageAttribute(deletedAt: decoder.decodeInt32ForKey("d", orElse: 0), source: .imported)
    })
}
