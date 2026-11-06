import Foundation

/// Settings this build no longer declares: a removed feature, or rows merged into one setting.
///
/// The registry keeps keys it does not know when it rewrites a file (`WGSettingsStore`), so a
/// retired key stays in the user's files forever unless a migration drops it. A migration reads the
/// last stored value first when its meaning moves to a new setting:
///
///     WGMigrations.registerGlobal(id: "appearance.merge.v1") { _ in
///         let chats = WGRetiredSettings.value("appearance.messages.hideReactionsInChats", as: Bool.self)
///         …
///         WGRetiredSettings.remove(keys: ["appearance.messages.hideReactionsInChats"])
///     }
///
/// An absent value means the old default (defaults were never written). A declared key is never
/// read or removed here. App process only: extensions read nothing and drop nothing.
public enum WGRetiredSettings {
    /// The stored value of a retired global or App Group key; nil when absent or of another type.
    public static func value<Value: WGSettingValue>(_ key: String, as type: Value.Type) -> Value? {
        guard let fragment = WGSettingsStore.shared.retiredFragment(key, account: nil) else {
            return nil
        }
        return WGSettingCodec.decode(Value.self, from: fragment)
    }

    /// The stored value of a retired account key; nil when absent or of another type.
    public static func value<Value: WGSettingValue>(_ key: String, as type: Value.Type, account: WGAccountID) -> Value? {
        guard let fragment = WGSettingsStore.shared.retiredFragment(key, account: account) else {
            return nil
        }
        return WGSettingCodec.decode(Value.self, from: fragment)
    }

    /// Drops retired keys from global.json and shared.json: `keys` exactly, `prefixes` as the start
    /// of a key ("feed." drops every key of a removed feature).
    public static func remove(keys: [String] = [], prefixes: [String] = []) {
        WGSettingsStore.shared.removeRetired(keys: keys, prefixes: prefixes, account: nil)
    }

    /// Drops retired keys from the account's settings file.
    public static func remove(keys: [String] = [], prefixes: [String] = [], account: WGAccountID) {
        WGSettingsStore.shared.removeRetired(keys: keys, prefixes: prefixes, account: account)
    }

    /// Deletes files a removed feature kept next to the account's settings
    /// (`<account.basePath>/wraithgram/<name>`), on a utility queue. Plain file names only.
    public static func removeAccountFiles(_ names: [String], account: WGAccountID) {
        if let process = WGSettingsStore.shared.processKind, !process.isApp {
            return
        }
        guard let directory = WGSettingsStore.shared.accountDirectory(account) else {
            return
        }
        let paths = names.filter { name in
            return !name.isEmpty && !name.contains("/") && name != "." && name != ".."
        }.map { name in
            return (directory as NSString).appendingPathComponent(name)
        }
        if paths.isEmpty {
            return
        }
        DispatchQueue.global(qos: .utility).async {
            for path in paths where FileManager.default.fileExists(atPath: path) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }
}
