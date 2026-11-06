import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import WGCore

/// One-time import of what the old Wraithgram kept (same bundle id, so its files are in place),
/// per account, off the main thread:
/// - an archived deletion becomes the Wraithgram attribute of the very message it describes
///   (same chat, id, date and text) — never of another account's message with the same id;
///   without such a message it becomes an archive entry of a chat this account knows;
/// - previous versions, local edits, bookmarks go to their messages (replaced reactions are not
///   imported: the feature was removed on 2026-10-27; their files are only deleted).
/// The plain-text files (secret chat content included) are deleted once every account imported
/// them: from then on everything lives in the encrypted database of its account.
public enum WGAntiDeleteLegacyImport {
    private static let stashName = "ghostgram_antidelete_legacy.bin"
    private static let chunkSize = 300

    private struct Sources {
        var deleted: [WGLegacyDeletedEntry] = []
        var edits: [WGLegacyEditEntry] = []
        var localEdits: [WGLegacyLocalEdit] = []
        var bookmarks: [WGLegacyBookmark] = []

        var isEmpty: Bool {
            return self.deleted.isEmpty && self.edits.isEmpty && self.localEdits.isEmpty && self.bookmarks.isEmpty
        }
    }

    private static var cachedSources: Sources?

    private static var documentsPath: String? {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
    }

    private static var stashPath: String? {
        return WGAntiDeleteLegacyImport.documentsPath.map { $0 + "/" + WGAntiDeleteLegacyImport.stashName }
    }

    /// The global migration (main thread) hands over the UserDefaults blobs; they are written to
    /// the stash on the anti-delete queue and only then removed from UserDefaults.
    public static func stash(editHistory: Data?, archiveMirror: Data?, didStash: @escaping () -> Void) {
        let stash = WGAntiDeleteLegacyStash(editHistory: editHistory, archiveMirror: archiveMirror)
        if stash.isEmpty {
            didStash()
            return
        }
        WGAntiDeleteAccounts.shared.queue.justDispatch {
            guard let path = WGAntiDeleteLegacyImport.stashPath else {
                return
            }
            do {
                try stash.encode().write(to: URL(fileURLWithPath: path), options: [.atomic])
                didStash()
            } catch {
                WGLog.warning("antiDelete", "legacy stash failed, the old data stays in place")
            }
        }
    }

    private static func readFile(_ name: String) -> Data? {
        guard let documentsPath = WGAntiDeleteLegacyImport.documentsPath else {
            return nil
        }
        return try? Data(contentsOf: URL(fileURLWithPath: documentsPath + "/" + name))
    }

    /// Anti-delete queue.
    private static func loadSources() -> Sources {
        if let cached = WGAntiDeleteLegacyImport.cachedSources {
            return cached
        }
        var sources = Sources()
        var stash: WGAntiDeleteLegacyStash?
        if let path = WGAntiDeleteLegacyImport.stashPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            stash = WGAntiDeleteLegacyStash(data: data)
        }
        for name in WGAntiDeleteLegacyParser.deletedArchiveFiles {
            if let data = WGAntiDeleteLegacyImport.readFile(name) {
                let entries = WGAntiDeleteLegacyParser.deletedArchive(data)
                if !entries.isEmpty {
                    sources.deleted = entries
                    break
                }
            }
        }
        if sources.deleted.isEmpty, let mirror = stash?.archiveMirror {
            sources.deleted = WGAntiDeleteLegacyParser.deletedArchive(mirror)
        }
        if let editHistory = stash?.editHistory {
            sources.edits = WGAntiDeleteLegacyParser.editHistory(editHistory)
        }
        if let data = WGAntiDeleteLegacyImport.readFile(WGAntiDeleteLegacyParser.localEditsFile) {
            sources.localEdits = WGAntiDeleteLegacyParser.localEdits(data)
        }
        if let data = WGAntiDeleteLegacyImport.readFile(WGAntiDeleteLegacyParser.bookmarksFile) {
            sources.bookmarks = WGAntiDeleteLegacyParser.bookmarks(data)
        }
        WGAntiDeleteLegacyImport.cachedSources = sources
        return sources
    }

    /// Account start (app). Runs once per account; does nothing when there is nothing old.
    static func importIfNeeded(accountId: AccountRecordId, postbox: Postbox) {
        WGAntiDeleteAccounts.shared.queue.justDispatch {
            if WGAntiDeleteSettings.legacyImportDone.value(for: accountId.wg) {
                return
            }
            let sources = WGAntiDeleteLegacyImport.loadSources()
            if sources.isEmpty {
                WGAntiDeleteSettings.legacyImportDone.set(true, for: accountId.wg)
                WGAntiDeleteLegacyImport.removeFilesIfEveryAccountImported()
                return
            }
            // Read here, not inside a transaction (a directory listing).
            let isSingleAccount = WGLegacyAccounts.isSingleAccount
            var signals: [Signal<Never, NoError>] = []
            var offset = 0
            while offset < sources.deleted.count {
                let chunk = Array(sources.deleted[offset ..< min(offset + WGAntiDeleteLegacyImport.chunkSize, sources.deleted.count)])
                signals.append(postbox.transaction { transaction -> Void in
                    WGAntiDeleteLegacyImport.importDeleted(transaction, entries: chunk)
                } |> ignoreValues)
                offset += WGAntiDeleteLegacyImport.chunkSize
            }
            signals.append(postbox.transaction { transaction -> Void in
                WGAntiDeleteLegacyImport.importOthers(transaction, sources: sources, isSingleAccount: isSingleAccount)
            } |> ignoreValues)

            var chain: Signal<Never, NoError> = .complete()
            for signal in signals {
                chain = chain |> then(signal)
            }
            let _ = (chain |> deliverOn(WGAntiDeleteAccounts.shared.queue)).start(completed: {
                WGAntiDeleteSettings.legacyImportDone.set(true, for: accountId.wg)
                WGLog.info("antiDelete", "legacy archive imported into an account")
                // Summaries changed under the account: reload them.
                let _ = (postbox.transaction { transaction -> [WGAntiDeleteLogKind: WGAntiDeleteSummary] in
                    var result: [WGAntiDeleteLogKind: WGAntiDeleteSummary] = [:]
                    for kind in WGAntiDeleteLogKind.allCases {
                        result[kind] = WGAntiDeleteIndexStore.readSummary(transaction, kind: kind)
                    }
                    return result
                } |> deliverOn(WGAntiDeleteAccounts.shared.queue)).start(next: { summaries in
                    WGAntiDeleteAccounts.shared.updateSummaries(account: accountId, summaries, flushedPeers: [])
                    WGAntiDeleteLegacyImport.removeFilesIfEveryAccountImported()
                })
            })
        }
    }

    /// The message an old record describes in this account, if it is really that message.
    private static func matchingMessage(_ transaction: Transaction, peerId: PeerId, id: Int32, timestamp: Int32, text: String) -> Message? {
        let namespaces: [MessageId.Namespace]
        if peerId.namespace == Namespaces.Peer.SecretChat {
            namespaces = [Namespaces.Message.SecretIncoming, Namespaces.Message.Local]
        } else {
            namespaces = [Namespaces.Message.Cloud]
        }
        for namespace in namespaces {
            guard let message = transaction.getMessage(MessageId(peerId: peerId, namespace: namespace, id: id)) else {
                continue
            }
            if timestamp != 0 && message.timestamp != timestamp {
                continue
            }
            if !text.isEmpty && message.text != text {
                continue
            }
            return message
        }
        return nil
    }

    private static func importDeleted(_ transaction: Transaction, entries: [WGLegacyDeletedEntry]) {
        var summary = WGAntiDeleteIndexStore.readSummary(transaction, kind: .deleted)
        var byPeer: [PeerId: [WGAntiDeleteLogEntry]] = [:]
        for entry in entries {
            let peerId = PeerId(wgKey: entry.peer)
            // Only chats this account knows: the old archive mixed all accounts.
            if transaction.getPeer(peerId) == nil {
                continue
            }
            let deletedAt = entry.deletedAt != 0 ? entry.deletedAt : entry.timestamp
            if let message = WGAntiDeleteLegacyImport.matchingMessage(transaction, peerId: peerId, id: entry.messageId, timestamp: entry.timestamp, text: entry.text) {
                if !message.wgIsDeleted {
                    transaction.updateMessage(message.id, update: { current in
                        return .update(wgStoreMessage(current, attributes: wgReplacingAttribute(current.attributes, with: WGDeletedMessageAttribute(deletedAt: deletedAt, source: .imported))))
                    })
                }
                byPeer[peerId, default: []].append(WGAntiDeleteLogEntry(namespace: message.id.namespace, id: message.id.id, threadId: message.threadId, time: deletedAt, source: WGAntiDeleteSource.imported.rawValue, isOutgoing: !message.flags.contains(.Incoming)))
            } else {
                let id = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: entry.messageId)
                if transaction.getMessage(id) != nil {
                    // A live message with the same id but other content: not ours to mark.
                    continue
                }
                WGAntiDeleteIndexStore.writeArchived(transaction, id: id, content: WGAntiDeleteArchivedContent(date: entry.timestamp, deletedAt: deletedAt, authorName: entry.authorName, authorUsername: entry.authorUsername, text: entry.text, mediaDescription: entry.mediaDescription))
                byPeer[peerId, default: []].append(WGAntiDeleteLogEntry(namespace: id.namespace, id: id.id, threadId: entry.threadId, time: deletedAt, source: WGAntiDeleteSource.imported.rawValue, isArchiveOnly: true))
            }
        }
        for (peerId, logEntries) in byPeer {
            WGAntiDeleteIndexStore.apply(transaction, kind: .deleted, peerId: peerId, entries: logEntries, summary: &summary)
        }
        WGAntiDeleteIndexStore.writeSummary(transaction, kind: .deleted, summary: summary)
    }

    /// Whether a message id names the same message in every account: channels (and supergroups) number
    /// their messages themselves; private chats, basic groups and secret chats use the account's own
    /// counter, so the same id in another account is another message.
    private static func idIsSharedByAccounts(_ id: MessageId) -> Bool {
        return id.peerId.namespace == Namespaces.Peer.CloudChannel
    }

    /// The old edit records carry no date or text of the message itself: in a chat with per-account ids
    /// and several accounts, only a message that was edited and already existed at the first recorded
    /// edit can be the one (the device clock may be behind the server: 15 minutes of slack).
    private static func mayBeRecordedEditedMessage(_ message: Message, firstEditDate: Int32) -> Bool {
        if !message.attributes.contains(where: { $0 is EditedMessageAttribute }) {
            return false
        }
        if firstEditDate != 0 && message.timestamp > firstEditDate + 15 * 60 {
            return false
        }
        return true
    }

    private static func importOthers(_ transaction: Transaction, sources: Sources, isSingleAccount: Bool) {
        let now = Int32(Date().timeIntervalSince1970)

        var editedSummary = WGAntiDeleteIndexStore.readSummary(transaction, kind: .edited)
        var editedByPeer: [PeerId: [WGAntiDeleteLogEntry]] = [:]
        for entry in sources.edits {
            let id = MessageId(wgKey: entry.message)
            guard transaction.getPeer(id.peerId) != nil, let message = transaction.getMessage(id) else {
                continue
            }
            if !isSingleAccount && !WGAntiDeleteLegacyImport.idIsSharedByAccounts(id) && !WGAntiDeleteLegacyImport.mayBeRecordedEditedMessage(message, firstEditDate: entry.versions.first?.date ?? 0) {
                // Another account's message with the same id: not ours to attach versions to.
                continue
            }
            if WGAntiDeleteMessageState(attributes: message.attributes).history != nil {
                continue
            }
            let history = WGEditHistoryMessageAttribute(versions: entry.versions.map { WGEditVersion(text: $0.text, entities: [], date: $0.date, mediaDescription: nil) })
            transaction.updateMessage(id, update: { current in
                return .update(wgStoreMessage(current, attributes: wgReplacingAttribute(current.attributes, with: history)))
            })
            editedByPeer[id.peerId, default: []].append(WGAntiDeleteLogEntry(namespace: id.namespace, id: id.id, threadId: message.threadId, time: entry.versions.last?.date ?? message.timestamp, count: Int32(history.versions.count), isOutgoing: !message.flags.contains(.Incoming)))
        }
        for (peerId, entries) in editedByPeer {
            WGAntiDeleteIndexStore.apply(transaction, kind: .edited, peerId: peerId, entries: entries, summary: &editedSummary)
        }
        WGAntiDeleteIndexStore.writeSummary(transaction, kind: .edited, summary: editedSummary)

        for entry in sources.localEdits {
            let id = MessageId(wgKey: entry.message)
            // A local edit keeps only its new text: nothing to check the message against. With several
            // accounts it is taken only where ids are the same message in every account.
            if !isSingleAccount && !WGAntiDeleteLegacyImport.idIsSharedByAccounts(id) {
                continue
            }
            guard transaction.getPeer(id.peerId) != nil, let message = transaction.getMessage(id) else {
                continue
            }
            if WGAntiDeleteMessageState(attributes: message.attributes).localEdit != nil {
                continue
            }
            transaction.updateMessage(id, update: { current in
                return .update(wgStoreMessage(current, attributes: wgReplacingAttribute(current.attributes, with: WGLocalEditMessageAttribute(text: entry.text, entities: [], date: now, isActive: true))))
            })
        }

        var bookmarks = WGAntiDeleteIndexStore.readBookmarks(transaction)
        var evicted: [WGBookmarkEntry] = []
        for entry in sources.bookmarks {
            let id = MessageId(wgKey: entry.message)
            if entry.messageDate == 0 && !isSingleAccount && !WGAntiDeleteLegacyImport.idIsSharedByAccounts(id) {
                // No date to check the message against, and the id may be another account's message.
                continue
            }
            guard transaction.getPeer(id.peerId) != nil, let message = transaction.getMessage(id) else {
                continue
            }
            if entry.messageDate != 0 && message.timestamp != entry.messageDate {
                continue
            }
            let createdAt = entry.createdAt != 0 ? entry.createdAt : now
            transaction.updateMessage(id, update: { current in
                return .update(wgStoreMessage(current, attributes: wgReplacingAttribute(current.attributes, with: WGBookmarkMessageAttribute(title: entry.title, createdAt: createdAt, isActive: true))))
            })
            evicted.append(contentsOf: bookmarks.set(WGBookmarkEntry(message: entry.message, threadId: message.threadId, title: entry.title, createdAt: createdAt, messageDate: message.timestamp)))
        }
        // Over the cap: the oldest lose their mark as well (a later import may bring one back, so only
        // what is not in the list in the end).
        let kept = Set(bookmarks.entries.map(\.message))
        WGAntiDeleteIndexStore.deactivateBookmarks(transaction, evicted.filter { !kept.contains($0.message) }, now: now)
        WGAntiDeleteIndexStore.writeBookmarks(transaction, list: bookmarks)
    }

    /// Deletes the old plain-text files once no registered account still needs them.
    private static func removeFilesIfEveryAccountImported() {
        for account in WGSettingsStore.shared.registeredAccounts where !WGAntiDeleteSettings.legacyImportDone.value(for: account) {
            return
        }
        guard let documentsPath = WGAntiDeleteLegacyImport.documentsPath else {
            return
        }
        var names = WGAntiDeleteLegacyParser.deletedArchiveFiles
        names.append(WGAntiDeleteLegacyParser.localEditsFile)
        names.append(WGAntiDeleteLegacyParser.bookmarksFile)
        names.append(contentsOf: WGAntiDeleteLegacyParser.editedReactionsFiles)
        names.append(contentsOf: WGAntiDeleteLegacyParser.deletedReactionsFiles)
        names.append(WGAntiDeleteLegacyImport.stashName)
        for name in names {
            let path = documentsPath + "/" + name
            if FileManager.default.fileExists(atPath: path) {
                let _ = try? FileManager.default.removeItem(atPath: path)
            }
        }
        WGAntiDeleteLegacyImport.cachedSources = nil
    }
}
