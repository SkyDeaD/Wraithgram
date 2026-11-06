import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import WGCore

/// What the server knows about the account's reads, per chat (and per forum topic):
///
/// - **kept** — read on the device while ghost mode held the receipt (the server was told nothing);
/// - **server** — the highest id the server is known to have read (an allowed push, an explicit
///   «Прочитать», a read on action);
/// - **local** — «Прочитать локально»: kept on the device even with ghost mode off, but only up to that
///   id, so a later read of newer messages goes out normally.
///
/// The tables live in memory and are written behind on their own queue (one write per second at
/// most): the read hooks run inside Postbox transactions and on network queues, where no file or
/// settings write is allowed. Entries older than 30 days and the oldest beyond 2000 are dropped.
public final class WGGhostReadLedger {
    public static let shared = WGGhostReadLedger()

    private struct Tables {
        var kept: [String: WGGhostKeptRead]
        var server: [String: Int32]
        var local: [String: Int32]
    }

    private let tables = Atomic<[WGAccountID: Tables]>(value: [:])
    private let queue = Queue(name: "org.wraithgram.ghostMode.readLedger", qos: .utility)
    private var flushScheduled = Set<WGAccountID>()

    private let maxAge: Int32 = 30 * 24 * 60 * 60
    private let maxEntries = 2000

    private init() {
    }

    private static func now() -> Int32 {
        return Int32(Date().timeIntervalSince1970)
    }

    private func loaded(_ current: [WGAccountID: Tables], account: WGAccountID) -> Tables {
        if let tables = current[account] {
            return tables
        }
        let now = WGGhostReadLedger.now()
        var kept = WGGhostSettings.keptReads.value(for: account)
        kept = kept.filter { now - $0.value.date < self.maxAge }
        return Tables(kept: kept, server: WGGhostSettings.serverReads.value(for: account), local: WGGhostSettings.localReads.value(for: account))
    }

    private func update(_ account: WGAccountID, _ f: (inout Tables) -> Void) {
        var changed = false
        let _ = self.tables.modify { current in
            var current = current
            var tables = self.loaded(current, account: account)
            let keptBefore = tables.kept
            let serverBefore = tables.server
            let localBefore = tables.local
            f(&tables)
            if tables.kept.count > self.maxEntries {
                let sorted = tables.kept.sorted(by: { $0.value.date < $1.value.date })
                for (key, _) in sorted.prefix(tables.kept.count - self.maxEntries) {
                    tables.kept.removeValue(forKey: key)
                }
            }
            if tables.server.count > self.maxEntries * 2 {
                tables.server.removeAll()
            }
            if keptBefore != tables.kept {
                changed = true
            } else if serverBefore != tables.server {
                changed = true
            } else if localBefore != tables.local {
                changed = true
            }
            current[account] = tables
            return current
        }
        if changed {
            self.scheduleFlush(account)
        }
    }

    private func read<R>(_ account: WGAccountID, _ f: (Tables) -> R) -> R {
        let tables = self.tables.modify { current in
            if current[account] != nil {
                return current
            }
            var current = current
            current[account] = self.loaded(current, account: account)
            return current
        }[account]!
        return f(tables)
    }

    private func scheduleFlush(_ account: WGAccountID) {
        self.queue.async {
            if self.flushScheduled.contains(account) {
                return
            }
            self.flushScheduled.insert(account)
            self.queue.after(1.0, {
                self.flushScheduled.remove(account)
                guard let tables = self.tables.with({ $0[account] }) else {
                    return
                }
                WGGhostSettings.keptReads.set(tables.kept, for: account)
                WGGhostSettings.serverReads.set(tables.server, for: account)
                WGGhostSettings.localReads.set(tables.local, for: account)
            })
        }
    }

    func accountWillBeRemoved(_ account: WGAccountID) {
        let _ = self.tables.modify { current in
            var current = current
            current.removeValue(forKey: account)
            return current
        }
    }

    // MARK: Kept reads

    /// The receipt up to `maxId` stayed on the device.
    public func noteKept(account: WGAccountID, key: String, maxId: Int32, maxTimestamp: Int32) {
        self.update(account) { tables in
            if let server = tables.server[key], maxId <= server {
                return
            }
            let previous = tables.kept[key]
            tables.kept[key] = WGGhostKeptRead(maxId: max(maxId, previous?.maxId ?? 0), maxTimestamp: max(maxTimestamp, previous?.maxTimestamp ?? 0), date: WGGhostReadLedger.now())
        }
    }

    public func keptRead(account: WGAccountID, key: String) -> WGGhostKeptRead? {
        return self.read(account) { $0.kept[key] }
    }

    public func keptReads(account: WGAccountID) -> [String: WGGhostKeptRead] {
        return self.read(account) { $0.kept }
    }

    /// Kept reads of a chat and of its topics.
    public func keptReads(account: WGAccountID, peerId: PeerId) -> [String: WGGhostKeptRead] {
        let prefix = peerId.wgGhostKey
        return self.read(account) { tables in
            return tables.kept.filter { $0.key == prefix || $0.key.hasPrefix(prefix + "#") }
        }
    }

    public func hasKeptRead(account: WGAccountID, peerId: PeerId) -> Bool {
        return !self.keptReads(account: account, peerId: peerId).isEmpty
    }

    // MARK: Server reads

    /// The server now knows reads up to `maxId` (a push went out, or an explicit read).
    public func noteServerRead(account: WGAccountID, key: String, maxId: Int32) {
        self.update(account) { tables in
            tables.server[key] = max(maxId, tables.server[key] ?? 0)
            if let kept = tables.kept[key], kept.maxId <= maxId {
                tables.kept.removeValue(forKey: key)
            }
        }
    }

    public func serverReadMaxId(account: WGAccountID, key: String) -> Int32? {
        return self.read(account) { $0.server[key] }
    }

    /// A secret chat was read on the server up to this date.
    public func noteServerReadSecret(account: WGAccountID, key: String) {
        self.update(account) { tables in
            tables.kept.removeValue(forKey: key)
        }
    }

    // MARK: «Прочитать локально»

    public func addLocalReads(account: WGAccountID, _ entries: [String: Int32]) {
        self.update(account) { tables in
            for (key, maxId) in entries {
                tables.local[key] = max(maxId, tables.local[key] ?? 0)
            }
        }
    }

    public func localReadMaxId(account: WGAccountID, key: String) -> Int32? {
        return self.read(account) { $0.local[key] }
    }

    public func localReadCount(account: WGAccountID) -> Int {
        return self.read(account) { $0.local.count }
    }

    /// A read past the local-only mark is a new read: the mark has done its job.
    public func dropLocalRead(account: WGAccountID, key: String) {
        self.update(account) { tables in
            tables.local.removeValue(forKey: key)
        }
    }

    /// Everything the server does not know yet: kept reads and local-only marks.
    public func pendingKeys(account: WGAccountID) -> (kept: [String: WGGhostKeptRead], local: [String: Int32]) {
        return self.read(account) { ($0.kept, $0.local) }
    }

    public func clear(account: WGAccountID, keptKeys: [String], localKeys: [String]) {
        self.update(account) { tables in
            for key in keptKeys {
                tables.kept.removeValue(forKey: key)
            }
            for key in localKeys {
                tables.local.removeValue(forKey: key)
            }
        }
    }
}
