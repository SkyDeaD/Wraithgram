import Foundation
import XCTest

final class WGMigrationsTests: XCTestCase {
    private var directory: WGTestDirectory!
    private var suiteName: String!
    private var legacyStore: UserDefaults!

    override func setUp() {
        super.setUp()
        WGTestSettings.touchAll()
        self.directory = WGTestDirectory()
        WGSettingsStore.shared.resetForTesting(environment: self.directory.environment())
        WGMigrations.resetForTesting()
        self.suiteName = "GGCoreTests.legacy.\(UUID().uuidString)"
        self.legacyStore = UserDefaults(suiteName: self.suiteName)
    }

    override func tearDown() {
        WGMigrations.resetForTesting()
        self.legacyStore.removePersistentDomain(forName: self.suiteName)
        WGSettingsStore.shared.flushSynchronously()
        WGSettingsStore.shared.resetForTesting(environment: nil)
        self.directory.remove()
        super.tearDown()
    }

    private var legacy: WGLegacyDefaults {
        return WGLegacyDefaults(stores: [self.legacyStore])
    }

    func testGlobalMigrationRunsOnceAndIsRemembered() {
        self.legacyStore.set(true, forKey: "GhostMode.hideReadReceipts")
        var runs = 0
        WGMigrations.registerGlobal(id: "test.v1") { legacy in
            runs += 1
            if let value = legacy.bool("GhostMode.hideReadReceipts") {
                WGTestSettings.toggle.set(value)
                legacy.removeLegacyKey("GhostMode.hideReadReceipts")
            }
        }
        WGMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(runs, 1)
        XCTAssertTrue(WGTestSettings.toggle.value)
        XCTAssertNil(self.legacyStore.object(forKey: "GhostMode.hideReadReceipts"))

        WGMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(runs, 1)

        // The flag survives a relaunch.
        WGSettingsStore.shared.flushSynchronously()
        WGSettingsStore.shared.resetForTesting(environment: self.directory.environment())
        WGMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(runs, 1)
        XCTAssertTrue(WGMigrations.completedGlobal.value.contains("test.v1"))
    }

    func testMigrationsDoNotRunInExtensions() {
        WGSettingsStore.shared.resetForTesting(environment: self.directory.environment(process: .share))
        var runs = 0
        WGMigrations.registerGlobal(id: "test.extension") { _ in
            runs += 1
        }
        WGMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(runs, 0)
    }

    func testAccountMigrationRunsPerAccount() {
        let first = WGAccountID(rawValue: 11)
        let second = WGAccountID(rawValue: 12)
        WGSettingsStore.shared.registerAccount(first, basePath: self.directory.makeDirectory("a11"))
        var seen: [WGAccountID] = []
        WGMigrations.registerAccount(id: "test.account.v1") { _, account in
            seen.append(account)
            WGTestSettings.accountToggle.set(true, for: account)
        }
        WGMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(seen, [first])
        XCTAssertTrue(WGTestSettings.accountToggle.value(for: first))

        WGSettingsStore.shared.registerAccount(second, basePath: self.directory.makeDirectory("a12"))
        WGMigrations.runPendingAccountMigrations(for: second, legacy: self.legacy)
        XCTAssertEqual(seen, [first, second])

        WGMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(seen, [first, second])
    }

    func testAccountPeerMigrationRunsOnceThePeerIsKnown() {
        let account = WGAccountID(rawValue: 21)
        let peer = WGLegacyKeys.peerKey(fromLegacyInt64: 777000)
        WGSettingsStore.shared.registerAccount(account, basePath: self.directory.makeDirectory("a21"))
        var seen: [(WGAccountID, WGPeerKey)] = []
        WGMigrations.registerAccountPeer(id: "test.accountPeer.v1") { _, account, peer in
            seen.append((account, peer))
            WGTestSettings.accountToggle.set(true, for: account)
        }

        // The peer is not known yet: nothing runs and nothing is marked done.
        WGMigrations.runPending(legacy: self.legacy)
        XCTAssertTrue(seen.isEmpty)
        XCTAssertFalse(WGMigrations.completedAccount.value(for: account).contains("test.accountPeer.v1"))

        WGMigrations.accountPeerDidLoad(account, peer: peer)
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.0, account)
        XCTAssertEqual(seen.first?.1, peer)
        XCTAssertTrue(WGTestSettings.accountToggle.value(for: account))

        // Once per account: neither a restart of the account nor the global pass run it again.
        WGMigrations.accountPeerDidLoad(account, peer: peer)
        WGMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(seen.count, 1)
        XCTAssertTrue(WGMigrations.completedAccount.value(for: account).contains("test.accountPeer.v1"))
    }

    func testAccountPeerMigrationOfAKnownPeerRunsFromTheGlobalPass() {
        let account = WGAccountID(rawValue: 22)
        let peer = WGLegacyKeys.peerKey(fromLegacyInt64: 777001)
        WGSettingsStore.shared.registerAccount(account, basePath: self.directory.makeDirectory("a22"))
        WGMigrations.accountPeerDidLoad(account, peer: peer)
        var runs = 0
        WGMigrations.registerAccountPeer(id: "test.accountPeer.late") { _, _, _ in
            runs += 1
        }
        WGMigrations.runPending(legacy: self.legacy)
        XCTAssertEqual(runs, 1)
    }

    func testLegacyDefaultsTypedReaders() {
        self.legacyStore.set(true, forKey: "b")
        self.legacyStore.set("1", forKey: "bs")
        self.legacyStore.set(42, forKey: "i")
        self.legacyStore.set("43", forKey: "is")
        self.legacyStore.set(1.5, forKey: "d")
        self.legacyStore.set("text", forKey: "s")
        self.legacyStore.set(Data([1, 2]), forKey: "data")
        self.legacyStore.set(["a", "b"], forKey: "sa")
        self.legacyStore.set(["a", 1] as [Any], forKey: "mixed")

        let legacy = self.legacy
        XCTAssertEqual(legacy.bool("b"), true)
        XCTAssertEqual(legacy.bool("bs"), true)
        XCTAssertEqual(legacy.int("i"), 42)
        XCTAssertEqual(legacy.int("is"), 43)
        XCTAssertEqual(legacy.double("d"), 1.5)
        XCTAssertEqual(legacy.string("s"), "text")
        XCTAssertNil(legacy.string("i"))
        XCTAssertEqual(legacy.data("data"), Data([1, 2]))
        XCTAssertEqual(legacy.stringArray("sa"), ["a", "b"])
        XCTAssertNil(legacy.stringArray("mixed"))
        XCTAssertNil(legacy.bool("absent"))
    }

    func testLegacyAccountProfileKey() {
        XCTAssertEqual(WGLegacyDefaults.sanitizedAccountText(WGAccountID(rawValue: 123)), "AccountRecordId_rawValue__123_")
        XCTAssertEqual(WGLegacyDefaults.sanitizedAccountText(WGAccountID(rawValue: -5)), "AccountRecordId_rawValue___5_")

        let profile: [String: Any] = ["GhostMode.isEnabled": true]
        self.legacyStore.set(profile, forKey: "GG.accountConfigs.snapshots.ghostgram.AccountRecordId_rawValue__123_")
        let loaded = self.legacy.legacyAccountProfile(for: WGAccountID(rawValue: 123))
        XCTAssertEqual(loaded?["GhostMode.isEnabled"] as? Bool, true)
        XCTAssertNil(self.legacy.legacyAccountProfile(for: WGAccountID(rawValue: 124)))
    }

    /// With the old profiles on, the shared keys belong to the active account only.
    func testLegacyAccountValue() {
        let active = WGAccountID(rawValue: 123)
        let other = WGAccountID(rawValue: 124)
        let otherWithProfile = WGAccountID(rawValue: 125)
        self.legacyStore.set("777", forKey: "GG.hyperlinkSpoof.targetId")
        self.legacyStore.set(["GG.hyperlinkSpoof.targetId": "555"], forKey: "GG.accountConfigs.snapshots.ghostgram.AccountRecordId_rawValue__123_")
        self.legacyStore.set(["GhostMode.isEnabled": true], forKey: "GG.accountConfigs.snapshots.ghostgram.AccountRecordId_rawValue__125_")

        // Profiles off: everybody has the shared value.
        XCTAssertEqual(self.legacy.legacyAccountValue("GG.hyperlinkSpoof.targetId", for: active) as? String, "777")
        XCTAssertEqual(self.legacy.legacyAccountValue("GG.hyperlinkSpoof.targetId", for: other) as? String, "777")

        self.legacyStore.set(true, forKey: "GG.accountConfigs.enabled.ghostgram")
        self.legacyStore.set("AccountRecordId_rawValue__123_", forKey: "GG.accountConfigs.activeAccountId.ghostgram")
        // The active account: the live shared value, not its older profile.
        XCTAssertEqual(self.legacy.legacyAccountValue("GG.hyperlinkSpoof.targetId", for: active) as? String, "777")
        // Others: their profile only.
        XCTAssertNil(self.legacy.legacyAccountValue("GG.hyperlinkSpoof.targetId", for: other))
        XCTAssertNil(self.legacy.legacyAccountValue("GG.hyperlinkSpoof.targetId", for: otherWithProfile))
        XCTAssertEqual(self.legacy.legacyAccountValue("GhostMode.isEnabled", for: otherWithProfile) as? Bool, true)
    }
}
