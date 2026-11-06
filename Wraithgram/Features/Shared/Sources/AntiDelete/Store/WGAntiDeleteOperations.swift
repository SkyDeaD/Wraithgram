import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import WGCore

/// User actions and maintenance over the kept data of one account. Every function returns a
/// signal that does its Postbox work in transactions sized by chat (never one transaction for
/// everything) and touches files only on the anti-delete queue.
public enum WGAntiDeleteOperations {
    private static func now() -> Int32 {
        return Int32(Date().timeIntervalSince1970)
    }

    /// Runs the signals one after another; completes after the last one.
    private static func sequence(_ signals: [Signal<Void, NoError>]) -> Signal<Never, NoError> {
        var result: Signal<Never, NoError> = .complete()
        for signal in signals {
            result = result |> then(signal |> ignoreValues)
        }
        return result
    }

    /// One value, computed when `work` completes.
    private static func value<T>(after work: Signal<Never, NoError>, _ make: @escaping () -> T) -> Signal<T, NoError> {
        return Signal { subscriber in
            return work.start(completed: {
                subscriber.putNext(make())
                subscriber.putCompletion()
            })
        }
    }

    // MARK: Bookmarks

    /// Sets (`title != nil`) or removes the bookmark of a message.
    public static func setBookmark(postbox: Postbox, accountId: AccountRecordId, messageId: MessageId, title: String?) -> Signal<Never, NoError> {
        let now = WGAntiDeleteOperations.now()
        return postbox.transaction { transaction -> Set<PeerId> in
            guard let message = transaction.getMessage(messageId) else {
                return Set(WGAntiDeleteIndexStore.readBookmarks(transaction).entries.map { PeerId(wgKey: $0.message.peer) })
            }
            let attribute = WGBookmarkMessageAttribute(title: title ?? "", createdAt: now, isActive: title != nil)
            transaction.updateMessage(messageId, update: { current in
                return .update(wgStoreMessage(current, attributes: wgReplacingAttribute(current.attributes, with: attribute)))
            })
            var list = WGAntiDeleteIndexStore.readBookmarks(transaction)
            if let title {
                let evicted = list.set(WGBookmarkEntry(message: messageId.wgKey, threadId: message.threadId, title: title, createdAt: now, messageDate: message.timestamp))
                WGAntiDeleteIndexStore.deactivateBookmarks(transaction, evicted, now: now)
            } else {
                list.remove([messageId.wgKey])
            }
            WGAntiDeleteIndexStore.writeBookmarks(transaction, list: list)
            return Set(list.entries.map { PeerId(wgKey: $0.message.peer) })
        }
        |> map { peers -> Void in
            WGAntiDeleteAccounts.shared.updateBookmarkPeers(account: accountId, peers: peers)
            return Void()
        }
        |> ignoreValues
    }

    /// Removes bookmark entries whose messages are gone (the list screen does it on open).
    public static func reconcileBookmarks(postbox: Postbox, accountId: AccountRecordId) -> Signal<Never, NoError> {
        return postbox.transaction { transaction -> Set<PeerId> in
            var list = WGAntiDeleteIndexStore.readBookmarks(transaction)
            let ids = Set(list.entries.map { MessageId(wgKey: $0.message) })
            let stored = transaction.filterStoredMessageIds(ids)
            let missing = ids.subtracting(stored)
            if !missing.isEmpty {
                list.remove(Set(missing.map(\.wgKey)))
                WGAntiDeleteIndexStore.writeBookmarks(transaction, list: list)
            }
            return Set(list.entries.map { PeerId(wgKey: $0.message.peer) })
        }
        |> map { peers -> Void in
            WGAntiDeleteAccounts.shared.updateBookmarkPeers(account: accountId, peers: peers)
            return Void()
        }
        |> ignoreValues
    }

    // MARK: Local edit

    /// Sets (`text != nil`) or resets the local edit of a message.
    public static func setLocalEdit(postbox: Postbox, messageId: MessageId, text: String?, entities: [MessageTextEntity]) -> Signal<Never, NoError> {
        let now = WGAntiDeleteOperations.now()
        return postbox.transaction { transaction -> Void in
            transaction.updateMessage(messageId, update: { current in
                let attribute = WGLocalEditMessageAttribute(text: text ?? "", entities: text == nil ? [] : entities, date: now, isActive: text != nil)
                return .update(wgStoreMessage(current, attributes: wgReplacingAttribute(current.attributes, with: attribute)))
            })
        }
        |> ignoreValues
    }

    // MARK: Deleted messages

    /// «Удалить у себя»: kept messages go for real (local only) and leave the index.
    public static func deleteKept(postbox: Postbox, accountId: AccountRecordId, messageIds: [MessageId]) -> Signal<Never, NoError> {
        let byPeer = Dictionary(grouping: messageIds, by: { $0.peerId })
        var signals: [Signal<Void, NoError>] = []
        for (peerId, ids) in byPeer {
            signals.append(postbox.transaction { transaction -> [WGAntiDeleteLogKind: WGAntiDeleteSummary] in
                wgDeleteKeptMessages(transaction, postbox: postbox, ids: ids)
                var summaries: [WGAntiDeleteLogKind: WGAntiDeleteSummary] = [:]
                let refs = Set(ids.map { WGAntiDeleteMessageRef(namespace: $0.namespace, id: $0.id) })
                for kind in WGAntiDeleteLogKind.allCases {
                    var summary = WGAntiDeleteIndexStore.readSummary(transaction, kind: kind)
                    WGAntiDeleteIndexStore.remove(transaction, kind: kind, peerId: peerId, refs: refs, summary: &summary)
                    WGAntiDeleteIndexStore.writeSummary(transaction, kind: kind, summary: summary)
                    summaries[kind] = summary
                }
                for id in ids {
                    WGAntiDeleteIndexStore.writeArchived(transaction, id: id, content: nil)
                }
                return summaries
            }
            |> map { summaries -> Void in
                WGAntiDeleteAccounts.shared.updateSummaries(account: accountId, summaries, flushedPeers: [])
                return Void()
            })
        }
        return WGAntiDeleteOperations.sequence(signals)
    }

    /// Drops the saved versions of some messages (their entries leave the edited history).
    public static func removeEditHistory(postbox: Postbox, accountId: AccountRecordId, messageIds: [MessageId]) -> Signal<Never, NoError> {
        let byPeer = Dictionary(grouping: messageIds, by: { $0.peerId })
        var signals: [Signal<Void, NoError>] = []
        for (peerId, ids) in byPeer {
            signals.append(postbox.transaction { transaction -> WGAntiDeleteSummary in
                for id in ids {
                    wgClearEditHistory(transaction, id: id)
                }
                var summary = WGAntiDeleteIndexStore.readSummary(transaction, kind: .edited)
                WGAntiDeleteIndexStore.remove(transaction, kind: .edited, peerId: peerId, refs: Set(ids.map { WGAntiDeleteMessageRef(namespace: $0.namespace, id: $0.id) }), summary: &summary)
                WGAntiDeleteIndexStore.writeSummary(transaction, kind: .edited, summary: summary)
                return summary
            }
            |> map { summary -> Void in
                WGAntiDeleteAccounts.shared.updateSummaries(account: accountId, [.edited: summary], flushedPeers: [])
                return Void()
            })
        }
        return WGAntiDeleteOperations.sequence(signals)
    }

    /// Clears a history: the deleted one deletes the kept messages for real; the edited one
    /// drops the saved versions (not the local edits, not the reactions). One transaction per chat.
    public static func clear(postbox: Postbox, accountId: AccountRecordId, kind: WGAntiDeleteLogKind, peerIds: [PeerId]? = nil) -> Signal<Never, NoError> {
        return postbox.transaction { transaction -> [PeerId] in
            if let peerIds {
                return peerIds
            }
            return WGAntiDeleteIndexStore.readSummary(transaction, kind: kind).peers.keys.map { PeerId(wgKey: $0) }
        }
        |> mapToSignal { peerIds -> Signal<Never, NoError> in
            var signals: [Signal<Void, NoError>] = []
            for peerId in peerIds {
                signals.append(postbox.transaction { transaction -> WGAntiDeleteSummary in
                    let log = WGAntiDeleteIndexStore.readLog(transaction, kind: kind, peerId: peerId)
                    WGAntiDeleteOperations.dropEntries(transaction, postbox: postbox, kind: kind, peerId: peerId, entries: log.entries)
                    WGAntiDeleteIndexStore.writeLog(transaction, kind: kind, peerId: peerId, log: WGAntiDeletePeerLog())
                    var summary = WGAntiDeleteIndexStore.readSummary(transaction, kind: kind)
                    summary.remove(peer: peerId.wgKey)
                    WGAntiDeleteIndexStore.writeSummary(transaction, kind: kind, summary: summary)
                    return summary
                }
                |> map { summary -> Void in
                    WGAntiDeleteAccounts.shared.updateSummaries(account: accountId, [kind: summary], flushedPeers: [peerId])
                    return Void()
                })
            }
            return WGAntiDeleteOperations.sequence(signals)
        }
    }

    /// What dropping index entries means for their messages.
    private static func dropEntries(_ transaction: Transaction, postbox: Postbox, kind: WGAntiDeleteLogKind, peerId: PeerId, entries: [WGAntiDeleteLogEntry]) {
        switch kind {
        case .deleted:
            var ids: [MessageId] = []
            for entry in entries {
                let id = MessageId(peerId: peerId, namespace: entry.namespace, id: entry.id)
                if entry.isArchiveOnly {
                    WGAntiDeleteIndexStore.writeArchived(transaction, id: id, content: nil)
                } else {
                    ids.append(id)
                }
            }
            wgDeleteKeptMessages(transaction, postbox: postbox, ids: ids)
        case .edited:
            for entry in entries {
                wgClearEditHistory(transaction, id: MessageId(peerId: peerId, namespace: entry.namespace, id: entry.id))
            }
        }
    }

    /// Drops index entries whose messages no longer exist (deleted by the user, chat removed).
    public static func reconcile(postbox: Postbox, accountId: AccountRecordId, kind: WGAntiDeleteLogKind, peerId: PeerId) -> Signal<Never, NoError> {
        return postbox.transaction { transaction -> WGAntiDeleteSummary? in
            var log = WGAntiDeleteIndexStore.readLog(transaction, kind: kind, peerId: peerId)
            var ids = Set<MessageId>()
            for entry in log.entries where !entry.isArchiveOnly {
                ids.insert(MessageId(peerId: peerId, namespace: entry.namespace, id: entry.id))
            }
            let missing = ids.subtracting(transaction.filterStoredMessageIds(ids))
            if missing.isEmpty {
                return nil
            }
            log.remove(Set(missing.map { WGAntiDeleteMessageRef(namespace: $0.namespace, id: $0.id) }))
            WGAntiDeleteIndexStore.writeLog(transaction, kind: kind, peerId: peerId, log: log)
            var summary = WGAntiDeleteIndexStore.readSummary(transaction, kind: kind)
            summary.update(peer: peerId.wgKey, log: log)
            WGAntiDeleteIndexStore.writeSummary(transaction, kind: kind, summary: summary)
            return summary
        }
        |> map { summary -> Void in
            if let summary {
                WGAntiDeleteAccounts.shared.updateSummaries(account: accountId, [kind: summary], flushedPeers: [])
            }
            return Void()
        }
        |> ignoreValues
    }

    /// Age limit («Автоочистка») for one account: entries older than `cutoff` go, chat by chat.
    public static func prune(postbox: Postbox, accountId: AccountRecordId, cutoff: Int32) -> Signal<Never, NoError> {
        var signals: [Signal<Void, NoError>] = []
        for kind in WGAntiDeleteLogKind.allCases {
            signals.append(postbox.transaction { transaction -> [PeerId] in
                let summary = WGAntiDeleteIndexStore.readSummary(transaction, kind: kind)
                return summary.peers.keys.map { PeerId(wgKey: $0) }
            }
            |> mapToSignal { peerIds -> Signal<Void, NoError> in
                var perPeer: [Signal<Void, NoError>] = []
                for peerId in peerIds {
                    perPeer.append(postbox.transaction { transaction -> WGAntiDeleteSummary? in
                        var log = WGAntiDeleteIndexStore.readLog(transaction, kind: kind, peerId: peerId)
                        let removed = log.prune(olderThan: cutoff)
                        if removed.isEmpty {
                            return nil
                        }
                        WGAntiDeleteOperations.dropEntries(transaction, postbox: postbox, kind: kind, peerId: peerId, entries: removed)
                        WGAntiDeleteIndexStore.writeLog(transaction, kind: kind, peerId: peerId, log: log)
                        var summary = WGAntiDeleteIndexStore.readSummary(transaction, kind: kind)
                        summary.update(peer: peerId.wgKey, log: log)
                        WGAntiDeleteIndexStore.writeSummary(transaction, kind: kind, summary: summary)
                        return summary
                    }
                    |> map { summary -> Void in
                        if let summary {
                            WGAntiDeleteAccounts.shared.updateSummaries(account: accountId, [kind: summary], flushedPeers: [])
                        }
                        return Void()
                    })
                }
                return WGAntiDeleteOperations.sequence(perPeer)
                |> map { _ -> Void in }
            })
        }
        return WGAntiDeleteOperations.sequence(signals)
    }

    /// The age limit for every running account (foreground task).
    public static func pruneAllAccounts() -> Signal<Never, NoError> {
        let retention = WGAntiDeleteRetention(settingValue: WGAntiDeleteSettings.autoClear.value)
        guard let cutoff = retention.cutoff(now: WGAntiDeleteOperations.now()) else {
            return .complete()
        }
        var result: Signal<Never, NoError> = .complete()
        for state in WGAntiDeleteAccounts.shared.allStates() {
            if let postbox = state.postbox {
                result = result |> then(WGAntiDeleteOperations.prune(postbox: postbox, accountId: state.id, cutoff: cutoff))
            }
        }
        return result
    }

    // MARK: Export / import

    /// What the export collects, chat by chat. One transaction per chat appends its whole batch; the
    /// transactions run one after another, so the arrays grow in place (no copy of everything
    /// collected so far on every record, which kept the Postbox queue busy on a big archive).
    private final class WGAntiDeleteExportAccumulator {
        var deleted: [WGAntiDeleteExportFile.Deleted] = []
        var edited: [WGAntiDeleteExportFile.Edited] = []
    }

    /// The histories of an account (secret chats excluded), built chat by chat.
    public static func export(postbox: Postbox, accountId: AccountRecordId) -> Signal<Data?, NoError> {
        let collected = Atomic<WGAntiDeleteExportAccumulator>(value: WGAntiDeleteExportAccumulator())
        let peersSignal = postbox.transaction { transaction -> [(WGAntiDeleteLogKind, PeerId)] in
            var result: [(WGAntiDeleteLogKind, PeerId)] = []
            for kind in WGAntiDeleteLogKind.allCases {
                for peer in WGAntiDeleteIndexStore.readSummary(transaction, kind: kind).peers.keys.sorted() where !WGAntiDeleteExportFile.isSecretChat(peer) {
                    result.append((kind, PeerId(wgKey: peer)))
                }
            }
            return result
        }
        return peersSignal
        |> mapToSignal { items -> Signal<Data?, NoError> in
            var signals: [Signal<Void, NoError>] = []
            for (kind, peerId) in items {
                signals.append(postbox.transaction { transaction -> Void in
                    let log = WGAntiDeleteIndexStore.readLog(transaction, kind: kind, peerId: peerId)
                    var deleted: [WGAntiDeleteExportFile.Deleted] = []
                    var edited: [WGAntiDeleteExportFile.Edited] = []
                    for entry in log.entries {
                        let id = MessageId(peerId: peerId, namespace: entry.namespace, id: entry.id)
                        switch kind {
                        case .deleted:
                            if let item = WGAntiDeleteOperations.exportDeleted(transaction, id: id, entry: entry) {
                                deleted.append(item)
                            }
                        case .edited:
                            if let message = transaction.getMessage(id), let history = WGAntiDeleteMessageState(attributes: message.attributes).history {
                                edited.append(WGAntiDeleteExportFile.Edited(message: id.wgKey, thread: message.threadId, author: message.author.flatMap { EnginePeer($0).debugDisplayTitle }, current: message.text, versions: history.versions.map { WGAntiDeleteExportFile.Version(text: $0.text, date: $0.date) }))
                            }
                        }
                    }
                    if !deleted.isEmpty || !edited.isEmpty {
                        collected.with { accumulator in
                            accumulator.deleted.append(contentsOf: deleted)
                            accumulator.edited.append(contentsOf: edited)
                        }
                    }
                })
            }
            return WGAntiDeleteOperations.value(after: WGAntiDeleteOperations.sequence(signals), {
                return collected.with { accumulator in
                    return (accumulator.deleted, accumulator.edited)
                }
            })
            // The file is encoded off the Postbox queue (the last transaction completes there).
            |> deliverOn(Queue.concurrentDefaultQueue())
            |> map { value -> Data? in
                let file = WGAntiDeleteExportFile(account: accountId.wg, exportedAt: WGAntiDeleteOperations.now(), deleted: value.0, edited: value.1)
                return file.encode()
            }
        }
    }

    private static func exportDeleted(_ transaction: Transaction, id: MessageId, entry: WGAntiDeleteLogEntry) -> WGAntiDeleteExportFile.Deleted? {
        if let message = transaction.getMessage(id) {
            var username: String?
            if let author = message.author {
                username = EnginePeer(author).addressName
            }
            return WGAntiDeleteExportFile.Deleted(message: id.wgKey, thread: message.threadId, date: message.timestamp, deletedAt: entry.time, author: message.author.flatMap { EnginePeer($0).debugDisplayTitle }, username: username, text: message.text, media: wgAntiDeleteMediaToken(message.media))
        }
        if let content = WGAntiDeleteIndexStore.readArchived(transaction, id: id) {
            return WGAntiDeleteExportFile.Deleted(message: id.wgKey, thread: entry.threadId, date: content.date, deletedAt: content.deletedAt, author: content.authorName, username: content.authorUsername, text: content.text, media: content.mediaDescription)
        }
        return nil
    }

    public struct ImportResult: Equatable {
        public var added: Int
        public var skipped: Int
    }

    /// Adds archive entries from an export file. A message that is still in the chat is never
    /// marked as deleted; versions are added only to the message the file describes (same text).
    public static func importFile(postbox: Postbox, accountId: AccountRecordId, file: WGAntiDeleteExportFile) -> Signal<ImportResult, NoError> {
        let result = Atomic<ImportResult>(value: ImportResult(added: 0, skipped: 0))
        var signals: [Signal<Void, NoError>] = []
        let deletedByPeer = Dictionary(grouping: file.deleted, by: { $0.message.peer })
        for (peer, items) in deletedByPeer {
            let peerId = PeerId(wgKey: peer)
            signals.append(postbox.transaction { transaction -> WGAntiDeleteSummary in
                var entries: [WGAntiDeleteLogEntry] = []
                var skipped = 0
                for item in items {
                    let id = MessageId(wgKey: item.message)
                    if transaction.getMessage(id) != nil || WGAntiDeleteIndexStore.readArchived(transaction, id: id) != nil {
                        skipped += 1
                        continue
                    }
                    WGAntiDeleteIndexStore.writeArchived(transaction, id: id, content: WGAntiDeleteArchivedContent(date: item.date, deletedAt: item.deletedAt, authorName: item.author, authorUsername: item.username, text: item.text, mediaDescription: item.media))
                    entries.append(WGAntiDeleteLogEntry(namespace: id.namespace, id: id.id, threadId: item.thread, time: item.deletedAt, source: WGAntiDeleteSource.imported.rawValue, isArchiveOnly: true))
                }
                var summary = WGAntiDeleteIndexStore.readSummary(transaction, kind: .deleted)
                WGAntiDeleteIndexStore.apply(transaction, kind: .deleted, peerId: peerId, entries: entries, summary: &summary)
                WGAntiDeleteIndexStore.writeSummary(transaction, kind: .deleted, summary: summary)
                let added = entries.count
                let _ = result.modify { value in
                    return ImportResult(added: value.added + added, skipped: value.skipped + skipped)
                }
                return summary
            }
            |> map { summary -> Void in
                WGAntiDeleteAccounts.shared.updateSummaries(account: accountId, [.deleted: summary], flushedPeers: [])
                return Void()
            })
        }
        let editedByPeer = Dictionary(grouping: file.edited, by: { $0.message.peer })
        for (peer, items) in editedByPeer {
            let peerId = PeerId(wgKey: peer)
            signals.append(postbox.transaction { transaction -> WGAntiDeleteSummary in
                var entries: [WGAntiDeleteLogEntry] = []
                var skipped = 0
                for item in items {
                    let id = MessageId(wgKey: item.message)
                    guard let message = transaction.getMessage(id), message.text == item.current, WGAntiDeleteMessageState(attributes: message.attributes).history == nil, !item.versions.isEmpty else {
                        skipped += 1
                        continue
                    }
                    let history = WGEditHistoryMessageAttribute(versions: item.versions.map { WGEditVersion(text: $0.text, entities: [], date: $0.date, mediaDescription: nil) })
                    transaction.updateMessage(id, update: { current in
                        return .update(wgStoreMessage(current, attributes: wgReplacingAttribute(current.attributes, with: history)))
                    })
                    entries.append(WGAntiDeleteLogEntry(namespace: id.namespace, id: id.id, threadId: message.threadId, time: item.versions.last?.date ?? message.timestamp, count: Int32(history.versions.count), isOutgoing: !message.flags.contains(.Incoming)))
                }
                var summary = WGAntiDeleteIndexStore.readSummary(transaction, kind: .edited)
                WGAntiDeleteIndexStore.apply(transaction, kind: .edited, peerId: peerId, entries: entries, summary: &summary)
                WGAntiDeleteIndexStore.writeSummary(transaction, kind: .edited, summary: summary)
                let added = entries.count
                let _ = result.modify { value in
                    return ImportResult(added: value.added + added, skipped: value.skipped + skipped)
                }
                return summary
            }
            |> map { summary -> Void in
                WGAntiDeleteAccounts.shared.updateSummaries(account: accountId, [.edited: summary], flushedPeers: [])
                return Void()
            })
        }
        return WGAntiDeleteOperations.value(after: WGAntiDeleteOperations.sequence(signals), {
            return result.with { $0 }
        })
    }
}
