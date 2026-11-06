import Foundation

/// The process WGCore runs in. Extensions only read settings and never run migrations.
public enum WGProcessKind: String {
    case app
    case notificationService
    case notificationContent
    case share
    case widget
    case intents
    case broadcastUpload
    case other

    public var isApp: Bool {
        return self == .app
    }
}

public struct WGCoreEnvironment {
    /// Path of the App Group container (`group.<base bundle id>`).
    public let appGroupPath: String
    public let process: WGProcessKind
    /// App Group of the previous Wraithgram installation, read by migrations. `nil` means
    /// `group.<main bundle id>`: the old app had the same bundle id.
    public let legacyAppGroupIdentifier: String?

    public init(appGroupPath: String, process: WGProcessKind, legacyAppGroupIdentifier: String? = nil) {
        self.appGroupPath = appGroupPath
        self.process = process
        self.legacyAppGroupIdentifier = legacyAppGroupIdentifier
    }

    var wraithgramPath: String {
        return (self.appGroupPath as NSString).appendingPathComponent("wraithgram")
    }

    var settingsDirectoryPath: String {
        return (self.wraithgramPath as NSString).appendingPathComponent("settings")
    }

    var inboxDirectoryPath: String {
        return (self.wraithgramPath as NSString).appendingPathComponent("inbox")
    }
}

/// Entry points called once per process from the launch path (see FOUNDATION_SPEC §2).
public enum WGCore {
    private static let lock = WGUnfairLock()
    private static var currentEnvironment: WGCoreEnvironment?

    /// The environment passed to `bootstrap`, or nil before it.
    public static var environment: WGCoreEnvironment? {
        return WGCore.lock.withLock {
            return WGCore.currentEnvironment
        }
    }

    /// Loads the settings files of this process. Call first, before any feature registers.
    public static func bootstrap(_ environment: WGCoreEnvironment) {
        let isFirst = WGCore.lock.withLock { () -> Bool in
            if WGCore.currentEnvironment != nil {
                return false
            }
            WGCore.currentEnvironment = environment
            return true
        }
        if !isFirst {
            assertionFailure("WGCore.bootstrap must be called once")
            return
        }
        WGLog.bootstrap(process: environment.process)
        WGSettingsStore.shared.bootstrap(environment)
        // Registers core.language and resolves the language before the first string is read.
        let _ = WGLocalization.shared
    }

    /// Extensions: reads the settings files again (iOS reuses an extension's process for the next
    /// request while the app goes on changing them). Call at the start of every request after the
    /// first; does nothing in the app.
    public static func reloadSettings() {
        WGSettingsStore.shared.reloadFromDisk()
    }

    /// Runs the registered one-time migrations from the old Wraithgram. App process only, after
    /// all modules have registered (`WGFeatures.registerAll()`).
    public static func runGlobalMigrations() {
        WGMigrations.runPending()
    }
}
