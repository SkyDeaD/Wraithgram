// Call camera points, used by TelegramCallsUI (owner of the call files: W3-3, requests/W3-2.md):
//   - every `OngoingCallVideoCapturer()` made for the device camera in PresentationCall,
//     PresentationGroupCall and VideoChatScreen (camera preview) asks `makeCameraCapturer()` first;
//   - `switchVideoCamera()` asks `switchCamera(capturer:isFront:)` first.
// The masks / virtual camera buttons of the call screens go through W3-3's
// `WGCallsMediaHooks.overlayItems`. Without handlers every helper returns nil / false: upstream.

import Foundation
import TelegramVoip
import WGCore

public enum WGCallCameraHooks {
    /// Asked whenever a call needs a camera capturer. Non-nil: a capturer Wraithgram feeds itself
    /// (the virtual camera); the device camera is never started for it. Main thread.
    public static let cameraCapturer = WGHookPoint<() -> OngoingCallVideoCapturer?>("calls.cameraCapturer")

    /// Asked before switching cameras: `true` = the feature handled it (its capturer has no device).
    public static let cameraSwitch = WGHookPoint<(OngoingCallVideoCapturer, Bool) -> Bool>("calls.cameraSwitch")

    public static func makeCameraCapturer() -> OngoingCallVideoCapturer? {
        if WGCallCameraHooks.cameraCapturer.isEmpty {
            return nil
        }
        for handler in WGCallCameraHooks.cameraCapturer.handlers {
            if let capturer = handler() {
                return capturer
            }
        }
        return nil
    }

    public static func switchCamera(capturer: OngoingCallVideoCapturer, isFront: Bool) -> Bool {
        if WGCallCameraHooks.cameraSwitch.isEmpty {
            return false
        }
        for handler in WGCallCameraHooks.cameraSwitch.handlers {
            if handler(capturer, isFront) {
                return true
            }
        }
        return false
    }
}
