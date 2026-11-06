import Foundation
import TelegramCore
import WGCore

/// The old client's keys (SGSimpleSettings, `UserDefaults.standard`):
/// - `showRegDate` (Bool, default true) → `regDate.show`;
/// - `regDateCache` (user id text → JSON of Swiftgram's `RegDate {from, to, validUntil}`): real
///   answers of Swiftgram's server, moved to `regDate.remote` as remote answers (expired ones too —
///   their bounds stay evidence, see `WGRegDate.resolve`).
enum WGRegDateMigration {
    static func register() {
        WGMigrations.registerGlobal(id: "regDate.v1") { legacy in
            if let value = legacy.bool("showRegDate") {
                WGRegDateSettings.show.set(value)
                legacy.removeLegacyKey("showRegDate")
            }
            let answers = WGRegDateStore.legacyRemoteAnswers(legacy.object("regDateCache"))
            if !answers.isEmpty {
                let userNamespace = Namespaces.Peer.CloudUser._internalGetInt32Value()
                var remote = WGRegDateSettings.remote.value
                for (userId, entry) in answers {
                    guard let key = WGPeerKey(namespace: userNamespace, id: userId)?.stringValue else {
                        continue
                    }
                    // An answer this build already has is newer than the old client's.
                    if remote[key] == nil {
                        remote[key] = entry
                    }
                }
                WGRegDateSettings.remote.set(WGRegDateStore.trimmedRemote(remote, now: Int32(clamping: Int(Date().timeIntervalSince1970))))
            }
            if legacy.object("regDateCache") != nil {
                legacy.removeLegacyKey("regDateCache")
            }
        }
    }
}
