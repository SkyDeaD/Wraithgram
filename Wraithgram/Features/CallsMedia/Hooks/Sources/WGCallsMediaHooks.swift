import Foundation
import UIKit
import Display
import TelegramCore
import TelegramVoip
import AccountContext
import WGCallAudio
import WGCore

// Points of the «Calls» zone, called from TelegramCallsUI (PresentationCall, CallController,
// CallControllerNodeV2, PresentationCallManager, VideoChatScreen). Handlers: WGCallsMedia (silent
// mute, rating, Force TCP, the overlay host and its soundboard button), W3-2 (masks / virtual camera
// buttons in the overlay column). Empty points = upstream behaviour, byte for byte.

/// One call screen as features see it: the 1:1 call screen or the group call (video chat) screen.
public final class WGCallScreen {
    public let context: AccountContext
    /// The 1:1 call; nil on the group call screen.
    public let call: PresentationCall?
    /// The group call; nil on the 1:1 call screen.
    public let groupCall: PresentationGroupCall?
    /// The call's audio device (silent mute, soundboard, recording tap). nil when the call runs without
    /// the shared device (server killswitch `ios_killswitch_disable_call_device`).
    public let audioDevice: OngoingCallContext.AudioDevice?
    /// Presents a controller over the call screen (pickers, alerts).
    public let present: (ViewController) -> Void

    public init(context: AccountContext, call: PresentationCall?, groupCall: PresentationGroupCall?, audioDevice: OngoingCallContext.AudioDevice?, present: @escaping (ViewController) -> Void) {
        self.context = context
        self.call = call
        self.groupCall = groupCall
        self.audioDevice = audioDevice
        self.present = present
    }
}

/// What the overlay needs from the screen on every layout.
public struct WGCallScreenState: Equatable {
    /// The own camera (or a replacement) is being sent.
    public var hasLocalVideo: Bool
    /// 1:1 signal quality 0…4, smoothed by the screen; nil = unknown or a group call.
    public var signalQuality: Int?
    /// When the call became active (`CFAbsoluteTimeGetCurrent` time base); nil before that.
    public var activeSince: Double?
    /// The call is over (the screen stays for the «call ended» state).
    public var isTerminated: Bool

    public init(hasLocalVideo: Bool, signalQuality: Int?, activeSince: Double?, isTerminated: Bool) {
        self.hasLocalVideo = hasLocalVideo
        self.signalQuality = signalQuality
        self.activeSince = activeSince
        self.isTerminated = isTerminated
    }
}

/// Feature-owned layer above a call screen, created once per screen.
public protocol WGCallScreenOverlay: AnyObject {
    /// Added above the call screen's content. Touches outside the overlay's controls fall through.
    var view: UIView { get }
    /// `size` = the screen, `insets` = safe area (status bar, home indicator).
    func update(size: CGSize, insets: UIEdgeInsets, state: WGCallScreenState, transition: ContainedViewLayoutTransition)
    /// The screen is going away for good (dismissed, call ended).
    func screenWillClose()
}

/// A button in the overlay's right-hand column (soundboard, masks, virtual camera…).
public protocol WGCallOverlayItem: AnyObject {
    /// Stable id, also the order tiebreaker.
    var id: String { get }
    /// Sparse, step 100: soundboard 300; masks / virtual camera (W3-2) 100–200.
    var order: Int { get }
    /// Template glyph, drawn white in a 40 pt dark circle.
    var icon: UIImage? { get }
    func isVisible(state: WGCallScreenState) -> Bool
    /// Strip shown under the column while the button is selected (choices). nil = `buttonTapped()`.
    func makePanel() -> UIView?
    func buttonTapped()
    func screenWillClose()
}

public enum WGCallsMediaHooks {
    /// Policy (first non-nil wins): mute a 1:1 call silently — silence the captured audio and keep the
    /// call unmuted, so the other side sees no «microphone off». Never asked for conference calls.
    public static let silentMute = WGHookPoint<(PresentationCall) -> Bool?>("calls.silentMute")

    /// Policy (any `true`): do not offer the rating sheet after a call.
    public static let suppressRating = WGHookPoint<() -> Bool>("calls.suppressRating")

    /// Policy (any `true`): force TCP for calls (the upstream debug switch `enableVoipTcp` keeps working).
    public static let forceTcp = WGHookPoint<() -> Bool>("calls.forceTcp")

    /// Provider of the overlay host of a call screen (first non-nil wins). WGCallsMedia.
    public static let screenOverlay = WGHookPoint<(WGCallScreen) -> WGCallScreenOverlay?>("calls.screenOverlay")

    /// Providers of the overlay column's buttons, asked once per screen by the overlay host.
    public static let overlayItems = WGHookPoint<(WGCallScreen) -> [WGCallOverlayItem]>("calls.overlayItems")

    // MARK: - Call-site helpers

    /// `PresentationCallImpl.setIsMuted` and the call context's creation. `upstream` is the original
    /// `ongoingContext.setIsMuted`. Without handlers this is exactly `upstream(muted)`.
    public static func applyMute(_ muted: Bool, call: PresentationCall, audioDevice: OngoingCallContext.AudioDevice?, upstream: (Bool) -> Void) {
        if WGCallsMediaHooks.silentMute.isEmpty {
            upstream(muted)
            return
        }
        var silent = false
        for handler in WGCallsMediaHooks.silentMute.handlers {
            if let value = handler(call) {
                silent = value
                break
            }
        }
        if let audioDevice = audioDevice, silent {
            audioDevice.wgAudioEffects.captureSilenced = muted
            upstream(false)
        } else {
            // The feature may have been switched off mid-call while silenced: hand the mute back.
            if let audioDevice = audioDevice, audioDevice.wgAudioEffects.captureSilenced {
                audioDevice.wgAudioEffects.captureSilenced = false
            }
            upstream(muted)
        }
    }

    public static func shouldSuppressRating() -> Bool {
        for handler in WGCallsMediaHooks.suppressRating.handlers {
            if handler() {
                return true
            }
        }
        return false
    }

    public static func shouldForceTcp() -> Bool {
        for handler in WGCallsMediaHooks.forceTcp.handlers {
            if handler() {
                return true
            }
        }
        return false
    }

    public static func makeScreenOverlay(_ screen: WGCallScreen) -> WGCallScreenOverlay? {
        for handler in WGCallsMediaHooks.screenOverlay.handlers {
            if let overlay = handler(screen) {
                return overlay
            }
        }
        return nil
    }

    public static func makeOverlayItems(_ screen: WGCallScreen) -> [WGCallOverlayItem] {
        var result: [WGCallOverlayItem] = []
        for handler in WGCallsMediaHooks.overlayItems.handlers {
            result.append(contentsOf: handler(screen))
        }
        return result.sorted(by: { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id < rhs.id
        })
    }
}
