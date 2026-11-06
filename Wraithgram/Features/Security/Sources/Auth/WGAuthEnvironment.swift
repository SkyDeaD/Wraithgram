import Foundation
import LocalAuthentication
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramUIPreferences
import WGCore
import WGFeaturesShared

/// What the device and Telegram offer for a check, kept in memory: whether a Telegram passcode is set,
/// whether Telegram unlocks with biometrics (and the enrollment it last saw), which biometry the
/// device has. Filled from account-manager signals and from one `LAContext` probe on a background
/// queue — nothing here talks to LocalAuthentication on the main thread, so menu rebuilds only read.
final class WGAuthEnvironment {
    static let shared = WGAuthEnvironment()

    struct State: Equatable {
        var hasTelegramPasscode: Bool = false
        var telegramBiometrics: Bool = false
        var telegramDomainState: Data?
        var biometryType: LABiometryType = .none
        var hasDevicePasscode: Bool = false
    }

    /// Main thread.
    private(set) var state = State()

    private var started = false
    private var disposable: Disposable?
    private var languageDisposable: Disposable?

    /// Once, from the first account's root controllers (main thread).
    func start(sharedContext: SharedAccountContext) {
        if self.started {
            return
        }
        self.started = true
        let accountManager = sharedContext.accountManager
        self.disposable = (combineLatest(
            accountManager.accessChallengeData(),
            accountManager.sharedData(keys: Set([ApplicationSpecificSharedDataKeys.presentationPasscodeSettings]))
        )
        |> deliverOnMainQueue).start(next: { [weak self] accessChallengeData, sharedData in
            guard let self else {
                return
            }
            let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.presentationPasscodeSettings]?.get(PresentationPasscodeSettings.self) ?? .defaultSettings
            self.state.hasTelegramPasscode = accessChallengeData.data.isLockable
            self.state.telegramBiometrics = settings.enableBiometrics
            self.state.telegramDomainState = settings.biometricsDomainState
            if WGSecuritySettings.passcodeIsSet.value != accessChallengeData.data.isLockable {
                WGSecuritySettings.passcodeIsSet.set(accessChallengeData.data.isLockable)
            }
        })
        // The notification service writes its own texts in the app's Wraithgram language.
        self.languageDisposable = (WGLocalization.shared.languageCodeSignal
        |> deliverOnMainQueue).start(next: { code in
            if WGSecuritySharedSettings.extensionLanguage.value != code {
                WGSecuritySharedSettings.extensionLanguage.set(code)
            }
        })
        self.refreshDevice()
    }

    /// Re-probes biometry and the device passcode off the main thread (on launch and on every return
    /// to the app — the user may have changed them in iOS Settings).
    func refreshDevice() {
        DispatchQueue.global(qos: .utility).async {
            let probe = WGAuthEnvironment.probeDevice()
            DispatchQueue.main.async {
                self.state.biometryType = probe.biometryType
                self.state.hasDevicePasscode = probe.hasDevicePasscode
            }
        }
    }

    struct DeviceProbe {
        let canUseBiometrics: Bool
        let biometryType: LABiometryType
        let domainState: Data?
        let hasDevicePasscode: Bool
    }

    /// Never on the main thread: `canEvaluatePolicy` is a synchronous XPC call.
    static func probeDevice() -> DeviceProbe {
        let biometricContext = LAContext()
        var error: NSError?
        let canUseBiometrics = biometricContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let biometryType = biometricContext.biometryType
        let domainState = biometricContext.evaluatedPolicyDomainState
        let hasDevicePasscode = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        return DeviceProbe(canUseBiometrics: canUseBiometrics, biometryType: biometryType, domainState: domainState, hasDevicePasscode: hasDevicePasscode)
    }
}
