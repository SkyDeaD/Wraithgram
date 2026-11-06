import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import WGCore
import WGFeaturesShared

/// What the camera features of calls need to know about the calls in progress, without a call
/// screen: the account of the call (its anonymous mode decides the mask, also for a call answered
/// from the lock screen) and whether a call is sending its own video (the virtual camera stops
/// decoding once the user turned the camera off). Watches the calls only while masks in calls, the
/// virtual camera or an anonymous mode is on. Main thread.
final class WGCameraCallsMonitor {
    static let shared = WGCameraCallsMonitor()

    private var isStarted = false
    private let callsDisposable = MetaDisposable()
    private var neededDisposable: Disposable?

    private init() {
    }

    /// Idempotent; from `WGLifecycleHooks.rootControllersDidLoad`.
    func start(sharedContext: SharedAccountContext) {
        assert(Thread.isMainThread)
        if self.isStarted {
            return
        }
        guard let callManager = sharedContext.callManager else {
            return
        }
        self.isStarted = true
        let needed: Signal<Bool, NoError> = WGSettingsStore.shared.revision
        |> map { _ -> Bool in
            return WGCameraCallsMonitor.isNeeded
        }
        |> distinctUntilChanged
        self.neededDisposable = (needed |> deliverOnMainQueue).start(next: { [weak self] isNeeded in
            guard let self else {
                return
            }
            if isNeeded {
                self.watch(callManager: callManager)
            } else {
                self.callsDisposable.set(nil)
                // No call is watched: unknown, so nothing idles by mistake.
                WGVirtualCameraFeeder.setLocalVideoSending(nil)
            }
        })
    }

    private static var isNeeded: Bool {
        if WGVirtualCameraSettings.enabled.value || WGMaskSettings.inCalls.value {
            return true
        }
        return WGSettingsStore.shared.registeredAccounts.contains(where: { WGAnonymousMode.isActive.value(for: $0) })
    }

    private func watch(callManager: PresentationCallManager) {
        let oneToOne: Signal<(WGAccountID?, Bool), NoError> = callManager.currentCallSignal
        |> mapToSignal { call -> Signal<(WGAccountID?, Bool), NoError> in
            guard let call else {
                return .single((nil, false))
            }
            let account = call.context.account.id.wg
            return call.state
            |> map { state -> (WGAccountID?, Bool) in
                return (account, WGCameraCallsMonitor.isSendingVideo(state))
            }
        }
        let group: Signal<(WGAccountID?, Bool), NoError> = callManager.currentGroupCallSignal
        |> mapToSignal { call -> Signal<(WGAccountID?, Bool), NoError> in
            guard let call else {
                return .single((nil, false))
            }
            switch call {
            case let .group(groupCall):
                let account = groupCall.accountContext.account.id.wg
                return groupCall.state
                |> map { state -> (WGAccountID?, Bool) in
                    return (account, state.isMyVideoActive)
                }
            case let .conferenceSource(source):
                let account = source.context.account.id.wg
                return source.state
                |> map { state -> (WGAccountID?, Bool) in
                    return (account, WGCameraCallsMonitor.isSendingVideo(state))
                }
            }
        }
        self.callsDisposable.set((combineLatest(oneToOne, group)
        |> deliverOnMainQueue).start(next: { oneToOne, group in
            if let account = group.0 ?? oneToOne.0 {
                WGCallMasks.shared.currentAccount = account
            }
            WGVirtualCameraFeeder.setLocalVideoSending(oneToOne.1 || group.1)
        }))
    }

    private static func isSendingVideo(_ state: PresentationCallState) -> Bool {
        switch state.state {
        case .terminating, .terminated:
            return false
        default:
            break
        }
        switch state.videoState {
        case .active, .paused:
            return true
        case .inactive, .notAvailable:
            return false
        }
    }
}
