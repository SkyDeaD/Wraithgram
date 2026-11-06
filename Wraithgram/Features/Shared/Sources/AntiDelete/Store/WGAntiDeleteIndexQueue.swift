import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import WGCore

/// Index work collected inside Postbox transactions and done after them.
/// - App: batches are applied to the account's own Postbox in a separate transaction on the
///   anti-delete queue, coalesced for 0.2 s (a deletion burst becomes one write per chat).
/// - Extensions: the records go to the app through `WGSharedInbox("antiDelete.index")`; the
///   message itself is already marked in the shared Postbox.
public final class WGAntiDeleteIndexQueue {
    public static let shared = WGAntiDeleteIndexQueue()

    static let inboxName = "antiDelete.index"

    struct Batch {
        let kind: WGAntiDeleteInboxRecord.Kind
        let peerId: PeerId
        let entries: [WGAntiDeleteLogEntry]
    }

    private let lock = NSLock()
    private var pending: [AccountRecordId: [Batch]] = [:]
    private var isFlushScheduled = false
    private var pendingInboxRecords: [Data] = []
    private var isInboxAppendScheduled = false

    private init() {
    }

    private var isExtension: Bool {
        if let process = WGCore.environment?.process {
            return !process.isApp
        }
        return false
    }

    /// From a transaction handler: only memory work here.
    func enqueue(account: AccountRecordId?, kind: WGAntiDeleteInboxRecord.Kind, peerId: PeerId, entries: [WGAntiDeleteLogEntry]) {
        guard let account else {
            WGLog.warning("antiDelete", "index entries without an account dropped")
            return
        }
        if entries.isEmpty {
            return
        }
        if self.isExtension {
            let record = WGAntiDeleteInboxRecord(account: account.wg, kind: kind, peer: peerId.wgKey, entries: entries)
            self.lock.lock()
            self.pendingInboxRecords.append(record.encode())
            let schedule = !self.isInboxAppendScheduled
            self.isInboxAppendScheduled = true
            self.lock.unlock()
            if schedule {
                // Not from inside the transaction: the file is written on our own queue.
                WGAntiDeleteAccounts.shared.queue.justDispatch { [weak self] in
                    self?.appendInboxRecords()
                }
            }
            return
        }
        if kind == .deleted {
            WGAntiDeleteAccounts.shared.noteKept(account: account, peerId: peerId)
        }
        self.lock.lock()
        self.pending[account, default: []].append(Batch(kind: kind, peerId: peerId, entries: entries))
        let schedule = !self.isFlushScheduled
        self.isFlushScheduled = true
        self.lock.unlock()
        if schedule {
            WGAntiDeleteAccounts.shared.queue.after(0.2, { [weak self] in
                self?.flush()
            })
        }
    }

    private func appendInboxRecords() {
        self.lock.lock()
        let records = self.pendingInboxRecords
        self.pendingInboxRecords = []
        self.isInboxAppendScheduled = false
        self.lock.unlock()
        if records.isEmpty {
            return
        }
        let inbox = WGSharedInbox(name: WGAntiDeleteIndexQueue.inboxName)
        for record in records {
            inbox.append(record)
        }
    }

    private func flush() {
        self.lock.lock()
        let pending = self.pending
        self.pending = [:]
        self.isFlushScheduled = false
        self.lock.unlock()
        for (account, batches) in pending {
            self.apply(account: account, batches: batches)
        }
    }

    /// Applies batches to one account (anti-delete queue).
    func apply(account: AccountRecordId, batches: [Batch]) {
        guard let postbox = WGAntiDeleteAccounts.shared.postbox(for: account) else {
            WGLog.warning("antiDelete", "index batch for an account that is not running dropped")
            return
        }
        let _ = (postbox.transaction { transaction -> ([WGAntiDeleteLogKind: WGAntiDeleteSummary], [PeerId: [WGAntiDeleteLogEntry]]) in
            var summaries: [WGAntiDeleteLogKind: WGAntiDeleteSummary] = [:]
            var deletedByPeer: [PeerId: [WGAntiDeleteLogEntry]] = [:]
            var dropped: [MessageId] = []
            for batch in batches {
                let kind: WGAntiDeleteLogKind = batch.kind == .deleted ? .deleted : .edited
                var summary = summaries[kind] ?? WGAntiDeleteIndexStore.readSummary(transaction, kind: kind)
                let pushedOut = WGAntiDeleteIndexStore.apply(transaction, kind: kind, peerId: batch.peerId, entries: batch.entries, summary: &summary)
                summaries[kind] = summary
                if kind == .deleted {
                    deletedByPeer[batch.peerId, default: []].append(contentsOf: batch.entries)
                    for entry in pushedOut where !entry.isArchiveOnly {
                        dropped.append(MessageId(peerId: batch.peerId, namespace: entry.namespace, id: entry.id))
                    }
                } else {
                    for entry in pushedOut {
                        wgClearEditHistory(transaction, id: MessageId(peerId: batch.peerId, namespace: entry.namespace, id: entry.id))
                    }
                }
            }
            for (kind, summary) in summaries {
                WGAntiDeleteIndexStore.writeSummary(transaction, kind: kind, summary: summary)
            }
            if !dropped.isEmpty {
                // Over the per-chat cap: nothing lists them any more, so they go for real.
                wgDeleteKeptMessages(transaction, postbox: postbox, ids: dropped)
            }
            return (summaries, deletedByPeer)
        }
        |> map { summaries, deletedByPeer -> [PeerId: [WGAntiDeleteLogEntry]] in
            // On the Postbox queue, in transaction order: a later operation never sees an older summary.
            WGAntiDeleteAccounts.shared.updateSummaries(account: account, summaries, flushedPeers: Set(batches.map(\.peerId)))
            return deletedByPeer
        }
        |> deliverOn(WGAntiDeleteAccounts.shared.queue)).start(next: { deletedByPeer in
            if let basePath = WGAntiDeleteAccounts.shared.basePath(for: account) {
                for (peerId, entries) in deletedByPeer {
                    WGAntiDeleteMediaArchive.archive(postbox: postbox, basePath: basePath, peerId: peerId, entries: entries)
                }
            }
        })
    }

    /// App: takes what the notification service left in the inbox (anti-delete queue, never main).
    public func drainInbox(completion: @escaping () -> Void) {
        WGAntiDeleteAccounts.shared.queue.justDispatch { [weak self] in
            guard let self else {
                completion()
                return
            }
            let records = WGSharedInbox(name: WGAntiDeleteIndexQueue.inboxName).drain()
            var batches: [AccountRecordId: [Batch]] = [:]
            for data in records {
                guard let record = WGAntiDeleteInboxRecord(data: data) else {
                    WGLog.warning("antiDelete", "damaged inbox record skipped")
                    continue
                }
                batches[AccountRecordId(wg: record.account), default: []].append(Batch(kind: record.kind, peerId: PeerId(wgKey: record.peer), entries: record.entries))
            }
            for (account, accountBatches) in batches {
                if WGAntiDeleteAccounts.shared.postbox(for: account) == nil {
                    // The account is not running now: keep its records for the next drain.
                    let inbox = WGSharedInbox(name: WGAntiDeleteIndexQueue.inboxName)
                    for batch in accountBatches {
                        inbox.append(WGAntiDeleteInboxRecord(account: account.wg, kind: batch.kind, peer: batch.peerId.wgKey, entries: batch.entries).encode())
                    }
                    continue
                }
                self.apply(account: account, batches: accountBatches)
            }
            completion()
        }
    }
}

// MARK: - Postbox helpers shared by the queue, the menus and the maintenance tasks

/// Marks every message of a chat as deleted (a secret chat the other side cleared). Returns the
/// new index entries.
func wgMarkWholeChatDeleted(_ transaction: Transaction, peerId: PeerId) -> [WGAntiDeleteLogEntry] {
    let now = Int32(Date().timeIntervalSince1970)
    var entries: [WGAntiDeleteLogEntry] = []
    transaction.withAllMessages(peerId: peerId, { message in
        if !message.wgIsDeleted {
            entries.append(WGAntiDeleteLogEntry(namespace: message.id.namespace, id: message.id.id, threadId: message.threadId, time: now, source: WGAntiDeleteSource.secretChat.rawValue, isOutgoing: !message.flags.contains(.Incoming)))
        }
        return true
    })
    for entry in entries {
        transaction.updateMessage(MessageId(peerId: peerId, namespace: entry.namespace, id: entry.id), update: { message in
            let attributes = wgReplacingAttribute(message.attributes, with: WGDeletedMessageAttribute(deletedAt: now, source: .secretChat))
            return .update(wgStoreMessage(message, attributes: attributes))
        })
    }
    return entries
}

/// Clears the saved versions of a message (tombstone: they must not come back with the next
/// storage of the message).
func wgClearEditHistory(_ transaction: Transaction, id: MessageId) {
    transaction.updateMessage(id, update: { message in
        guard message.attributes.contains(where: { ($0 as? WGEditHistoryMessageAttribute)?.versions.isEmpty == false }) else {
            return .skip
        }
        let attributes = wgReplacingAttribute(message.attributes, with: WGEditHistoryMessageAttribute(versions: []))
        return .update(wgStoreMessage(message, attributes: attributes))
    })
}

/// Deletes messages kept by anti-delete for real (cap, age limit, «Очистить», «Удалить у себя»):
/// local only, nothing is sent. Media copies of the archive are removed by the caller.
func wgDeleteKeptMessages(_ transaction: Transaction, postbox: Postbox, ids: [MessageId]) {
    if ids.isEmpty {
        return
    }
    var archived: [(messageId: MessageId, resourceIds: [MediaResourceId])] = []
    let basePath = WGAntiDeleteAccounts.shared.basePath(forPostbox: postbox)
    if basePath != nil {
        for id in ids {
            if let message = transaction.getMessage(id) {
                let resourceIds = WGAntiDeleteMediaArchive.resources(of: message).map { $0.resource.id }
                if !resourceIds.isEmpty {
                    archived.append((id, resourceIds))
                }
            }
        }
    }
    _internal_deleteMessages(transaction: transaction, mediaBox: postbox.mediaBox, ids: ids, deleteMedia: true, manualAddMessageThreadStatsDifference: nil)
    if let basePath, !archived.isEmpty {
        // Files are touched outside the transaction, on the anti-delete queue.
        WGAntiDeleteAccounts.shared.queue.justDispatch {
            WGAntiDeleteMediaArchive.remove(basePath: basePath, items: archived)
        }
    }
}

/// The stored form of `message` with other attributes.
func wgStoreMessage(_ message: Message, attributes: [MessageAttribute]) -> StoreMessage {
    var storeForwardInfo: StoreMessageForwardInfo?
    if let forwardInfo = message.forwardInfo {
        storeForwardInfo = StoreMessageForwardInfo(forwardInfo)
    }
    return StoreMessage(id: message.id, customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: StoreMessageFlags(message.flags), tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: storeForwardInfo, authorId: message.author?.id, text: message.text, attributes: attributes, media: message.media)
}
