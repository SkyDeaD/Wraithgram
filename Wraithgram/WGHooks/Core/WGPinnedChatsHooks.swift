// Compiled into TelegramCore (filegroup //Wraithgram/WGHooks:TelegramCoreHookSources).
// "Pinned chats beyond the server limit": the server keeps a prefix of a pinned list, a feature
// keeps the rest as a local tail. The points cover every place where a pinned list is limited, where
// the server's list replaces the stored one and where the stored list goes to the server — for
// «Чаты», the archive and «Избранное». Folders are not covered: a folder's pins are not limited on
// their own (only the folder's size is, and the whole folder is synchronized with the server).
// Handlers run inside Postbox transactions: snapshot reads, and the feature's own Postbox records
// through the passed `Transaction` only.

import Foundation
import Postbox
import WGCore

/// A pinned list with its own server limit.
public enum WGPinnedList: Equatable {
    /// «Чаты» (`.root`) or the archive (`.group(1)`): `transaction.getPinnedItemIds(groupId:)`.
    case chats(PeerGroupId)
    /// «Избранное»: pinned dialogs of Saved Messages, `transaction.getPeerPinnedThreads(peerId:)` of
    /// the account's own peer (a thread id is `PeerId.toInt64()` of the chat).
    case savedMessages
}

public struct WGPinLimitRequest {
    public let list: WGPinnedList
    /// The limit the server configuration allows this account (Premium included).
    public let serverLimit: Int
    public let isPremium: Bool
    public let accountPeerId: PeerId
}

public struct WGPinnedListRequest {
    public let list: WGPinnedList
    public let accountPeerId: PeerId
    /// The list stored on this device now (`listToServer`: the list just stored).
    public let local: [PinnedItemId]
    /// `listFromServer`: the server's list, about to replace `local`. `listToServer`: the list about
    /// to go to the server.
    public let proposed: [PinnedItemId]
    /// The limit the server allows this account for this list (Premium included) — the same value
    /// upstream checks when a chat is pinned.
    public let serverLimit: Int
    /// The current transaction: for the feature's own Postbox records.
    public let transaction: Transaction
}

/// One synchronization of «Чаты» or the archive (`messages.getPinnedDialogs`).
public struct WGPinnedSyncRequest {
    public let groupId: PeerGroupId
    public let accountPeerId: PeerId
    /// The stored list when the first change that is not synchronized yet was made; upstream treats
    /// it as what the server had.
    public let previous: [PinnedItemId]
    /// The stored list when the synchronization started.
    public let local: [PinnedItemId]
    /// The server's list.
    public let remote: [PinnedItemId]
    /// Upstream's merge of the three: what upstream stores and sends.
    public let merged: [PinnedItemId]
    public let serverLimit: Int
    /// The current transaction: for the feature's own Postbox records.
    public let transaction: Transaction
}

public struct WGPinnedSyncResult {
    /// Stored on this device.
    public let stored: [PinnedItemId]
    /// Sent to the server (`messages.reorderPinnedDialogs`); secret chats are dropped on the wire as
    /// upstream does.
    public let toServer: [PinnedItemId]

    public init(stored: [PinnedItemId], toServer: [PinnedItemId]) {
        self.stored = stored
        self.toServer = toServer
    }
}

public enum WGPinnedChatsHooks {
    /// Policy: how many chats may be pinned locally in a list (nil = the server limit). Asked when a
    /// chat is pinned in «Чаты», the archive or «Избранное»; never for folders.
    public static let pinLimit = WGHookPoint<(WGPinLimitRequest) -> Int?>("pinnedChats.pinLimit")

    /// Transformer: the list stored when the server's list arrives (chat list holes, account state
    /// reset, the first page of Saved Messages, a reorder of Saved Messages pins from the server).
    public static let listFromServer = WGHookPoint<(WGPinnedListRequest) -> [PinnedItemId]>("pinnedChats.listFromServer")

    /// Policy: the merge of a «Чаты» / archive synchronization — what is stored and what goes to the
    /// server. The first non-nil answer wins; nil everywhere = upstream's merge.
    public static let sync = WGHookPoint<(WGPinnedSyncRequest) -> WGPinnedSyncResult?>("pinnedChats.sync")

    /// Transformer: the Saved Messages list sent to the server (`messages.reorderPinnedSavedDialogs`)
    /// when a chat is pinned or the pins are reordered there.
    public static let listToServer = WGHookPoint<(WGPinnedListRequest) -> [PinnedItemId]>("pinnedChats.listToServer")
}

public enum WGLimitHooks {
    /// Policy: how many recently searched chats are kept (upstream: 20).
    public static let recentSearchLimit = WGHookPoint<(Int) -> Int?>("limits.recentSearch")
}

/// The server's limit for a list, computed the way `_internal_toggleItemPinned` computes it (the
/// account's own Premium flag as the server reported it, the app configuration).
private func wgPinnedServerLimit(_ list: WGPinnedList, accountPeerId: PeerId, transaction: Transaction) -> Int {
    let isPremium = transaction.getPeer(accountPeerId)?.isPremium ?? false
    let appConfiguration = transaction.getPreferencesEntry(key: PreferencesKeys.appConfiguration)?.get(AppConfiguration.self) ?? .defaultValue
    let limits = UserLimitsConfiguration(appConfiguration: appConfiguration, isPremium: isPremium)
    switch list {
    case let .chats(groupId):
        if case .root = groupId {
            return Int(limits.maxPinnedChatCount)
        }
        return Int(limits.maxArchivedPinnedChatCount)
    case .savedMessages:
        return Int(limits.maxPinnedSavedChatCount)
    }
}

private func wgPinnedThreadId(_ itemId: PinnedItemId) -> Int64 {
    switch itemId {
    case let .peer(peerId):
        return peerId.toInt64()
    }
}

private func wgPinnedPeerId(_ itemId: PinnedItemId) -> PeerId {
    switch itemId {
    case let .peer(peerId):
        return peerId
    }
}

private func wgPinLimit(_ request: WGPinLimitRequest) -> Int {
    for handler in WGPinnedChatsHooks.pinLimit.handlers {
        if let value = handler(request) {
            return max(request.serverLimit, value)
        }
    }
    return request.serverLimit
}

/// WRAITH hook target: `_internal_toggleItemPinned` («Чаты», archive).
func wgPinnedChatsLimit(_ serverLimit: Int, groupId: PeerGroupId, isPremium: Bool, accountPeerId: PeerId) -> Int {
    if WGPinnedChatsHooks.pinLimit.isEmpty {
        return serverLimit
    }
    return wgPinLimit(WGPinLimitRequest(list: .chats(groupId), serverLimit: serverLimit, isPremium: isPremium, accountPeerId: accountPeerId))
}

/// WRAITH hook target: `TelegramEngine.Peers.toggleForumChannelTopicPinned` for the account's own
/// peer («Избранное»).
func wgPinnedSavedChatsLimit(_ serverLimit: Int, isPremium: Bool, accountPeerId: PeerId) -> Int {
    if WGPinnedChatsHooks.pinLimit.isEmpty {
        return serverLimit
    }
    return wgPinLimit(WGPinLimitRequest(list: .savedMessages, serverLimit: serverLimit, isPremium: isPremium, accountPeerId: accountPeerId))
}

private func wgPinnedListFromServer(_ list: WGPinnedList, proposed: [PinnedItemId], local: [PinnedItemId], accountPeerId: PeerId, transaction: Transaction) -> [PinnedItemId] {
    let serverLimit = wgPinnedServerLimit(list, accountPeerId: accountPeerId, transaction: transaction)
    var result = proposed
    for handler in WGPinnedChatsHooks.listFromServer.handlers {
        result = handler(WGPinnedListRequest(list: list, accountPeerId: accountPeerId, local: local, proposed: result, serverLimit: serverLimit, transaction: transaction))
    }
    return result
}

/// WRAITH hook target: the server's «Чаты» / archive list replaces the stored one (`Holes`,
/// `ResetState`).
func wgPinnedItemIdsFromServer(_ proposed: [PinnedItemId], groupId: PeerGroupId, transaction: Transaction) -> [PinnedItemId] {
    if WGPinnedChatsHooks.listFromServer.isEmpty {
        return proposed
    }
    guard let accountPeerId = wgAccountPeerId(transaction: transaction) else {
        return proposed
    }
    return wgPinnedListFromServer(.chats(groupId), proposed: proposed, local: transaction.getPinnedItemIds(groupId: groupId), accountPeerId: accountPeerId, transaction: transaction)
}

/// WRAITH hook target: `applyLoadMessageHistoryThreadsResults` — the first page of a thread list
/// carries its pins. Only the account's own peer (Saved Messages) is a pinned chat list; forums and
/// monoforums pass through untouched.
func wgPinnedSavedThreadIdsFromServer(_ threadIds: [Int64], peerId: PeerId, accountPeerId: PeerId, transaction: Transaction) -> [Int64] {
    if WGPinnedChatsHooks.listFromServer.isEmpty || peerId != accountPeerId {
        return threadIds
    }
    let local = transaction.getPeerPinnedThreads(peerId: accountPeerId).map { PinnedItemId.peer(PeerId($0)) }
    let proposed = threadIds.map { PinnedItemId.peer(PeerId($0)) }
    return wgPinnedListFromServer(.savedMessages, proposed: proposed, local: local, accountPeerId: accountPeerId, transaction: transaction).map(wgPinnedThreadId)
}

/// WRAITH hook target: replay of `updatePinnedSavedDialogs` with an order.
func wgPinnedSavedPeerIdsFromServer(_ peerIds: [PeerId], accountPeerId: PeerId, transaction: Transaction) -> [PeerId] {
    if WGPinnedChatsHooks.listFromServer.isEmpty {
        return peerIds
    }
    let local = transaction.getPeerPinnedThreads(peerId: accountPeerId).map { PinnedItemId.peer(PeerId($0)) }
    return wgPinnedListFromServer(.savedMessages, proposed: peerIds.map(PinnedItemId.peer), local: local, accountPeerId: accountPeerId, transaction: transaction).map(wgPinnedPeerId)
}

/// WRAITH hook target: `_internal_setForumChannelPinnedTopics` for the account's own peer — the
/// stored Saved Messages list (`threadIds`) is about to go to the server.
func wgPinnedSavedThreadIdsToServer(_ threadIds: [Int64], accountPeerId: PeerId, transaction: Transaction) -> [Int64] {
    if WGPinnedChatsHooks.listToServer.isEmpty {
        return threadIds
    }
    let serverLimit = wgPinnedServerLimit(.savedMessages, accountPeerId: accountPeerId, transaction: transaction)
    let stored = threadIds.map { PinnedItemId.peer(PeerId($0)) }
    var result = stored
    for handler in WGPinnedChatsHooks.listToServer.handlers {
        result = handler(WGPinnedListRequest(list: .savedMessages, accountPeerId: accountPeerId, local: stored, proposed: result, serverLimit: serverLimit, transaction: transaction))
    }
    return result.map(wgPinnedThreadId)
}

/// WRAITH hook target: `synchronizePinnedChats`, in the transaction that stores the merge. Returns
/// what to store and what to send; upstream's merge for both while the point is empty.
func wgPinnedChatsSync(previous: [PinnedItemId], local: [PinnedItemId], remote: [PinnedItemId], merged: [PinnedItemId], groupId: PeerGroupId, accountPeerId: PeerId, transaction: Transaction) -> (stored: [PinnedItemId], toServer: [PinnedItemId]) {
    if WGPinnedChatsHooks.sync.isEmpty {
        return (merged, merged)
    }
    let request = WGPinnedSyncRequest(groupId: groupId, accountPeerId: accountPeerId, previous: previous, local: local, remote: remote, merged: merged, serverLimit: wgPinnedServerLimit(.chats(groupId), accountPeerId: accountPeerId, transaction: transaction), transaction: transaction)
    for handler in WGPinnedChatsHooks.sync.handlers {
        if let result = handler(request) {
            return (result.stored, result.toServer)
        }
    }
    return (merged, merged)
}

func wgRecentSearchLimit(_ limit: Int) -> Int {
    if WGLimitHooks.recentSearchLimit.isEmpty {
        return limit
    }
    for handler in WGLimitHooks.recentSearchLimit.handlers {
        if let value = handler(limit) {
            return value
        }
    }
    return limit
}
