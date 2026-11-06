// Compiled into TelegramCore (filegroup //Wraithgram/WGCore:TelegramCoreBridgeSources): the parts of
// WGCore that need TelegramCore / Postbox types. WGCore itself can not see them, since
// TelegramCore depends on WGCore.

import Foundation
import Postbox
import SwiftSignalKit
import WGCore

// MARK: - Canonical keys

public extension AccountRecordId {
    /// The account's Wraithgram key (same raw value).
    var wg: WGAccountID {
        return WGAccountID(rawValue: self.int64)
    }

    init(wg: WGAccountID) {
        self.init(rawValue: wg.rawValue)
    }
}

public extension PeerId {
    /// The whole PeerId, namespace included. Use this, never `toInt64()`, as a stored key.
    var wgKey: WGPeerKey {
        guard let key = WGPeerKey(namespace: self.namespace._internalGetInt32Value(), id: self.id._internalGetInt64Value()) else {
            preconditionFailure("PeerId namespace out of range")
        }
        return key
    }

    init(wgKey: WGPeerKey) {
        self.init(namespace: PeerId.Namespace._internalFromInt32Value(wgKey.namespace), id: PeerId.Id._internalFromInt64Value(wgKey.id))
    }
}

public extension MessageId {
    /// Peer, message namespace and id.
    var wgKey: WGMessageKey {
        return WGMessageKey(peer: self.peerId.wgKey, namespace: self.namespace, id: self.id)
    }

    init(wgKey: WGMessageKey) {
        self.init(peerId: PeerId(wgKey: wgKey.peer), namespace: wgKey.namespace, id: wgKey.id)
    }
}

// MARK: - Account lifecycle

/// WRAITH hook target: call from `Account.init`, before the account's network starts. Loads the
/// account's Wraithgram settings (`<basePath>/wraithgram/settings.json`) and runs its migrations.
public func wgCoreAccountDidLoad(id: AccountRecordId, basePath: String) {
    #if DEBUG
    wgCoreBridgeSelfCheckOnce()
    #endif
    WGSettingsStore.shared.registerAccount(id.wg, basePath: basePath)
}

/// WRAITH hook target: call right after `wgCoreAccountDidLoad`, once the account's own peer is known
/// (`Account.init`, the notification service's standalone state manager). Runs the account's
/// migrations of old data keyed by that peer (`WGMigrations.registerAccountPeer`, app only).
public func wgCoreAccountPeerDidLoad(id: AccountRecordId, peerId: PeerId) {
    WGMigrations.accountPeerDidLoad(id.wg, peer: peerId.wgKey)
}

/// WRAITH hook target: call when the account is logged out / removed.
public func wgCoreAccountWillBeRemoved(id: AccountRecordId) {
    WGSettingsStore.shared.unregisterAccount(id.wg)
}

// MARK: - Proxy for WGNetwork

/// The SOCKS5 proxy for Wraithgram's own requests, or nil (MTProxy and WEB proxies can not carry
/// a `URLSession` request).
public func wgProxy(from server: ProxyServerSettings?) -> WGProxy? {
    guard let server = server else {
        return nil
    }
    switch server.connection {
    case let .socks5(username, password):
        return .socks5(host: server.host, port: Int(server.port), username: username, password: password)
    case .mtp, .web:
        return nil
    }
}

private struct WGProxyBridgeState {
    let proxy: WGProxy?
    let isDirectConnectionAllowed: Bool
}

private let wgProxyBridgeState = Atomic<WGProxyBridgeState>(value: WGProxyBridgeState(proxy: nil, isDirectConnectionAllowed: true))
private let wgProxyBridgeAttached = Atomic<Bool>(value: false)
private let wgProxyBridgeDisposable = MetaDisposable()

/// WRAITH hook target: call once after the `AccountManager` is created (app and extensions).
/// Keeps `WGNetwork.shared` on the user's active proxy: SOCKS5 is used, any other active proxy
/// blocks direct requests. Later calls do nothing.
public func wgCoreAttachProxySettings(accountManager: AccountManager<TelegramAccountManagerTypes>) {
    if wgProxyBridgeAttached.swap(true) {
        return
    }
    WGNetwork.shared.proxyProvider = {
        return wgProxyBridgeState.with { state in
            return state.proxy
        }
    }
    WGNetwork.shared.isDirectConnectionAllowedProvider = {
        return wgProxyBridgeState.with { state in
            return state.isDirectConnectionAllowed
        }
    }
    wgProxyBridgeDisposable.set((accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
    |> map { sharedData -> ProxyServerSettings? in
        return sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self)?.effectiveActiveServer
    }
    |> distinctUntilChanged).start(next: { server in
        let state = WGProxyBridgeState(proxy: wgProxy(from: server), isDirectConnectionAllowed: server == nil)
        let _ = wgProxyBridgeState.swap(state)
    }))
}

// MARK: - Debug self-check

#if DEBUG
private let wgCoreBridgeSelfChecked = Atomic<Bool>(value: false)

/// WGLegacyKeys mirrors the bit layout of `PeerId(Int64)`; make sure it still does.
private func wgCoreBridgeSelfCheckOnce() {
    if wgCoreBridgeSelfChecked.swap(true) {
        return
    }
    let samples: [PeerId] = [
        PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(777000)),
        PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(123456789)),
        PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(1234567890123)),
        PeerId(namespace: Namespaces.Peer.SecretChat, id: PeerId.Id._internalFromInt64Value(-5)),
        PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(5000000000))
    ]
    for peerId in samples {
        assert(WGLegacyKeys.peerKey(fromLegacyInt64: peerId.toInt64()) == peerId.wgKey, "WGLegacyKeys diverged from PeerId(Int64)")
        assert(WGLegacyKeys.legacyInt64(of: peerId.wgKey) == peerId.toInt64(), "WGLegacyKeys diverged from PeerId.toInt64()")
        assert(PeerId(wgKey: peerId.wgKey) == peerId, "PeerId(wgKey:) does not round-trip")
    }
}
#endif
