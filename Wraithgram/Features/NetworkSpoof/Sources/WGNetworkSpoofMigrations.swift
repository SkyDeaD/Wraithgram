import Foundation
import WGCore

// The old client's keys (same bundle id): the fake number (`MiscSettings.fakePhone*`) and the profile
// substitution (`WG.profileRedirect.*`), both per account through the old account profiles.

enum WGNetworkSpoofMigrations {
    static func register() {
        WGMigrations.registerAccount(id: "networkSpoof.account.v1", { legacy, account in
            // With the old per-account profiles on, the shared keys are the active account's live
            // values: another account takes its own profile only (never someone else's fake number).
            func value(_ key: String) -> Any? {
                return legacy.legacyAccountValue(key, for: account)
            }
            if let number = value("MiscSettings.fakePhoneNumber") as? String {
                let digits = String(number.filter { $0.isASCII && $0.isNumber }.prefix(15))
                if !digits.isEmpty {
                    WGNetworkSpoofSettings.fakePhone.set(digits, for: account)
                    if let enabled = value("MiscSettings.fakePhoneNumberEnabled") as? Bool {
                        WGNetworkSpoofSettings.fakePhoneEnabled.set(enabled, for: account)
                    }
                }
            }
            // The old pair stored bare ids; both are users there (the old code took the target's
            // namespace from the source, which only ever worked for users).
            if let source = (value("GG.profileRedirect.sourceId") as? String).flatMap({ Int64($0.trimmingCharacters(in: .whitespaces)) }),
               let target = (value("GG.profileRedirect.targetId") as? String).flatMap({ Int64($0.trimmingCharacters(in: .whitespaces)) }),
               let sourceKey = WGLegacyKeys.peerKey(fromRawId: source, namespace: 0),
               let targetKey = WGLegacyKeys.peerKey(fromRawId: target, namespace: 0),
               sourceKey != targetKey {
                WGNetworkSpoofSettings.profileRedirects.set([sourceKey.stringValue: targetKey], for: account)
                if let enabled = value("GG.profileRedirect.enabled") as? Bool {
                    WGNetworkSpoofSettings.profileRedirectEnabled.set(enabled, for: account)
                }
            }
        })
    }
}
