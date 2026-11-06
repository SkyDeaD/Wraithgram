import Foundation
import WGCore

extension WGRegDateStoredEntry: WGSettingValue {}
extension WGRegDateRemoteEntry: WGSettingValue {}

/// Settings and caches of «Дата регистрации».
enum WGRegDateSettings {
    /// The row in profiles. On by default, like Swiftgram's `showRegDate` (owner's decision 2026-11-01).
    static let show = WGSetting<Bool>("regDate.show", default: true)

    /// What this account found on the device, by user (`WGPeerKey.stringValue`): Telegram's month and
    /// the earliest trace. Account scope: it was learned through this account's data and leaves with
    /// it. A cache — not exported; bounded by `WGRegDateStore.evidenceLimit`.
    static let evidence = WGAccountSetting<[String: WGRegDateStoredEntry]>("regDate.evidence", default: [:], flags: [.noExport])

    /// Answers of a remote service by user (`WGPeerKey.stringValue`), and the old client's
    /// `regDateCache`. Global: an answer depends on the ID only. Not exported; bounded by
    /// `WGRegDateStore.remoteLimit`.
    static let remote = WGSetting<[String: WGRegDateRemoteEntry]>("regDate.remote", default: [:], flags: [.noExport])

    static func declare() {
        let _ = WGRegDateSettings.show
        let _ = WGRegDateSettings.evidence
        let _ = WGRegDateSettings.remote
    }
}
