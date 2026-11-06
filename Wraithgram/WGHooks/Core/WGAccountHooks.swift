// Compiled into TelegramCore (filegroup //Wraithgram/WGHooks:TelegramCoreHookSources).
// Account lifecycle points. Called from Account.swift / AccountManager.swift.

import Foundation
import Postbox
import SwiftSignalKit
import WGCore

/// What a feature learns when an account starts in this process (app or extension).
public struct WGAccountStartContext {
    public let id: AccountRecordId
    public let peerId: PeerId
    public let basePath: String
    /// True for accounts started only to finish a logout or for a short extension task.
    public let isSupplementary: Bool
    public let postbox: Postbox
    public let network: Network
}

public enum WGAccountHooks {
    /// Observer. An account's state machinery is about to start; its Wraithgram settings
    /// (`WGAccountSetting`) are already loaded. Runs on the thread that creates the account.
    public static let accountWillStart = WGHookPoint<(WGAccountStartContext) -> Void>("account.willStart")

    /// Observer. The account is being removed (logged out); its directory is deleted afterwards.
    public static let accountWillBeRemoved = WGHookPoint<(AccountRecordId) -> Void>("account.willBeRemoved")

    /// The record id of the account whose own peer is `accountPeerId`, once it started in this
    /// process. Lets handlers that only get an account peer id (Core points) reach
    /// account-scoped settings: `WGAccountSetting.value(for: id.wg)`.
    public static func accountId(forAccountPeerId accountPeerId: PeerId) -> AccountRecordId? {
        return wgAccountIdsByPeerId.with { $0[accountPeerId] }
    }
}

private let wgAccountIdsByPeerId = Atomic<[PeerId: AccountRecordId]>(value: [:])

/// WRAITH hook target: first statement of `Account.init`, before the account's managers start.
func wgAccountWillStart(id: AccountRecordId, basePath: String, peerId: PeerId, supplementary: Bool, postbox: Postbox, network: Network) {
    // WGCore bridge (W1-1): loads <basePath>/wraithgram/settings.json and runs account migrations.
    wgCoreAccountDidLoad(id: id, basePath: basePath)
    // Then the migrations of old data keyed by the account's peer: before the handlers below, which
    // may already read what they moved (fake gifts).
    wgCoreAccountPeerDidLoad(id: id, peerId: peerId)
    let _ = wgAccountIdsByPeerId.modify { current in
        var current = current
        current[peerId] = id
        return current
    }
    if WGAccountHooks.accountWillStart.isEmpty {
        return
    }
    let context = WGAccountStartContext(id: id, peerId: peerId, basePath: basePath, isSupplementary: supplementary, postbox: postbox, network: network)
    for handler in WGAccountHooks.accountWillStart.handlers {
        handler(context)
    }
}

/// WRAITH hook target: `standaloneStateManager` (notification service) — no `Account` object
/// exists there, so the account's settings are loaded here, before its network starts.
func wgStandaloneAccountWillStart(id: AccountRecordId, basePath: String, peerId: PeerId) {
    wgCoreAccountDidLoad(id: id, basePath: basePath)
    wgCoreAccountPeerDidLoad(id: id, peerId: peerId)
    let _ = wgAccountIdsByPeerId.modify { current in
        var current = current
        current[peerId] = id
        return current
    }
}

/// WRAITH hook target: an account record is about to be removed for good (logout).
func wgAccountWillBeRemoved(id: AccountRecordId) {
    for handler in WGAccountHooks.accountWillBeRemoved.handlers {
        handler(id)
    }
    let _ = wgAccountIdsByPeerId.modify { current in
        return current.filter { $0.value != id }
    }
    wgCoreAccountWillBeRemoved(id: id)
}

/// The account peer id stored in the account's own Postbox state, for points that are called
/// without one (autoremove timers, interactive deletions without a state manager).
func wgAccountPeerId(transaction: Transaction) -> PeerId? {
    return (transaction.getState() as? AuthorizedAccountState)?.peerId
}
