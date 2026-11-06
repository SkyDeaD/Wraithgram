import Foundation
import SwiftSignalKit

/// The settings registry and its files.
///
/// | scope    | file                                              | who reads                 |
/// |----------|---------------------------------------------------|---------------------------|
/// | global   | `<appGroup>/wraithgram/settings/global.json`        | the app                   |
/// | appGroup | `<appGroup>/wraithgram/settings/shared.json`        | the app and extensions    |
/// | account  | `<account.basePath>/wraithgram/settings.json`       | the app; NSE for its push |
///
/// Format: `{"version": 1, "values": {"<key>": <JSON>}}`. Keys this build does not know are kept
/// when the file is rewritten; values equal to the default are not written. Writes happen on the
/// store's own queue, coalesced (0.3 s) and atomic. Extensions never write.
public final class WGSettingsStore {
    public static let shared = WGSettingsStore()

    static let coalescingDelay: Double = 0.3

    private let lock = WGUnfairLock()
    private var environment: WGCoreEnvironment?
    private var globalFile: WGSettingsFileState?
    private var appGroupFile: WGSettingsFileState?
    private var accountFiles: [WGAccountID: WGSettingsFileState] = [:]
    private var descriptorsByKey: [String: WGAnySettingDescriptor] = [:]
    private var descriptors: [WGAnySettingDescriptor] = []
    private var isWriteScheduled = false
    /// Grows when the files are replaced (tests), so a write scheduled for old files does nothing.
    private var fileEpoch = 0
    private var batchDepth = 0
    private var batchChanged = false
    #if DEBUG
    private var reportedExtensionReads = Set<String>()
    #endif

    private let ioQueue = DispatchQueue(label: "org.wraithgram.settings", qos: .utility)
    private let revisionCell = WGValueCell<UInt64>(0)

    private init() {
    }

    // MARK: - Public API

    /// Grows on every change of any setting, account registration and import. For screens that
    /// depend on many settings: one subscription instead of one per setting.
    public var revision: Signal<UInt64, NoError> {
        return self.revisionCell.signal()
    }

    public var registeredAccounts: [WGAccountID] {
        return self.lock.withLock {
            return self.accountFiles.keys.sorted()
        }
    }

    /// Keys of every declared setting, in declaration order.
    public var registeredKeys: [String] {
        return self.lock.withLock {
            return self.descriptors.map { $0.key }
        }
    }

    /// Loads the account's file and runs the pending account migrations. Synchronous: call when
    /// the `Account` is created, before its network starts (TelegramCore bridge).
    public func registerAccount(_ id: WGAccountID, basePath: String) {
        let path = WGSettingsStore.accountFilePath(basePath: basePath)
        let (process, isAlreadyRegistered) = self.lock.withLock { () -> (WGProcessKind?, Bool) in
            return (self.environment?.process, self.accountFiles[id]?.path == path)
        }
        if isAlreadyRegistered && (process?.isApp ?? true) {
            // The same account object recreated (e.g. a reconnect): memory already holds its values
            // and possibly unwritten changes; reloading the file would drop them. An extension never
            // writes, and iOS keeps its process alive between pushes while the app changes the file:
            // there the file is read again.
            return
        }
        let isWritable = process?.isApp ?? true
        let file = WGSettingsFileState.load(path: path, account: id, isWritable: isWritable, createsIntermediateDirectories: false)

        let stored = self.lock.withLock { () -> [(WGAnySettingDescriptor, Data?)] in
            if let previous = self.accountFiles[id] {
                previous.isRemoved = true
            }
            self.accountFiles[id] = file
            var result: [(WGAnySettingDescriptor, Data?)] = []
            for descriptor in self.descriptors where descriptor.storageKind == .account {
                result.append((descriptor, file.values[descriptor.key]))
            }
            return result
        }
        for (descriptor, fragment) in stored {
            let _ = descriptor.applyStored(fragment, account: id)
        }
        if process == .app {
            WGMigrations.runPendingAccountMigrations(for: id)
        }
        self.bumpRevision()
    }

    /// Forgets the account (on logout). Pending changes are written once more only while the
    /// account directory still exists: account files never create it, so a late write can not
    /// resurrect a removed account.
    public func unregisterAccount(_ id: WGAccountID) {
        let removed = self.lock.withLock { () -> (WGSettingsFileState, Set<String>, [WGAnySettingDescriptor])? in
            guard let file = self.accountFiles.removeValue(forKey: id) else {
                return nil
            }
            let pendingKeys = file.dirtyKeys
            file.dirtyKeys.removeAll()
            file.isRemoved = true
            return (file, pendingKeys, self.descriptors.filter { $0.storageKind == .account })
        }
        guard let removedAccount = removed else {
            return
        }
        let (file, pendingKeys, accountDescriptors) = removedAccount
        if file.isWritable && !pendingKeys.isEmpty {
            var updates: [(String, Data?)] = []
            for descriptor in accountDescriptors where pendingKeys.contains(descriptor.key) {
                updates.append((descriptor.key, descriptor.storageFragment(account: id)))
            }
            let data = self.lock.withLock { () -> Data in
                for (key, fragment) in updates {
                    file.values[key] = fragment
                }
                return WGSettingsFileFormat.serialize(file.values)
            }
            let path = file.path
            self.ioQueue.async {
                WGSettingsStore.writeFile(path: path, data: data, createsIntermediateDirectories: false)
            }
        }
        for descriptor in accountDescriptors {
            descriptor.dropAccount(id)
        }
        self.bumpRevision()
    }

    /// Extensions only (the app's own memory is the truth there): reads shared.json and the files of
    /// the registered accounts again. iOS keeps an extension's process alive and reuses it for the
    /// next push, while the app goes on changing the files; call at the start of every request.
    /// Synchronous, small files; a value that did not change emits nothing.
    public func reloadFromDisk() {
        let (environment, accounts) = self.lock.withLock { () -> (WGCoreEnvironment?, [(WGAccountID, String)]) in
            return (self.environment, self.accountFiles.map { ($0.key, $0.value.path) })
        }
        guard let environment, !environment.process.isApp else {
            return
        }
        let shared = WGSettingsFileState.load(
            path: (environment.settingsDirectoryPath as NSString).appendingPathComponent("shared.json"),
            account: nil,
            isWritable: false,
            createsIntermediateDirectories: true
        )
        var accountFiles: [WGAccountID: WGSettingsFileState] = [:]
        for (account, path) in accounts {
            accountFiles[account] = WGSettingsFileState.load(path: path, account: account, isWritable: false, createsIntermediateDirectories: false)
        }
        let stored = self.lock.withLock { () -> [(WGAnySettingDescriptor, WGAccountID?, Data?)] in
            self.appGroupFile?.isRemoved = true
            self.appGroupFile = shared
            var result: [(WGAnySettingDescriptor, WGAccountID?, Data?)] = []
            for (account, file) in accountFiles {
                // Logged out meanwhile, or registered again under another path: keep what is there.
                guard let current = self.accountFiles[account], current.path == file.path else {
                    continue
                }
                current.isRemoved = true
                self.accountFiles[account] = file
            }
            for descriptor in self.descriptors {
                switch descriptor.storageKind {
                case .global:
                    break
                case .appGroup:
                    result.append((descriptor, nil, shared.values[descriptor.key]))
                case .account:
                    for (account, file) in accountFiles where self.accountFiles[account] === file {
                        result.append((descriptor, account, file.values[descriptor.key]))
                    }
                }
            }
            return result
        }
        var changed = false
        for (descriptor, account, fragment) in stored {
            if descriptor.applyStored(fragment, account: account) {
                changed = true
            }
        }
        if changed {
            self.bumpRevision()
        }
    }

    /// Writes pending changes now, on the store's queue. Never blocks the caller (the main thread
    /// must not wait for the disk). Call on resign active / background.
    public func flush() {
        self.ioQueue.async { [weak self] in
            self?.performWrite()
        }
    }

    // MARK: - Export / import / reset

    /// All registered settings without `.noExport`, plus the account settings of `accounts`.
    /// `{"format": "wraithgram.settings", "version": 1, "global": {...}, "appGroup": {...},
    ///   "accounts": {"<account id>": {...}}}`
    public func exportData(accounts: [WGAccountID]) -> Data {
        let (descriptors, registered) = self.lock.withLock { () -> ([WGAnySettingDescriptor], Set<WGAccountID>) in
            return (self.descriptors, Set(self.accountFiles.keys))
        }
        var global: [String: Data] = [:]
        var shared: [String: Data] = [:]
        for descriptor in descriptors where !descriptor.flags.contains(.noExport) {
            switch descriptor.storageKind {
            case .global:
                global[descriptor.key] = descriptor.currentFragment(account: nil)
            case .appGroup:
                shared[descriptor.key] = descriptor.currentFragment(account: nil)
            case .account:
                break
            }
        }
        var accountSections: [String: Data] = [:]
        for account in accounts where registered.contains(account) {
            var values: [String: Data] = [:]
            for descriptor in descriptors where descriptor.storageKind == .account && !descriptor.flags.contains(.noExport) {
                values[descriptor.key] = descriptor.currentFragment(account: account)
            }
            accountSections[account.stringValue] = WGSettingCodec.object(values)
        }
        let root: [String: Data] = [
            "format": Data("\"\(WGSettingsStore.exportFormat)\"".utf8),
            "version": Data("\(WGSettingsStore.exportVersion)".utf8),
            "global": WGSettingCodec.object(global),
            "appGroup": WGSettingCodec.object(shared),
            "accounts": WGSettingCodec.object(accountSections)
        ]
        return WGSettingCodec.object(root)
    }

    public func importPreview(_ data: Data) throws -> WGSettingsImportDiff {
        return try self.importPreview(data, accountMapping: [:])
    }

    /// `accountMapping` maps an account of the file to an account here. Without a mapping, a
    /// section goes to the account with the same id; a file with one account section goes to the
    /// only account registered here. Sections that match nothing are listed in `unmatchedAccounts`.
    public func importPreview(_ data: Data, accountMapping: [WGAccountID: WGAccountID]) throws -> WGSettingsImportDiff {
        guard let object = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
            throw WGSettingsImportError.invalidFormat
        }
        guard let format = object["format"] as? String, WGSettingsStore.importFormats.contains(format) else {
            throw WGSettingsImportError.invalidFormat
        }
        guard let version = object["version"] as? Int, version >= 1 else {
            throw WGSettingsImportError.invalidFormat
        }
        if version > WGSettingsStore.exportVersion {
            throw WGSettingsImportError.unsupportedVersion(version)
        }

        let (descriptorsByKey, registered) = self.lock.withLock { () -> ([String: WGAnySettingDescriptor], [WGAccountID]) in
            return (self.descriptorsByKey, self.accountFiles.keys.sorted())
        }

        var changes: [WGSettingsImportChange] = []
        var unknownKeys = Set<String>()
        var skippedKeys = Set<String>()
        var unmatchedAccounts: [WGAccountID] = []

        func consider(_ values: [String: Data], kind: WGSettingStorageKind, account: WGAccountID?) {
            for key in values.keys.sorted() {
                guard let fragment = values[key] else {
                    continue
                }
                guard let descriptor = descriptorsByKey[key] else {
                    unknownKeys.insert(key)
                    continue
                }
                if descriptor.flags.contains(.noExport) || descriptor.storageKind != kind {
                    skippedKeys.insert(key)
                    continue
                }
                guard let candidate = descriptor.importCandidate(fragment, account: account) else {
                    skippedKeys.insert(key)
                    continue
                }
                if candidate.isChange {
                    changes.append(WGSettingsImportChange(
                        key: key,
                        scope: WGSettingsImportScope(kind),
                        account: account,
                        oldValue: candidate.oldText,
                        newValue: candidate.newText,
                        fragment: candidate.canonicalFragment
                    ))
                }
            }
        }

        consider(WGSettingCodec.fragments(ofObject: object["global"]) ?? [:], kind: .global, account: nil)
        consider(WGSettingCodec.fragments(ofObject: object["appGroup"]) ?? [:], kind: .appGroup, account: nil)

        let accountsObject = object["accounts"] as? [String: Any] ?? [:]
        let fileAccounts = accountsObject.keys.compactMap { WGAccountID(string: $0) }.sorted()
        for fileAccount in fileAccounts {
            var target: WGAccountID?
            if let mapped = accountMapping[fileAccount] {
                target = mapped
            } else if registered.contains(fileAccount) {
                target = fileAccount
            } else if fileAccounts.count == 1 && registered.count == 1 {
                target = registered[0]
            }
            guard let account = target, registered.contains(account) else {
                unmatchedAccounts.append(fileAccount)
                continue
            }
            let values = WGSettingCodec.fragments(ofObject: accountsObject[fileAccount.stringValue]) ?? [:]
            consider(values, kind: .account, account: account)
        }

        return WGSettingsImportDiff(
            changes: changes,
            unknownKeys: unknownKeys.sorted(),
            skippedKeys: skippedKeys.sorted(),
            unmatchedAccounts: unmatchedAccounts
        )
    }

    /// Applies a preview made by `importPreview` (one revision bump, one flush). App only.
    public func applyImport(_ diff: WGSettingsImportDiff) {
        let descriptorsByKey = self.lock.withLock {
            return self.descriptorsByKey
        }
        self.performBatch {
            for change in diff.changes {
                guard let descriptor = descriptorsByKey[change.key], !descriptor.flags.contains(.noExport) else {
                    continue
                }
                descriptor.applyImported(change.fragment, account: change.account)
            }
        }
        self.flush()
    }

    /// Every registered setting without `.noExport` back to its default, for the global scopes and
    /// for the given accounts.
    public func resetAll(accounts: [WGAccountID]) {
        let descriptors = self.lock.withLock {
            return self.descriptors
        }
        self.performBatch {
            for descriptor in descriptors where !descriptor.flags.contains(.noExport) {
                switch descriptor.storageKind {
                case .global, .appGroup:
                    descriptor.resetValue(account: nil)
                case .account:
                    for account in accounts {
                        descriptor.resetValue(account: account)
                    }
                }
            }
        }
        self.flush()
    }

    // MARK: - Internal: registry

    static let exportFormat = "wraithgram.settings"
    /// Files exported before the rename to Wraithgram say "ghostgram.settings"; their contents are the same.
    static let importFormats: Set<String> = [exportFormat, "ghostgram.settings"]
    static let exportVersion = 1

    static func accountFilePath(basePath: String) -> String {
        let directory = (basePath as NSString).appendingPathComponent("wraithgram")
        return (directory as NSString).appendingPathComponent("settings.json")
    }

    static func isValidKey(_ key: String) -> Bool {
        let segments = key.split(separator: ".", omittingEmptySubsequences: false)
        if segments.count < 2 {
            return false
        }
        for segment in segments {
            if segment.isEmpty {
                return false
            }
            var isFirst = true
            for scalar in segment.unicodeScalars {
                let value = scalar.value
                let isLower = value >= 97 && value <= 122
                let isUpper = value >= 65 && value <= 90
                let isDigit = value >= 48 && value <= 57
                if isFirst {
                    if !isLower {
                        return false
                    }
                } else if !isLower && !isUpper && !isDigit {
                    return false
                }
                isFirst = false
            }
        }
        return true
    }

    func bootstrap(_ environment: WGCoreEnvironment) {
        let directory = environment.settingsDirectoryPath
        let isApp = environment.process.isApp
        #if DEBUG
        WGSettingsStore.debugIsExtensionProcess = !isApp
        #endif
        var global: WGSettingsFileState?
        if isApp {
            global = WGSettingsFileState.load(
                path: (directory as NSString).appendingPathComponent("global.json"),
                account: nil,
                isWritable: true,
                createsIntermediateDirectories: true
            )
        }
        let shared = WGSettingsFileState.load(
            path: (directory as NSString).appendingPathComponent("shared.json"),
            account: nil,
            isWritable: isApp,
            createsIntermediateDirectories: true
        )

        let stored = self.lock.withLock { () -> [(WGAnySettingDescriptor, Data?)] in
            self.environment = environment
            self.globalFile = global
            self.appGroupFile = shared
            var result: [(WGAnySettingDescriptor, Data?)] = []
            for descriptor in self.descriptors {
                switch descriptor.storageKind {
                case .global:
                    if let global = global {
                        result.append((descriptor, global.values[descriptor.key]))
                    }
                case .appGroup:
                    result.append((descriptor, shared.values[descriptor.key]))
                case .account:
                    break
                }
            }
            return result
        }
        var changed = false
        for (descriptor, fragment) in stored {
            if descriptor.applyStored(fragment, account: nil) {
                changed = true
            }
        }
        if changed {
            self.bumpRevision()
        }
    }

    var processKind: WGProcessKind? {
        return self.lock.withLock {
            return self.environment?.process
        }
    }

    func register(_ descriptor: WGAnySettingDescriptor) {
        var stored: [(WGAccountID?, Data?)] = []
        let isDuplicate = self.lock.withLock { () -> Bool in
            if self.descriptorsByKey[descriptor.key] != nil {
                return true
            }
            self.descriptorsByKey[descriptor.key] = descriptor
            self.descriptors.append(descriptor)
            switch descriptor.storageKind {
            case .global:
                if let file = self.globalFile {
                    stored.append((nil, file.values[descriptor.key]))
                }
            case .appGroup:
                if let file = self.appGroupFile {
                    stored.append((nil, file.values[descriptor.key]))
                }
            case .account:
                for (account, file) in self.accountFiles {
                    stored.append((account, file.values[descriptor.key]))
                }
            }
            return false
        }
        if isDuplicate {
            assertionFailure("Duplicate setting key \(descriptor.key)")
            WGLog.error("settings", "duplicate setting key \(descriptor.key); the second declaration is not persisted")
            return
        }
        var changed = false
        for (account, fragment) in stored where fragment != nil {
            if descriptor.applyStored(fragment, account: account) {
                changed = true
            }
        }
        if changed {
            self.bumpRevision()
        }
    }

    func canWrite(key: String) -> Bool {
        guard let process = self.processKind else {
            // Before bootstrap (tests, very early code): in memory only.
            return true
        }
        if !process.isApp {
            assertionFailure("\(key): extensions only read settings")
            WGLog.error("settings", "\(key): write from an extension ignored")
            return false
        }
        return true
    }

    func isAccountRegistered(_ account: WGAccountID) -> Bool {
        return self.lock.withLock {
            return self.accountFiles[account] != nil
        }
    }

    func didChange(_ descriptor: WGAnySettingDescriptor, account: WGAccountID?) {
        let shouldBump = self.lock.withLock { () -> Bool in
            if self.descriptorsByKey[descriptor.key] === descriptor, let file = self.fileLocked(kind: descriptor.storageKind, account: account) {
                if file.isWritable && !file.isRemoved {
                    file.dirtyKeys.insert(descriptor.key)
                    self.scheduleWriteLocked()
                }
            }
            if self.batchDepth > 0 {
                self.batchChanged = true
                return false
            }
            return true
        }
        if shouldBump {
            self.bumpRevision()
        }
    }

    func performBatch(_ body: () -> Void) {
        self.lock.withLock {
            self.batchDepth += 1
        }
        body()
        let shouldBump = self.lock.withLock { () -> Bool in
            self.batchDepth -= 1
            if self.batchDepth == 0 && self.batchChanged {
                self.batchChanged = false
                return true
            }
            return false
        }
        if shouldBump {
            self.bumpRevision()
        }
    }

    func bumpRevision() {
        self.revisionCell.modify { value in
            return value &+ 1
        }
    }

    // MARK: - Retired keys (WGRetiredSettings)

    /// The stored fragment of a key no setting declares: the account's file, or global.json and
    /// then shared.json. A declared key answers nil (its value lives in the setting).
    func retiredFragment(_ key: String, account: WGAccountID?) -> Data? {
        return self.lock.withLock { () -> Data? in
            if self.descriptorsByKey[key] != nil {
                return nil
            }
            if let account = account {
                return self.accountFiles[account]?.values[key]
            }
            if let fragment = self.globalFile?.values[key] {
                return fragment
            }
            return self.appGroupFile?.values[key]
        }
    }

    /// Drops undeclared keys (exact, or starting with one of `prefixes`) from the account's file or
    /// from global.json and shared.json. The file is rewritten by the usual coalesced write: only
    /// declared keys are re-encoded there, the dropped ones are simply no longer in `values`.
    /// App process only; true when something was dropped.
    @discardableResult
    func removeRetired(keys: [String], prefixes: [String], account: WGAccountID?) -> Bool {
        if keys.isEmpty && prefixes.isEmpty {
            return false
        }
        if let process = self.processKind, !process.isApp {
            return false
        }
        let exact = Set(keys)
        return self.lock.withLock { () -> Bool in
            var files: [WGSettingsFileState] = []
            if let account = account {
                if let file = self.accountFiles[account] {
                    files.append(file)
                }
            } else {
                if let file = self.globalFile {
                    files.append(file)
                }
                if let file = self.appGroupFile {
                    files.append(file)
                }
            }
            var changed = false
            for file in files where file.isWritable && !file.isRemoved {
                let dropped = file.values.keys.filter { key in
                    if self.descriptorsByKey[key] != nil {
                        return false
                    }
                    if exact.contains(key) {
                        return true
                    }
                    return prefixes.contains(where: { key.hasPrefix($0) })
                }
                for key in dropped {
                    file.values.removeValue(forKey: key)
                    file.dirtyKeys.insert(key)
                    changed = true
                }
            }
            if changed {
                self.scheduleWriteLocked()
            }
            return changed
        }
    }

    /// `<account.basePath>/wraithgram`, the directory of the account's settings file, while the
    /// account is registered.
    func accountDirectory(_ account: WGAccountID) -> String? {
        return self.lock.withLock { () -> String? in
            guard let file = self.accountFiles[account] else {
                return nil
            }
            return (file.path as NSString).deletingLastPathComponent
        }
    }

    #if DEBUG
    /// Set once in `bootstrap`, before any feature reads a setting; read without a lock.
    static var debugIsExtensionProcess = false

    func debugNoteExtensionRead(key: String) {
        let shouldReport = self.lock.withLock { () -> Bool in
            return self.reportedExtensionReads.insert(key).inserted
        }
        if shouldReport {
            WGLog.warning("settings", "\(key) is read in an extension but is not declared with .extensions; it reads the default there")
        }
    }

    /// DEBUG: declared settings that no feature code has read since launch — candidates for a dead
    /// toggle (a screen row without a consumer). For the W4-4 audit and the debug menu.
    public func debugUnreadKeys() -> [String] {
        let descriptors = self.lock.withLock {
            return self.descriptors
        }
        return descriptors.filter { !$0.debugWasRead }.map { $0.key }
    }
    #endif

    // MARK: - Internal: writing

    private func fileLocked(kind: WGSettingStorageKind, account: WGAccountID?) -> WGSettingsFileState? {
        switch kind {
        case .global:
            return self.globalFile
        case .appGroup:
            return self.appGroupFile
        case .account:
            guard let account = account else {
                return nil
            }
            return self.accountFiles[account]
        }
    }

    private func allFilesLocked() -> [WGSettingsFileState] {
        var result: [WGSettingsFileState] = []
        if let globalFile = self.globalFile {
            result.append(globalFile)
        }
        if let appGroupFile = self.appGroupFile {
            result.append(appGroupFile)
        }
        for account in self.accountFiles.keys.sorted() {
            if let file = self.accountFiles[account] {
                result.append(file)
            }
        }
        return result
    }

    private func scheduleWriteLocked() {
        if self.isWriteScheduled {
            return
        }
        self.isWriteScheduled = true
        let epoch = self.fileEpoch
        self.ioQueue.asyncAfter(deadline: .now() + WGSettingsStore.coalescingDelay) { [weak self] in
            self?.performWrite(epoch: epoch)
        }
    }

    private struct WriteJob {
        let file: WGSettingsFileState
        let items: [(String, WGAnySettingDescriptor)]
    }

    /// Runs on `ioQueue`. `epoch`: the files the write was scheduled for (nil: the current ones).
    private func performWrite(epoch: Int? = nil) {
        let jobs = self.lock.withLock { () -> [WriteJob] in
            if let epoch = epoch, epoch != self.fileEpoch {
                return []
            }
            self.isWriteScheduled = false
            var jobs: [WriteJob] = []
            for file in self.allFilesLocked() where !file.dirtyKeys.isEmpty {
                let keys = file.dirtyKeys.sorted()
                file.dirtyKeys.removeAll()
                if file.isRemoved || !file.isWritable {
                    continue
                }
                var items: [(String, WGAnySettingDescriptor)] = []
                for key in keys {
                    if let descriptor = self.descriptorsByKey[key] {
                        items.append((key, descriptor))
                    }
                }
                jobs.append(WriteJob(file: file, items: items))
            }
            return jobs
        }
        if jobs.isEmpty {
            return
        }

        // Encoding reads each cell under its own lock, outside the store lock.
        var encoded: [(WGSettingsFileState, [(String, Data?)])] = []
        for job in jobs {
            var items: [(String, Data?)] = []
            for (key, descriptor) in job.items {
                items.append((key, descriptor.storageFragment(account: job.file.account)))
            }
            encoded.append((job.file, items))
        }

        let writes = self.lock.withLock { () -> [(String, Data, Bool)] in
            var writes: [(String, Data, Bool)] = []
            for (file, items) in encoded {
                if file.isRemoved {
                    continue
                }
                for (key, fragment) in items {
                    file.values[key] = fragment
                }
                writes.append((file.path, WGSettingsFileFormat.serialize(file.values), file.createsIntermediateDirectories))
            }
            return writes
        }
        for (path, data, createsIntermediateDirectories) in writes {
            WGSettingsStore.writeFile(path: path, data: data, createsIntermediateDirectories: createsIntermediateDirectories)
        }
    }

    static func writeFile(path: String, data: Data, createsIntermediateDirectories: Bool) {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: createsIntermediateDirectories, attributes: nil)
            } catch {
                WGLog.warning("settings", "settings directory can not be created")
                return
            }
        }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            WGLog.error("settings", "settings file can not be written")
        }
    }

    // MARK: - Tests

    /// Waits for every queued write. Tests and process termination only: never from the main
    /// thread of the app.
    func flushSynchronously() {
        self.ioQueue.sync {
            self.performWrite()
        }
    }

    /// Forgets files and accounts, puts every declared setting back to its default and loads the
    /// files of `environment` (nil: stay unbootstrapped). Tests only.
    func resetForTesting(environment: WGCoreEnvironment?) {
        self.ioQueue.sync {
        }
        let (descriptors, accounts) = self.lock.withLock { () -> ([WGAnySettingDescriptor], [WGAccountID]) in
            let accounts = Array(self.accountFiles.keys)
            for file in self.accountFiles.values {
                file.isRemoved = true
            }
            self.globalFile?.isRemoved = true
            self.appGroupFile?.isRemoved = true
            self.accountFiles.removeAll()
            self.globalFile = nil
            self.appGroupFile = nil
            self.environment = nil
            self.isWriteScheduled = false
            self.fileEpoch += 1
            #if DEBUG
            WGSettingsStore.debugIsExtensionProcess = false
            #endif
            self.batchDepth = 0
            self.batchChanged = false
            return (self.descriptors, accounts)
        }
        for descriptor in descriptors {
            switch descriptor.storageKind {
            case .global, .appGroup:
                let _ = descriptor.applyStored(nil, account: nil)
            case .account:
                for account in accounts {
                    descriptor.dropAccount(account)
                }
            }
        }
        if let environment = environment {
            self.bootstrap(environment)
        }
    }
}

/// A settings file in memory: every stored fragment, including keys this build does not know.
final class WGSettingsFileState {
    let path: String
    let account: WGAccountID?
    let isWritable: Bool
    let createsIntermediateDirectories: Bool
    var values: [String: Data]
    var dirtyKeys = Set<String>()
    var isRemoved = false

    init(path: String, account: WGAccountID?, isWritable: Bool, createsIntermediateDirectories: Bool, values: [String: Data]) {
        self.path = path
        self.account = account
        self.isWritable = isWritable
        self.createsIntermediateDirectories = createsIntermediateDirectories
        self.values = values
    }

    /// Reads the file synchronously. A damaged file is moved aside to `<file>.damaged` (app only)
    /// and the settings start from defaults; a file of a newer format is read but never rewritten.
    static func load(path: String, account: WGAccountID?, isWritable: Bool, createsIntermediateDirectories: Bool) -> WGSettingsFileState {
        var values: [String: Data] = [:]
        var writable = isWritable
        if let data = FileManager.default.contents(atPath: path) {
            switch WGSettingsFileFormat.parse(data) {
            case let .parsed(parsedValues, version):
                values = parsedValues
                if version > WGSettingsFileFormat.version {
                    WGLog.warning("settings", "settings file of a newer format: read only for this launch")
                    writable = false
                }
            case .damaged:
                WGLog.error("settings", "damaged settings file: starting from defaults")
                if isWritable {
                    let damagedPath = path + ".damaged"
                    let _ = try? FileManager.default.removeItem(atPath: damagedPath)
                    let _ = try? FileManager.default.moveItem(atPath: path, toPath: damagedPath)
                }
            }
        }
        return WGSettingsFileState(
            path: path,
            account: account,
            isWritable: writable,
            createsIntermediateDirectories: createsIntermediateDirectories,
            values: values
        )
    }
}

enum WGSettingsFileFormat {
    static let version = 1

    enum ParseResult {
        case parsed(values: [String: Data], version: Int)
        case damaged
    }

    static func parse(_ data: Data) -> ParseResult {
        guard let object = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
            return .damaged
        }
        guard let version = object["version"] as? Int else {
            return .damaged
        }
        guard let values = WGSettingCodec.fragments(ofObject: object["values"]) else {
            return .damaged
        }
        return .parsed(values: values, version: version)
    }

    static func serialize(_ values: [String: Data]) -> Data {
        var result = Data("{\"version\":\(WGSettingsFileFormat.version),\"values\":".utf8)
        result.append(WGSettingCodec.object(values))
        result.append(contentsOf: Array("}\n".utf8))
        return result
    }
}

// MARK: - Import types

public enum WGSettingsImportError: Error, Equatable {
    case invalidFormat
    case unsupportedVersion(Int)

    /// Text for the alert, in the current Wraithgram language.
    public var localizedText: String {
        switch self {
        case .invalidFormat:
            return WGStrings.Core.Import.invalidFormat
        case let .unsupportedVersion(version):
            return WGStrings.Core.Import.unsupportedVersion(version: String(version))
        }
    }
}

public enum WGSettingsImportScope: Equatable {
    case global
    case appGroup
    case account

    init(_ kind: WGSettingStorageKind) {
        switch kind {
        case .global:
            self = .global
        case .appGroup:
            self = .appGroup
        case .account:
            self = .account
        }
    }
}

/// One setting the import would change: key, old → new (compact JSON), scope and account.
public struct WGSettingsImportChange {
    public let key: String
    public let scope: WGSettingsImportScope
    public let account: WGAccountID?
    public let oldValue: String
    public let newValue: String
    let fragment: Data
}

public struct WGSettingsImportDiff {
    public let changes: [WGSettingsImportChange]
    /// Keys of the file no setting here declares (a newer version, a removed feature).
    public let unknownKeys: [String]
    /// Keys that exist here but are not taken: secrets (`.noExport`), a wrong type or scope.
    public let skippedKeys: [String]
    /// Account sections of the file that match no account on this device.
    public let unmatchedAccounts: [WGAccountID]

    public var isEmpty: Bool {
        return self.changes.isEmpty
    }
}
