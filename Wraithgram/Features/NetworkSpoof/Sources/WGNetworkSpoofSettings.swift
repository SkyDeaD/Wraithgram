import Foundation
import WGCore

// Settings of «Приватность › Подмены»: the number and the profile substitutions, both per account
// and on this device only. Toggles default to off.

public enum WGNetworkSpoofSettings {
    // MARK: Phone number (this device only)
    public static let fakePhoneEnabled = WGAccountSetting<Bool>("networkSpoof.fakePhoneEnabled", default: false)
    /// Digits only, up to 15.
    public static let fakePhone = WGAccountSetting<String>("networkSpoof.fakePhone", default: "")

    // MARK: Profile substitution (this device only)
    public static let profileRedirectEnabled = WGAccountSetting<Bool>("networkSpoof.profileRedirectEnabled", default: false)
    /// Source peer (`WGPeerKey.stringValue`) → the peer whose profile opens instead.
    public static let profileRedirects = WGAccountSetting<[String: WGPeerKey]>("networkSpoof.profileRedirects", default: [:])

    static func declare() {
        let _ = WGNetworkSpoofSettings.fakePhoneEnabled
        let _ = WGNetworkSpoofSettings.fakePhone
        let _ = WGNetworkSpoofSettings.profileRedirectEnabled
        let _ = WGNetworkSpoofSettings.profileRedirects
    }
}
