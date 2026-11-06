import Foundation
import WGCore

/// What the notification service hands to the app: it marks the messages in the shared Postbox
/// itself, but the index is the app's job (`WGSharedInbox("antiDelete.index")`). The first byte
/// is the format version.
public struct WGAntiDeleteInboxRecord: Equatable {
    public enum Kind: UInt8 {
        /// Entries for the deleted log.
        case deleted = 0
        /// Entries for the edited log.
        case edited = 1
    }

    private static let formatVersion: UInt8 = 1

    public var account: WGAccountID
    public var kind: Kind
    public var peer: WGPeerKey
    public var entries: [WGAntiDeleteLogEntry]

    public init(account: WGAccountID, kind: Kind, peer: WGPeerKey, entries: [WGAntiDeleteLogEntry]) {
        self.account = account
        self.kind = kind
        self.peer = peer
        self.entries = entries
    }

    public func encode() -> Data {
        var writer = WGBinaryWriter()
        writer.writeUInt8(WGAntiDeleteInboxRecord.formatVersion)
        writer.writeInt64(self.account.rawValue)
        writer.writeUInt8(self.kind.rawValue)
        writer.writeInt32(self.peer.namespace)
        writer.writeInt64(self.peer.id)
        let log = WGAntiDeletePeerLog(entries: self.entries)
        var data = writer.data
        data.append(log.encode())
        return data
    }

    public init?(data: Data) {
        var reader = WGBinaryReader(data)
        guard let version = reader.readUInt8(), version == WGAntiDeleteInboxRecord.formatVersion else {
            return nil
        }
        guard let account = reader.readInt64(), let kindValue = reader.readUInt8(), let kind = Kind(rawValue: kindValue) else {
            return nil
        }
        guard let peerNamespace = reader.readInt32(), let peerId = reader.readInt64(), let peer = WGPeerKey(namespace: peerNamespace, id: peerId) else {
            return nil
        }
        // version (1) + account (8) + kind (1) + peer (12)
        let headerLength = 1 + 8 + 1 + 4 + 8
        if data.count < headerLength {
            return nil
        }
        guard let log = WGAntiDeletePeerLog(data: data.subdata(in: data.startIndex + headerLength ..< data.endIndex)) else {
            return nil
        }
        self.init(account: WGAccountID(rawValue: account), kind: kind, peer: peer, entries: log.entries)
    }
}
