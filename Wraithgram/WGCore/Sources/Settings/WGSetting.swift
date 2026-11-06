import Foundation
import SwiftSignalKit

/// Where a non-account setting is stored.
/// - `global`: `<appGroup>/wraithgram/settings/global.json`, read by the app only.
/// - `appGroup`: `<appGroup>/wraithgram/settings/shared.json`, small, read by the app and the
///   extensions (declare such settings in WGFeaturesShared with `.extensions`).
/// Account-scoped settings are `WGAccountSetting`.
public enum WGSettingScope: Equatable {
    case global
    case appGroup
}

public struct WGSettingFlags: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Secrets, hashes, tokens and internal state: never exported, imported or reset by
    /// "Reset all". The owning feature manages them.
    public static let noExport = WGSettingFlags(rawValue: 1 << 0)
    /// Read by the notification service / share extensions. Requires `.appGroup` scope or an
    /// account setting, and a declaration in WGFeaturesShared (linked into the extensions).
    public static let extensions = WGSettingFlags(rawValue: 1 << 1)
    /// The menu shows the localized "Restart required" footer after a change.
    public static let requiresRestart = WGSettingFlags(rawValue: 1 << 2)
}

/// What the store needs from any setting, without knowing its value type.
protocol WGAnySettingDescriptor: AnyObject {
    var key: String { get }
    var storageKind: WGSettingStorageKind { get }
    var flags: WGSettingFlags { get }

    /// Applies a stored JSON fragment (`nil`: absent, read the default). True when the value changed.
    func applyStored(_ fragment: Data?, account: WGAccountID?) -> Bool
    /// The value to write, or nil when it equals the default (the key is then dropped from the file).
    func storageFragment(account: WGAccountID?) -> Data?
    /// The current value, always encoded (export, diff display).
    func currentFragment(account: WGAccountID?) -> Data?
    /// Decodes an imported fragment; nil when it does not fit the type.
    func importCandidate(_ fragment: Data, account: WGAccountID?) -> WGSettingImportCandidate?
    /// Writes through the normal path (signals, persistence).
    func applyImported(_ fragment: Data, account: WGAccountID?)
    func resetValue(account: WGAccountID?)
    func dropAccount(_ account: WGAccountID)
    #if DEBUG
    var debugWasRead: Bool { get }
    #endif
}

enum WGSettingStorageKind: Equatable {
    case global
    case appGroup
    case account
}

struct WGSettingImportCandidate {
    let isChange: Bool
    let oldText: String
    let newText: String
    let canonicalFragment: Data
}

/// A global or App Group setting.
///
/// Declare it once, as a `static let` in the feature's enum, and touch every declaration from the
/// module's `register()` so the registry knows it before export, search and migrations:
///
///     enum GhostModeSettings {
///         static let hideReadReceipts = WGSetting<Bool>("ghostMode.hideReadReceipts", default: false)
///     }
///
/// `value` is the hot path: an uncontended lock and a copy of the value.
public final class WGSetting<Value: WGSettingValue> {
    public let key: String
    public let defaultValue: Value
    public let scope: WGSettingScope
    public let flags: WGSettingFlags

    let cell: WGValueCell<Value>

    public init(_ key: String, default defaultValue: Value, scope: WGSettingScope = .global, flags: WGSettingFlags = []) {
        self.key = key
        self.defaultValue = defaultValue
        self.scope = scope
        self.flags = flags
        self.cell = WGValueCell(defaultValue)

        assert(WGSettingsStore.isValidKey(key), "Setting key must be <feature>.<key> in camelCase: \(key)")
        assert(!flags.contains(.extensions) || scope == .appGroup, "\(key): .extensions needs scope .appGroup")
        WGSettingsStore.shared.register(self)
    }

    /// Current value. Safe on any thread; the hot path.
    public var value: Value {
        #if DEBUG
        if WGSettingsStore.debugIsExtensionProcess && !self.flags.contains(.extensions) {
            WGSettingsStore.shared.debugNoteExtensionRead(key: self.key)
        }
        return self.cell.currentMarkingRead
        #else
        return self.cell.current
        #endif
    }

    public func set(_ value: Value) {
        guard WGSettingsStore.shared.canWrite(key: self.key) else {
            return
        }
        if self.cell.update(value) {
            WGSettingsStore.shared.didChange(self, account: nil)
        }
    }

    public func reset() {
        self.set(self.defaultValue)
    }

    public var isDefault: Bool {
        return self.cell.current == self.defaultValue
    }

    /// The current value first, then every distinct change. Delivered on the writer's thread.
    public var signal: Signal<Value, NoError> {
        return self.cell.signal()
    }
}

extension WGSetting: WGAnySettingDescriptor {
    var storageKind: WGSettingStorageKind {
        switch self.scope {
        case .global:
            return .global
        case .appGroup:
            return .appGroup
        }
    }

    func applyStored(_ fragment: Data?, account: WGAccountID?) -> Bool {
        return self.cell.update(WGSettingDecoding.value(fragment, default: self.defaultValue, key: self.key))
    }

    func storageFragment(account: WGAccountID?) -> Data? {
        let current = self.cell.current
        if current == self.defaultValue {
            return nil
        }
        return WGSettingCodec.encode(current)
    }

    func currentFragment(account: WGAccountID?) -> Data? {
        return WGSettingCodec.encode(self.cell.current)
    }

    func importCandidate(_ fragment: Data, account: WGAccountID?) -> WGSettingImportCandidate? {
        return WGSettingDecoding.importCandidate(fragment, current: self.cell.current)
    }

    func applyImported(_ fragment: Data, account: WGAccountID?) {
        guard let value = WGSettingCodec.decode(Value.self, from: fragment) else {
            return
        }
        self.set(value)
    }

    func resetValue(account: WGAccountID?) {
        self.reset()
    }

    func dropAccount(_ account: WGAccountID) {
    }

    #if DEBUG
    var debugWasRead: Bool {
        return self.cell.debugWasRead
    }
    #endif
}

/// A setting with one value per Telegram account, stored in the account's own directory
/// (`<account.basePath>/wraithgram/settings.json`), so it leaves together with the account.
/// Exceptions, archives, bookmarks and per-account substitutions belong here.
public final class WGAccountSetting<Value: WGSettingValue> {
    public let key: String
    public let defaultValue: Value
    public let flags: WGSettingFlags

    let cell: WGAccountValueCell<Value>

    public init(_ key: String, default defaultValue: Value, flags: WGSettingFlags = []) {
        self.key = key
        self.defaultValue = defaultValue
        self.flags = flags
        self.cell = WGAccountValueCell(defaultValue: defaultValue)

        assert(WGSettingsStore.isValidKey(key), "Setting key must be <feature>.<key> in camelCase: \(key)")
        WGSettingsStore.shared.register(self)
    }

    /// Value for an account; the default for accounts that are not registered. The hot path.
    public func value(for account: WGAccountID) -> Value {
        #if DEBUG
        if WGSettingsStore.debugIsExtensionProcess && !self.flags.contains(.extensions) {
            WGSettingsStore.shared.debugNoteExtensionRead(key: self.key)
        }
        return self.cell.currentMarkingRead(for: account)
        #else
        return self.cell.current(for: account)
        #endif
    }

    public func set(_ value: Value, for account: WGAccountID) {
        guard WGSettingsStore.shared.canWrite(key: self.key) else {
            return
        }
        guard WGSettingsStore.shared.isAccountRegistered(account) else {
            WGLog.warning("settings", "\(self.key): write for an account that is not registered")
            return
        }
        if self.cell.update(value, for: account) {
            WGSettingsStore.shared.didChange(self, account: account)
        }
    }

    public func reset(for account: WGAccountID) {
        self.set(self.defaultValue, for: account)
    }

    public func isDefault(for account: WGAccountID) -> Bool {
        return self.cell.current(for: account) == self.defaultValue
    }

    /// The account's current value first, then every distinct change.
    public func signal(for account: WGAccountID) -> Signal<Value, NoError> {
        return self.cell.signal(for: account)
    }
}

extension WGAccountSetting: WGAnySettingDescriptor {
    var storageKind: WGSettingStorageKind {
        return .account
    }

    func applyStored(_ fragment: Data?, account: WGAccountID?) -> Bool {
        guard let account = account else {
            return false
        }
        let value = WGSettingDecoding.value(fragment, default: self.defaultValue, key: self.key)
        return self.cell.update(value, for: account)
    }

    func storageFragment(account: WGAccountID?) -> Data? {
        guard let account = account else {
            return nil
        }
        let current = self.cell.current(for: account)
        if current == self.defaultValue {
            return nil
        }
        return WGSettingCodec.encode(current)
    }

    func currentFragment(account: WGAccountID?) -> Data? {
        guard let account = account else {
            return nil
        }
        return WGSettingCodec.encode(self.cell.current(for: account))
    }

    func importCandidate(_ fragment: Data, account: WGAccountID?) -> WGSettingImportCandidate? {
        guard let account = account else {
            return nil
        }
        return WGSettingDecoding.importCandidate(fragment, current: self.cell.current(for: account))
    }

    func applyImported(_ fragment: Data, account: WGAccountID?) {
        guard let account = account, let value = WGSettingCodec.decode(Value.self, from: fragment) else {
            return
        }
        self.set(value, for: account)
    }

    func resetValue(account: WGAccountID?) {
        guard let account = account else {
            return
        }
        self.reset(for: account)
    }

    func dropAccount(_ account: WGAccountID) {
        self.cell.update(nil, for: account)
    }

    #if DEBUG
    var debugWasRead: Bool {
        return self.cell.debugWasRead
    }
    #endif
}

enum WGSettingDecoding {
    static func value<Value: WGSettingValue>(_ fragment: Data?, default defaultValue: Value, key: String) -> Value {
        guard let fragment = fragment else {
            return defaultValue
        }
        if let value = WGSettingCodec.decode(Value.self, from: fragment) {
            return value
        }
        // A stored value of another type (the declaration changed): read the default. The stored
        // fragment stays in the file until the setting is written again.
        WGLog.warning("settings", "\(key): stored value does not match the declared type")
        return defaultValue
    }

    static func importCandidate<Value: WGSettingValue>(_ fragment: Data, current: Value) -> WGSettingImportCandidate? {
        guard let newValue = WGSettingCodec.decode(Value.self, from: fragment) else {
            return nil
        }
        guard let canonical = WGSettingCodec.encode(newValue) else {
            return nil
        }
        return WGSettingImportCandidate(
            isChange: newValue != current,
            oldText: WGSettingCodec.text(WGSettingCodec.encode(current)),
            newText: WGSettingCodec.text(canonical),
            canonicalFragment: canonical
        )
    }
}
