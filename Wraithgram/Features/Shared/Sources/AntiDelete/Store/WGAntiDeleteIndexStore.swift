import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import WGCore

/// The anti-delete index inside the account's own Postbox (ItemCache): encrypted like the rest of
/// the account, removed together with it, readable reactively through `combinedView`.
/// Collection ids 120–124 belong to Wraithgram (upstream uses 0…59, `Namespaces.CachedItemCollection`).
public enum WGAntiDeleteIndexStore {
    static let deletedLogsCollection: Int8 = 120
    static let editedLogsCollection: Int8 = 121
    static let bookmarksCollection: Int8 = 122
    static let archivedCollection: Int8 = 123
    static let summariesCollection: Int8 = 124

    private static func logsCollection(_ kind: WGAntiDeleteLogKind) -> Int8 {
        switch kind {
        case .deleted:
            return WGAntiDeleteIndexStore.deletedLogsCollection
        case .edited:
            return WGAntiDeleteIndexStore.editedLogsCollection
        }
    }

    private static func peerKey(_ peerId: PeerId) -> ValueBoxKey {
        let key = peerId.wgKey
        let result = ValueBoxKey(length: 4 + 8)
        result.setInt32(0, value: key.namespace)
        result.setInt64(4, value: key.id)
        return result
    }

    private static func messageKey(_ id: MessageId) -> ValueBoxKey {
        let key = id.peerId.wgKey
        let result = ValueBoxKey(length: 4 + 8 + 4 + 4)
        result.setInt32(0, value: key.namespace)
        result.setInt64(4, value: key.id)
        result.setInt32(12, value: id.namespace)
        result.setInt32(16, value: id.id)
        return result
    }

    private static func singleKey(_ value: UInt8) -> ValueBoxKey {
        let result = ValueBoxKey(length: 1)
        result.setUInt8(0, value: value)
        return result
    }

    // MARK: Entry ids (also the keys of reactive views)

    public static func logEntryId(kind: WGAntiDeleteLogKind, peerId: PeerId) -> ItemCacheEntryId {
        return ItemCacheEntryId(collectionId: WGAntiDeleteIndexStore.logsCollection(kind), key: WGAntiDeleteIndexStore.peerKey(peerId))
    }

    public static func summaryEntryId(kind: WGAntiDeleteLogKind) -> ItemCacheEntryId {
        return ItemCacheEntryId(collectionId: WGAntiDeleteIndexStore.summariesCollection, key: WGAntiDeleteIndexStore.singleKey(kind.rawValue))
    }

    public static var bookmarksEntryId: ItemCacheEntryId {
        return ItemCacheEntryId(collectionId: WGAntiDeleteIndexStore.bookmarksCollection, key: WGAntiDeleteIndexStore.singleKey(0))
    }

    public static func archivedEntryId(_ id: MessageId) -> ItemCacheEntryId {
        return ItemCacheEntryId(collectionId: WGAntiDeleteIndexStore.archivedCollection, key: WGAntiDeleteIndexStore.messageKey(id))
    }

    // MARK: Read / write (inside a transaction)

    public static func readLog(_ transaction: Transaction, kind: WGAntiDeleteLogKind, peerId: PeerId) -> WGAntiDeletePeerLog {
        guard let entry = transaction.retrieveItemCacheEntry(id: WGAntiDeleteIndexStore.logEntryId(kind: kind, peerId: peerId)) else {
            return WGAntiDeletePeerLog()
        }
        return WGAntiDeletePeerLog(data: entry.data) ?? WGAntiDeletePeerLog()
    }

    static func writeLog(_ transaction: Transaction, kind: WGAntiDeleteLogKind, peerId: PeerId, log: WGAntiDeletePeerLog) {
        let id = WGAntiDeleteIndexStore.logEntryId(kind: kind, peerId: peerId)
        if log.isEmpty {
            transaction.removeItemCacheEntry(id: id)
        } else {
            transaction.putItemCacheEntry(id: id, entry: CodableEntry(data: log.encode()))
        }
    }

    public static func readSummary(_ transaction: Transaction, kind: WGAntiDeleteLogKind) -> WGAntiDeleteSummary {
        guard let entry = transaction.retrieveItemCacheEntry(id: WGAntiDeleteIndexStore.summaryEntryId(kind: kind)) else {
            return WGAntiDeleteSummary()
        }
        return WGAntiDeleteSummary(data: entry.data) ?? WGAntiDeleteSummary()
    }

    static func writeSummary(_ transaction: Transaction, kind: WGAntiDeleteLogKind, summary: WGAntiDeleteSummary) {
        let id = WGAntiDeleteIndexStore.summaryEntryId(kind: kind)
        if summary.peers.isEmpty {
            transaction.removeItemCacheEntry(id: id)
        } else {
            transaction.putItemCacheEntry(id: id, entry: CodableEntry(data: summary.encode()))
        }
    }

    public static func readBookmarks(_ transaction: Transaction) -> WGBookmarkList {
        guard let entry = transaction.retrieveItemCacheEntry(id: WGAntiDeleteIndexStore.bookmarksEntryId) else {
            return WGBookmarkList()
        }
        return WGBookmarkList(data: entry.data) ?? WGBookmarkList()
    }

    static func writeBookmarks(_ transaction: Transaction, list: WGBookmarkList) {
        if list.isEmpty {
            transaction.removeItemCacheEntry(id: WGAntiDeleteIndexStore.bookmarksEntryId)
        } else {
            transaction.putItemCacheEntry(id: WGAntiDeleteIndexStore.bookmarksEntryId, entry: CodableEntry(data: list.encode()))
        }
    }

    /// Bookmarks the list's cap pushed out lose their mark on the message too: a «🔖» that no list
    /// shows would be a bookmark the user can not find.
    static func deactivateBookmarks(_ transaction: Transaction, _ entries: [WGBookmarkEntry], now: Int32) {
        for entry in entries {
            transaction.updateMessage(MessageId(wgKey: entry.message), update: { current in
                let isActive = current.attributes.contains(where: { attribute in
                    return (attribute as? WGBookmarkMessageAttribute)?.isActive == true
                })
                if !isActive {
                    return .skip
                }
                return .update(wgStoreMessage(current, attributes: wgReplacingAttribute(current.attributes, with: WGBookmarkMessageAttribute(title: "", createdAt: now, isActive: false))))
            })
        }
    }

    public static func readArchived(_ transaction: Transaction, id: MessageId) -> WGAntiDeleteArchivedContent? {
        guard let entry = transaction.retrieveItemCacheEntry(id: WGAntiDeleteIndexStore.archivedEntryId(id)) else {
            return nil
        }
        return WGAntiDeleteArchivedContent(data: entry.data)
    }

    static func writeArchived(_ transaction: Transaction, id: MessageId, content: WGAntiDeleteArchivedContent?) {
        let entryId = WGAntiDeleteIndexStore.archivedEntryId(id)
        if let content {
            transaction.putItemCacheEntry(id: entryId, entry: CodableEntry(data: content.encode()))
        } else {
            transaction.removeItemCacheEntry(id: entryId)
        }
    }

    /// Adds entries of one chat and updates the summary. Returns the new summary and what the cap
    /// pushed out (their messages are deleted for real by the caller: nothing lists them anymore).
    @discardableResult
    static func apply(_ transaction: Transaction, kind: WGAntiDeleteLogKind, peerId: PeerId, entries: [WGAntiDeleteLogEntry], summary: inout WGAntiDeleteSummary) -> [WGAntiDeleteLogEntry] {
        var log = WGAntiDeleteIndexStore.readLog(transaction, kind: kind, peerId: peerId)
        let dropped = log.upsert(entries)
        WGAntiDeleteIndexStore.writeLog(transaction, kind: kind, peerId: peerId, log: log)
        summary.update(peer: peerId.wgKey, log: log)
        return dropped
    }

    /// Removes entries of one chat and updates the summary.
    static func remove(_ transaction: Transaction, kind: WGAntiDeleteLogKind, peerId: PeerId, refs: Set<WGAntiDeleteMessageRef>, summary: inout WGAntiDeleteSummary) {
        if refs.isEmpty {
            return
        }
        var log = WGAntiDeleteIndexStore.readLog(transaction, kind: kind, peerId: peerId)
        if log.remove(refs) == 0 {
            return
        }
        WGAntiDeleteIndexStore.writeLog(transaction, kind: kind, peerId: peerId, log: log)
        summary.update(peer: peerId.wgKey, log: log)
    }

    // MARK: Reactive reads (UI)

    public static func summarySignal(postbox: Postbox, kind: WGAntiDeleteLogKind) -> Signal<WGAntiDeleteSummary, NoError> {
        let key = PostboxViewKey.cachedItem(WGAntiDeleteIndexStore.summaryEntryId(kind: kind))
        return postbox.combinedView(keys: [key])
        |> map { views -> WGAntiDeleteSummary in
            guard let view = views.views[key] as? CachedItemView, let value = view.value else {
                return WGAntiDeleteSummary()
            }
            return WGAntiDeleteSummary(data: value.data) ?? WGAntiDeleteSummary()
        }
        |> distinctUntilChanged
    }

    public static func logSignal(postbox: Postbox, kind: WGAntiDeleteLogKind, peerId: PeerId) -> Signal<WGAntiDeletePeerLog, NoError> {
        let key = PostboxViewKey.cachedItem(WGAntiDeleteIndexStore.logEntryId(kind: kind, peerId: peerId))
        return postbox.combinedView(keys: [key])
        |> map { views -> WGAntiDeletePeerLog in
            guard let view = views.views[key] as? CachedItemView, let value = view.value else {
                return WGAntiDeletePeerLog()
            }
            return WGAntiDeletePeerLog(data: value.data) ?? WGAntiDeletePeerLog()
        }
        |> distinctUntilChanged
    }

    public static func bookmarksSignal(postbox: Postbox) -> Signal<WGBookmarkList, NoError> {
        let key = PostboxViewKey.cachedItem(WGAntiDeleteIndexStore.bookmarksEntryId)
        return postbox.combinedView(keys: [key])
        |> map { views -> WGBookmarkList in
            guard let view = views.views[key] as? CachedItemView, let value = view.value else {
                return WGBookmarkList()
            }
            return WGBookmarkList(data: value.data) ?? WGBookmarkList()
        }
        |> distinctUntilChanged
    }
}
