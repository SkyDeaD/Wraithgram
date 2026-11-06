import Foundation
import SwiftSignalKit
import XCTest

/// Settings used only by these tests. Declared once: a second declaration of a key asserts.
enum WGTestSettings {
    static let toggle = WGSetting<Bool>("test.toggle", default: false)
    static let counter = WGSetting<Int>("test.counter", default: 7)
    static let title = WGSetting<String>("test.title", default: "")
    static let optionalText = WGSetting<String?>("test.optionalText", default: nil)
    static let list = WGSetting<[String]>("test.list", default: [])
    static let peers = WGSetting<Set<WGPeerKey>>("test.peers", default: [])
    static let shared = WGSetting<Bool>("test.sharedFlag", default: false, scope: .appGroup, flags: [.extensions])
    static let secret = WGSetting<String>("test.secret", default: "", flags: [.noExport])
    static let restart = WGSetting<Bool>("test.restart", default: false, flags: [.requiresRestart])
    static let exceptions = WGAccountSetting<[String]>("test.exceptions", default: [])
    static let accountToggle = WGAccountSetting<Bool>("test.accountToggle", default: false)
    static let accountSecret = WGAccountSetting<String>("test.accountSecret", default: "", flags: [.noExport])

    static func touchAll() {
        let _ = WGTestSettings.toggle
        let _ = WGTestSettings.counter
        let _ = WGTestSettings.title
        let _ = WGTestSettings.optionalText
        let _ = WGTestSettings.list
        let _ = WGTestSettings.peers
        let _ = WGTestSettings.shared
        let _ = WGTestSettings.secret
        let _ = WGTestSettings.restart
        let _ = WGTestSettings.exceptions
        let _ = WGTestSettings.accountToggle
        let _ = WGTestSettings.accountSecret
    }
}

final class WGSettingsStoreTests: XCTestCase {
    private var directory: WGTestDirectory!

    override func setUp() {
        super.setUp()
        WGTestSettings.touchAll()
        self.directory = WGTestDirectory()
        WGSettingsStore.shared.resetForTesting(environment: self.directory.environment())
    }

    override func tearDown() {
        WGSettingsStore.shared.flushSynchronously()
        WGSettingsStore.shared.resetForTesting(environment: nil)
        self.directory.remove()
        self.directory = nil
        super.tearDown()
    }

    private func reload(process: WGProcessKind = .app) {
        WGSettingsStore.shared.flushSynchronously()
        WGSettingsStore.shared.resetForTesting(environment: self.directory.environment(process: process))
    }

    // MARK: - Values and signals

    func testDefaultSetResetAndIsDefault() {
        XCTAssertEqual(WGTestSettings.counter.value, 7)
        XCTAssertTrue(WGTestSettings.counter.isDefault)

        WGTestSettings.counter.set(42)
        XCTAssertEqual(WGTestSettings.counter.value, 42)
        XCTAssertFalse(WGTestSettings.counter.isDefault)

        WGTestSettings.counter.reset()
        XCTAssertEqual(WGTestSettings.counter.value, 7)
        XCTAssertTrue(WGTestSettings.counter.isDefault)
    }

    func testOptionalAndCollectionValues() {
        WGTestSettings.optionalText.set("a")
        WGTestSettings.list.set(["x", "y"])
        let peer = WGPeerKey(namespace: 2, id: 1234567890)!
        WGTestSettings.peers.set([peer])
        self.reload()
        XCTAssertEqual(WGTestSettings.optionalText.value, "a")
        XCTAssertEqual(WGTestSettings.list.value, ["x", "y"])
        XCTAssertEqual(WGTestSettings.peers.value, [peer])

        WGTestSettings.optionalText.set(nil)
        self.reload()
        XCTAssertNil(WGTestSettings.optionalText.value)
    }

    func testSignalDeliversCurrentValueThenDistinctChanges() {
        WGTestSettings.counter.set(1)
        let recorder = WGSignalRecorder(WGTestSettings.counter.signal)
        WGTestSettings.counter.set(2)
        WGTestSettings.counter.set(2)
        WGTestSettings.counter.set(3)
        WGTestSettings.counter.set(1)
        XCTAssertEqual(recorder.values, [1, 2, 3, 1])
        recorder.dispose()
        WGTestSettings.counter.set(9)
        XCTAssertEqual(recorder.values, [1, 2, 3, 1])
    }

    func testRevisionGrowsOnEveryChange() {
        let recorder = WGSignalRecorder(WGSettingsStore.shared.revision)
        XCTAssertEqual(recorder.values.count, 1)
        WGTestSettings.toggle.set(true)
        WGTestSettings.toggle.set(true)
        WGTestSettings.title.set("x")
        let values = recorder.values
        XCTAssertEqual(values.count, 3)
        XCTAssertTrue(values[1] > values[0] && values[2] > values[1])
        recorder.dispose()
    }

    // MARK: - Files

    func testGlobalValueIsWrittenAndReloaded() {
        WGTestSettings.title.set("hello")
        WGSettingsStore.shared.flushSynchronously()
        let stored = self.directory.storedValues(self.directory.globalFilePath)
        XCTAssertEqual(stored?["test.title"] as? String, "hello")

        WGSettingsStore.shared.resetForTesting(environment: nil)
        XCTAssertEqual(WGTestSettings.title.value, "")
        WGSettingsStore.shared.resetForTesting(environment: self.directory.environment())
        XCTAssertEqual(WGTestSettings.title.value, "hello")
    }

    func testDefaultValuesAreNotWritten() {
        WGTestSettings.toggle.set(true)
        WGSettingsStore.shared.flushSynchronously()
        XCTAssertEqual(self.directory.storedValues(self.directory.globalFilePath)?["test.toggle"] as? Bool, true)

        WGTestSettings.toggle.set(false)
        WGSettingsStore.shared.flushSynchronously()
        let stored = self.directory.storedValues(self.directory.globalFilePath)
        XCTAssertNotNil(stored)
        XCTAssertNil(stored?["test.toggle"])
    }

    func testUnknownKeysSurviveRewrite() {
        self.directory.writeFile(self.directory.globalFilePath, "{\"version\":1,\"values\":{\"future.feature\":{\"a\":[1,2]},\"test.counter\":11}}")
        self.reload()
        XCTAssertEqual(WGTestSettings.counter.value, 11)

        WGTestSettings.counter.set(12)
        WGSettingsStore.shared.flushSynchronously()
        let stored = self.directory.storedValues(self.directory.globalFilePath)
        XCTAssertEqual(stored?["test.counter"] as? Int, 12)
        let future = stored?["future.feature"] as? [String: Any]
        XCTAssertEqual(future?["a"] as? [Int], [1, 2])
    }

    func testWritesAreCoalesced() {
        for value in 0 ..< 50 {
            WGTestSettings.counter.set(100 + value)
        }
        // Nothing is on disk before the coalescing delay.
        XCTAssertNil(self.directory.storedValues(self.directory.globalFilePath))

        let written = self.expectation(description: "coalesced write")
        DispatchQueue.main.asyncAfter(deadline: .now() + WGSettingsStore.coalescingDelay + 0.5) {
            written.fulfill()
        }
        self.wait(for: [written], timeout: 5.0)
        WGSettingsStore.shared.flushSynchronously()
        XCTAssertEqual(self.directory.storedValues(self.directory.globalFilePath)?["test.counter"] as? Int, 149)
    }

    func testFlushWritesWithoutWaitingForTheDelay() {
        WGTestSettings.counter.set(5)
        WGSettingsStore.shared.flush()
        WGSettingsStore.shared.flushSynchronously()
        XCTAssertEqual(self.directory.storedValues(self.directory.globalFilePath)?["test.counter"] as? Int, 5)
    }

    func testAppGroupScopeGoesToSharedFile() {
        WGTestSettings.shared.set(true)
        WGSettingsStore.shared.flushSynchronously()
        XCTAssertEqual(self.directory.storedValues(self.directory.sharedFilePath)?["test.sharedFlag"] as? Bool, true)
        XCTAssertNil(self.directory.storedValues(self.directory.globalFilePath)?["test.sharedFlag"])
    }

    func testExtensionReadsOnlyTheSharedFile() {
        WGTestSettings.shared.set(true)
        WGTestSettings.title.set("app only")
        self.reload(process: .notificationService)
        XCTAssertTrue(WGTestSettings.shared.value)
        XCTAssertEqual(WGTestSettings.title.value, "")
    }

    /// iOS keeps the notification service's process between pushes while the app changes the files:
    /// the extension reads them again on the next push (shared.json and the push account's file).
    func testExtensionReadsChangedFilesAgain() {
        let account = WGAccountID(rawValue: 303)
        let basePath = self.directory.makeDirectory("telegram-data", "account-303")
        let accountFile = WGSettingsStore.accountFilePath(basePath: basePath)
        WGSettingsStore.shared.registerAccount(account, basePath: basePath)
        WGTestSettings.shared.set(true)
        WGTestSettings.accountToggle.set(true, for: account)
        self.reload(process: .notificationService)
        WGSettingsStore.shared.registerAccount(account, basePath: basePath)
        XCTAssertTrue(WGTestSettings.shared.value)
        XCTAssertTrue(WGTestSettings.accountToggle.value(for: account))

        let recorder = WGSignalRecorder(WGTestSettings.shared.signal)
        self.directory.writeFile(self.directory.sharedFilePath, "{\"version\":1,\"values\":{}}")
        self.directory.writeFile(accountFile, "{\"version\":1,\"values\":{}}")
        WGSettingsStore.shared.reloadFromDisk()
        XCTAssertFalse(WGTestSettings.shared.value)
        XCTAssertFalse(WGTestSettings.accountToggle.value(for: account))
        XCTAssertEqual(recorder.values, [true, false])
        recorder.dispose()

        // The next push registers the account again: its file is read again too.
        self.directory.writeFile(accountFile, "{\"version\":1,\"values\":{\"test.accountToggle\":true}}")
        WGSettingsStore.shared.registerAccount(account, basePath: basePath)
        XCTAssertTrue(WGTestSettings.accountToggle.value(for: account))
        // Extensions still never write.
        XCTAssertEqual(self.directory.storedValues(accountFile)?["test.accountToggle"] as? Bool, true)
    }

    /// In the app memory is the truth (it may hold changes not written yet): no reload.
    func testAppDoesNotReloadFromDisk() {
        WGTestSettings.shared.set(true)
        self.directory.writeFile(self.directory.sharedFilePath, "{\"version\":1,\"values\":{}}")
        WGSettingsStore.shared.reloadFromDisk()
        XCTAssertTrue(WGTestSettings.shared.value)
    }

    func testDamagedFileIsMovedAsideAndDefaultsAreUsed() {
        self.directory.writeFile(self.directory.globalFilePath, "{not json")
        self.reload()
        XCTAssertEqual(WGTestSettings.counter.value, 7)
        XCTAssertTrue(FileManager.default.fileExists(atPath: self.directory.globalFilePath + ".damaged"))

        WGTestSettings.counter.set(8)
        WGSettingsStore.shared.flushSynchronously()
        XCTAssertEqual(self.directory.storedValues(self.directory.globalFilePath)?["test.counter"] as? Int, 8)
    }

    func testNewerFileFormatIsNeverOverwritten() {
        let text = "{\"version\":2,\"values\":{\"test.counter\":21}}"
        self.directory.writeFile(self.directory.globalFilePath, text)
        self.reload()
        XCTAssertEqual(WGTestSettings.counter.value, 21)
        WGTestSettings.counter.set(22)
        WGSettingsStore.shared.flushSynchronously()
        let data = FileManager.default.contents(atPath: self.directory.globalFilePath)
        XCTAssertEqual(data.map { String(decoding: $0, as: UTF8.self) }, text)
    }

    func testStoredValueOfAnotherTypeReadsTheDefault() {
        self.directory.writeFile(self.directory.globalFilePath, "{\"version\":1,\"values\":{\"test.counter\":\"seven\"}}")
        self.reload()
        XCTAssertEqual(WGTestSettings.counter.value, 7)
    }

    // MARK: - Accounts

    func testAccountValuesAreSeparateAndLiveInTheAccountDirectory() {
        let first = WGAccountID(rawValue: 101)
        let second = WGAccountID(rawValue: -202)
        let firstPath = self.directory.makeDirectory("telegram-data", "account-101")
        let secondPath = self.directory.makeDirectory("telegram-data", "account-202")
        WGSettingsStore.shared.registerAccount(first, basePath: firstPath)
        WGSettingsStore.shared.registerAccount(second, basePath: secondPath)
        XCTAssertEqual(WGSettingsStore.shared.registeredAccounts, [second, first])

        WGTestSettings.exceptions.set(["0:1"], for: first)
        XCTAssertEqual(WGTestSettings.exceptions.value(for: first), ["0:1"])
        XCTAssertEqual(WGTestSettings.exceptions.value(for: second), [])
        XCTAssertTrue(WGTestSettings.exceptions.isDefault(for: second))

        WGSettingsStore.shared.flushSynchronously()
        let firstFile = WGSettingsStore.accountFilePath(basePath: firstPath)
        XCTAssertEqual(self.directory.storedValues(firstFile)?["test.exceptions"] as? [String], ["0:1"])
        XCTAssertNil(self.directory.storedValues(WGSettingsStore.accountFilePath(basePath: secondPath)))
        XCTAssertNil(self.directory.storedValues(self.directory.globalFilePath)?["test.exceptions"])

        WGSettingsStore.shared.unregisterAccount(first)
        XCTAssertEqual(WGTestSettings.exceptions.value(for: first), [])
        WGSettingsStore.shared.registerAccount(first, basePath: firstPath)
        XCTAssertEqual(WGTestSettings.exceptions.value(for: first), ["0:1"])
    }

    func testAccountSignalIsPerAccount() {
        let first = WGAccountID(rawValue: 1)
        let second = WGAccountID(rawValue: 2)
        WGSettingsStore.shared.registerAccount(first, basePath: self.directory.makeDirectory("a1"))
        WGSettingsStore.shared.registerAccount(second, basePath: self.directory.makeDirectory("a2"))
        let recorder = WGSignalRecorder(WGTestSettings.accountToggle.signal(for: first))
        WGTestSettings.accountToggle.set(true, for: second)
        WGTestSettings.accountToggle.set(true, for: first)
        WGTestSettings.accountToggle.set(false, for: first)
        XCTAssertEqual(recorder.values, [false, true, false])
        recorder.dispose()
    }

    func testWriteForUnregisteredAccountIsIgnored() {
        let account = WGAccountID(rawValue: 77)
        WGTestSettings.accountToggle.set(true, for: account)
        XCTAssertFalse(WGTestSettings.accountToggle.value(for: account))
    }

    func testRemovedAccountDirectoryIsNotRecreated() {
        let account = WGAccountID(rawValue: 5)
        let basePath = self.directory.makeDirectory("telegram-data", "account-5")
        WGSettingsStore.shared.registerAccount(account, basePath: basePath)
        WGTestSettings.accountToggle.set(true, for: account)
        try? FileManager.default.removeItem(atPath: basePath)
        WGSettingsStore.shared.unregisterAccount(account)
        WGSettingsStore.shared.flushSynchronously()
        XCTAssertFalse(FileManager.default.fileExists(atPath: basePath))
    }

    // MARK: - Export / import / reset

    func testExportSkipsSecretsAndImportRestores() {
        let account = WGAccountID(rawValue: 9)
        WGSettingsStore.shared.registerAccount(account, basePath: self.directory.makeDirectory("acc9"))
        WGTestSettings.counter.set(33)
        WGTestSettings.title.set("exported")
        WGTestSettings.secret.set("hash")
        WGTestSettings.exceptions.set(["2:5"], for: account)
        WGTestSettings.accountSecret.set("token", for: account)

        let data = WGSettingsStore.shared.exportData(accounts: [account])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("test.secret"))
        XCTAssertFalse(text.contains("test.accountSecret"))
        XCTAssertTrue(text.contains("test.counter"))

        WGSettingsStore.shared.resetAll(accounts: [account])
        XCTAssertEqual(WGTestSettings.counter.value, 7)
        XCTAssertEqual(WGTestSettings.exceptions.value(for: account), [])
        // Secrets survive "reset all".
        XCTAssertEqual(WGTestSettings.secret.value, "hash")
        XCTAssertEqual(WGTestSettings.accountSecret.value(for: account), "token")

        let diff: WGSettingsImportDiff
        do {
            diff = try WGSettingsStore.shared.importPreview(data)
        } catch {
            XCTFail("import preview failed: \(error)")
            return
        }
        let counterChange = diff.changes.first(where: { $0.key == "test.counter" })
        XCTAssertEqual(counterChange?.oldValue, "7")
        XCTAssertEqual(counterChange?.newValue, "33")
        XCTAssertEqual(counterChange?.scope, .global)
        let accountChange = diff.changes.first(where: { $0.key == "test.exceptions" })
        XCTAssertEqual(accountChange?.account, account)
        XCTAssertEqual(accountChange?.scope, .account)
        XCTAssertNil(diff.changes.first(where: { $0.key == "test.toggle" }), "unchanged values are not in the diff")

        WGSettingsStore.shared.applyImport(diff)
        XCTAssertEqual(WGTestSettings.counter.value, 33)
        XCTAssertEqual(WGTestSettings.title.value, "exported")
        XCTAssertEqual(WGTestSettings.exceptions.value(for: account), ["2:5"])
    }

    func testImportBumpsRevisionOnce() {
        WGTestSettings.counter.set(1)
        WGTestSettings.title.set("a")
        let data = WGSettingsStore.shared.exportData(accounts: [])
        WGSettingsStore.shared.resetAll(accounts: [])
        let diff = try? WGSettingsStore.shared.importPreview(data)
        XCTAssertEqual(diff?.changes.count, 2)
        let recorder = WGSignalRecorder(WGSettingsStore.shared.revision)
        if let diff = diff {
            WGSettingsStore.shared.applyImport(diff)
        }
        XCTAssertEqual(recorder.values.count, 2)
        recorder.dispose()
    }

    func testImportAcceptsFilesExportedAsGhostgram() {
        WGTestSettings.counter.set(1)
        let exported = String(decoding: WGSettingsStore.shared.exportData(accounts: []), as: UTF8.self)
        let old = exported.replacingOccurrences(of: "\"wraithgram.settings\"", with: "\"ghostgram.settings\"")
        XCTAssertNotEqual(old, exported)
        WGSettingsStore.shared.resetAll(accounts: [])
        let diff = try? WGSettingsStore.shared.importPreview(Data(old.utf8))
        XCTAssertNotNil(diff)
        XCTAssertEqual(diff?.changes.count, 1)
    }

    func testImportRejectsForeignAndNewerFiles() {
        XCTAssertThrowsError(try WGSettingsStore.shared.importPreview(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? WGSettingsImportError, .invalidFormat)
        }
        XCTAssertThrowsError(try WGSettingsStore.shared.importPreview(Data("{\"format\":\"other\",\"version\":1}".utf8))) { error in
            XCTAssertEqual(error as? WGSettingsImportError, .invalidFormat)
        }
        XCTAssertThrowsError(try WGSettingsStore.shared.importPreview(Data("{\"format\":\"wraithgram.settings\",\"version\":2}".utf8))) { error in
            XCTAssertEqual(error as? WGSettingsImportError, .unsupportedVersion(2))
        }
    }

    func testImportSortsOutUnknownSecretAndMistypedKeys() {
        let text = """
        {"format":"wraithgram.settings","version":1,
         "global":{"test.counter":"many","test.secret":"stolen","nobody.knows":1,"test.toggle":true},
         "appGroup":{},"accounts":{}}
        """
        guard let diff = try? WGSettingsStore.shared.importPreview(Data(text.utf8)) else {
            XCTFail("import preview failed")
            return
        }
        XCTAssertEqual(diff.unknownKeys, ["nobody.knows"])
        XCTAssertEqual(diff.skippedKeys, ["test.counter", "test.secret"])
        XCTAssertEqual(diff.changes.map { $0.key }, ["test.toggle"])
        WGSettingsStore.shared.applyImport(diff)
        XCTAssertEqual(WGTestSettings.secret.value, "")
        XCTAssertTrue(WGTestSettings.toggle.value)
    }

    func testImportMapsTheOnlyAccountSection() {
        let here = WGAccountID(rawValue: 1000)
        WGSettingsStore.shared.registerAccount(here, basePath: self.directory.makeDirectory("acc1000"))
        let text = """
        {"format":"wraithgram.settings","version":1,"global":{},"appGroup":{},
         "accounts":{"555":{"test.accountToggle":true}}}
        """
        guard let diff = try? WGSettingsStore.shared.importPreview(Data(text.utf8)) else {
            XCTFail("import preview failed")
            return
        }
        XCTAssertEqual(diff.unmatchedAccounts, [])
        XCTAssertEqual(diff.changes.first?.account, here)

        let other = WGAccountID(rawValue: 2000)
        WGSettingsStore.shared.registerAccount(other, basePath: self.directory.makeDirectory("acc2000"))
        guard let ambiguous = try? WGSettingsStore.shared.importPreview(Data(text.utf8)) else {
            XCTFail("import preview failed")
            return
        }
        XCTAssertEqual(ambiguous.unmatchedAccounts, [WGAccountID(rawValue: 555)])
        guard let mapped = try? WGSettingsStore.shared.importPreview(Data(text.utf8), accountMapping: [WGAccountID(rawValue: 555): other]) else {
            XCTFail("import preview failed")
            return
        }
        XCTAssertEqual(mapped.changes.first?.account, other)
    }

    // MARK: - Registry

    func testRegistryKnowsDeclaredSettings() {
        let _ = WGLocalization.languageOverride
        let keys = WGSettingsStore.shared.registeredKeys
        XCTAssertTrue(keys.contains("test.toggle"))
        XCTAssertTrue(keys.contains("test.exceptions"))
        XCTAssertTrue(keys.contains("core.language"))
        XCTAssertTrue(WGTestSettings.restart.flags.contains(.requiresRestart))
        XCTAssertEqual(WGTestSettings.shared.scope, .appGroup)
    }

    #if DEBUG
    func testUnreadSettingsAreReported() {
        let _ = WGTestSettings.toggle.value
        let unread = WGSettingsStore.shared.debugUnreadKeys()
        XCTAssertFalse(unread.contains("test.toggle"))
        XCTAssertTrue(unread.contains("test.restart"), "declared, shown in a menu, never read: a dead toggle")
    }
    #endif

    func testKeyValidation() {
        XCTAssertTrue(WGSettingsStore.isValidKey("ghostMode.hideReadReceipts"))
        XCTAssertTrue(WGSettingsStore.isValidKey("a.b.c2"))
        XCTAssertFalse(WGSettingsStore.isValidKey("ghostMode"))
        XCTAssertFalse(WGSettingsStore.isValidKey("GhostMode.x"))
        XCTAssertFalse(WGSettingsStore.isValidKey("ghost-mode.x"))
        XCTAssertFalse(WGSettingsStore.isValidKey("ghostMode..x"))
        XCTAssertFalse(WGSettingsStore.isValidKey("ghostMode.x "))
    }

    func testReadIsCheap() {
        WGTestSettings.toggle.set(true)
        let iterations = 1_000_000
        var count = 0
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0 ..< iterations {
            if WGTestSettings.toggle.value {
                count += 1
            }
        }
        let perRead = (CFAbsoluteTimeGetCurrent() - start) / Double(iterations)
        XCTAssertEqual(count, iterations)
        // Generous bound for unoptimized test builds; the target in release is tens of nanoseconds.
        XCTAssertLessThan(perRead, 2.0e-6)
    }
}
