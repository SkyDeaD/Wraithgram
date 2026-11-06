// Compiled into TelegramCore (filegroup //Wraithgram/WGHooks:TelegramCoreHookSources).
// Points on the update / deletion paths. All handlers run INSIDE a Postbox transaction:
// they may read WGCore snapshots and mark messages through the given `Transaction`
// (their own attributes), nothing else — no UserDefaults, JSON, files or network.
// Heavy work goes to the feature's own queue after the transaction.

import Foundation
import Postbox
import SwiftSignalKit
import WGCore

/// Where a deletion comes from. User-initiated deletions other than "for everyone" of the
/// user's own messages are not routed through the points: the user asked for them.
public enum WGDeletionSource: Equatable {
    /// `updateDeleteMessages` / `updateDeleteChannelMessages` (incl. getDifference).
    case remoteUpdate
    /// History validation found the message gone on the server (holes, resets).
    case historyValidation
    /// The other side of a secret chat deleted it.
    case secretChat
    /// A self-destruct timer (secret chat TTL, auto-delete, view-once) fired on this device.
    case autoremoveTimer
    /// The user deleted messages "for everyone" (`InteractiveMessagesDeletionType.forEveryone`).
    case localForEveryone
}

public struct WGDeletionRequest {
    public let ids: [MessageId]
    public let source: WGDeletionSource
    public let transaction: Transaction
    private let explicitAccountPeerId: PeerId?

    init(ids: [MessageId], source: WGDeletionSource, transaction: Transaction, accountPeerId: PeerId?) {
        self.ids = ids
        self.source = source
        self.transaction = transaction
        self.explicitAccountPeerId = accountPeerId
    }

    public var accountPeerId: PeerId? {
        return self.explicitAccountPeerId ?? wgAccountPeerId(transaction: self.transaction)
    }

    public var accountId: AccountRecordId? {
        return self.accountPeerId.flatMap(WGAccountHooks.accountId(forAccountPeerId:))
    }

    /// True in the notification service / share extension: an extension must not mark
    /// anything it cannot finish, it hands work to the app (`WGSharedInbox`).
    public var isExtension: Bool {
        if let process = WGCore.environment?.process {
            return !process.isApp
        }
        return false
    }
}

/// A server-side "history cleared up to N" (`UpdateMinAvailableMessage`, cached
/// `minAvailableMessageId`) or a secret chat cleared by the other side.
public struct WGHistoryClearRequest {
    public let peerId: PeerId
    /// nil = every namespace of the chat is cleared (secret chat).
    public let namespace: MessageId.Namespace?
    /// Inclusive upper bound; nil = the whole history.
    public let maxId: MessageId.Id?
    public let source: WGDeletionSource
    public let transaction: Transaction

    public var accountPeerId: PeerId? {
        return wgAccountPeerId(transaction: self.transaction)
    }
}

public struct WGMessageEditRequest {
    /// The stored message before the edit.
    public let previous: Message
    /// Text of the incoming version.
    public let updatedText: String
    /// Media of the incoming version, as it will be stored (a paid media that was already
    /// unlocked keeps its unlocked form).
    public let updatedMedia: [Media]
    public let accountPeerId: PeerId
    public let transaction: Transaction
}

public enum WGUpdateHooks {
    /// Policy (union). Returns the ids the feature keeps (and has marked). The rest is deleted
    /// as in upstream. Called for every source in `WGDeletionSource`.
    public static let messagesWillBeDeleted = WGHookPoint<(WGDeletionRequest) -> Set<MessageId>>("updates.messagesWillBeDeleted")

    /// Policy (union). A cleared history range: ids inside the range that stay. For a whole
    /// history (`maxId == nil`) any non-empty answer keeps the entire history; the feature then
    /// marks the messages itself (after the transaction if that is heavy).
    public static let historyWillBeCleared = WGHookPoint<(WGHistoryClearRequest) -> Set<MessageId>>("updates.historyWillBeCleared")

    /// Transformer. Extra attributes for the incoming version of an edited message
    /// (the previous text, a version counter…). Returns the full attribute list.
    public static let messageWillBeEdited = WGHookPoint<(WGMessageEditRequest, [MessageAttribute]) -> [MessageAttribute]>("updates.messageWillBeEdited")
}

// MARK: - Call-site helpers (TelegramCore internal)

func wgMessageIdsToDelete(_ ids: [MessageId], source: WGDeletionSource, transaction: Transaction, accountPeerId: PeerId?) -> [MessageId] {
    if ids.isEmpty || WGUpdateHooks.messagesWillBeDeleted.isEmpty {
        return ids
    }
    let request = WGDeletionRequest(ids: ids, source: source, transaction: transaction, accountPeerId: accountPeerId)
    var kept = Set<MessageId>()
    for handler in WGUpdateHooks.messagesWillBeDeleted.handlers {
        kept.formUnion(handler(request))
    }
    if kept.isEmpty {
        return ids
    }
    return ids.filter { !kept.contains($0) }
}

/// Global ids (private chats and basic groups): the message id equals the global id.
func wgGlobalMessageIdsToDelete(_ ids: [Int32], source: WGDeletionSource, transaction: Transaction, accountPeerId: PeerId?) -> [Int32] {
    if ids.isEmpty || WGUpdateHooks.messagesWillBeDeleted.isEmpty {
        return ids
    }
    let messageIds = transaction.messageIdsForGlobalIds(ids)
    if messageIds.isEmpty {
        return ids
    }
    let remaining = wgMessageIdsToDelete(messageIds, source: source, transaction: transaction, accountPeerId: accountPeerId)
    if remaining.count == messageIds.count {
        return ids
    }
    let remainingSet = Set(remaining)
    var kept = Set<Int32>()
    for id in messageIds where !remainingSet.contains(id) {
        kept.insert(id.id)
    }
    return ids.filter { !kept.contains($0) }
}

/// True when a feature keeps this message instead of letting it be deleted.
func wgKeepsMessage(_ id: MessageId, source: WGDeletionSource, transaction: Transaction, accountPeerId: PeerId?) -> Bool {
    return wgMessageIdsToDelete([id], source: source, transaction: transaction, accountPeerId: accountPeerId).isEmpty
}

/// `transaction.deleteMessagesInRange` that leaves the ids features keep.
func wgDeleteMessagesInRange(transaction: Transaction, peerId: PeerId, namespace: MessageId.Namespace, minId: MessageId.Id, maxId: MessageId.Id, source: WGDeletionSource, forEachMedia: ((Media) -> Void)?) {
    if WGUpdateHooks.historyWillBeCleared.isEmpty {
        transaction.deleteMessagesInRange(peerId: peerId, namespace: namespace, minId: minId, maxId: maxId, forEachMedia: forEachMedia)
        return
    }
    let request = WGHistoryClearRequest(peerId: peerId, namespace: namespace, maxId: maxId, source: source, transaction: transaction)
    var kept = Set<MessageId.Id>()
    for handler in WGUpdateHooks.historyWillBeCleared.handlers {
        for id in handler(request) where id.peerId == peerId && id.namespace == namespace && id.id >= minId && id.id <= maxId {
            kept.insert(id.id)
        }
    }
    if kept.isEmpty {
        transaction.deleteMessagesInRange(peerId: peerId, namespace: namespace, minId: minId, maxId: maxId, forEachMedia: forEachMedia)
        return
    }
    // Delete the gaps between the kept ids.
    var lower = minId
    for id in kept.sorted() {
        if id > lower {
            transaction.deleteMessagesInRange(peerId: peerId, namespace: namespace, minId: lower, maxId: id - 1, forEachMedia: forEachMedia)
        }
        lower = id + 1
    }
    if lower <= maxId {
        transaction.deleteMessagesInRange(peerId: peerId, namespace: namespace, minId: lower, maxId: maxId, forEachMedia: forEachMedia)
    }
}

/// True when a feature keeps the whole history the other side of a secret chat cleared.
func wgKeepsClearedHistory(peerId: PeerId, source: WGDeletionSource, transaction: Transaction) -> Bool {
    if WGUpdateHooks.historyWillBeCleared.isEmpty {
        return false
    }
    let request = WGHistoryClearRequest(peerId: peerId, namespace: nil, maxId: nil, source: source, transaction: transaction)
    for handler in WGUpdateHooks.historyWillBeCleared.handlers {
        if !handler(request).isEmpty {
            return true
        }
    }
    return false
}

func wgEditedMessageAttributes(previous: Message, updatedText: String, updatedMedia: [Media], attributes: [MessageAttribute], accountPeerId: PeerId, transaction: Transaction) -> [MessageAttribute] {
    let request = WGMessageEditRequest(previous: previous, updatedText: updatedText, updatedMedia: updatedMedia, accountPeerId: accountPeerId, transaction: transaction)
    var result = attributes
    for handler in WGUpdateHooks.messageWillBeEdited.handlers {
        result = handler(request, result)
    }
    return result
}
