import Foundation
import UIKit
import CoreMedia
import CoreVideo
import ImageIO
import WGCore

public enum WGCameraFacing: Equatable {
    case front
    case back
}

/// What a processor knows about a captured frame.
public struct WGCameraFrameInfo {
    public let facing: WGCameraFacing
    public let timestamp: CMTime
    /// Turns the buffer upright the way the user sees it (front camera: mirrored, like a selfie).
    public let orientation: CGImagePropertyOrientation

    public init(facing: WGCameraFacing, timestamp: CMTime, orientation: CGImagePropertyOrientation) {
        self.facing = facing
        self.timestamp = timestamp
        self.orientation = orientation
    }

    /// `quarterTurns` clockwise turns that make the buffer upright, then an optional horizontal flip.
    public static func orientation(quarterTurns: Int, mirrored: Bool) -> CGImagePropertyOrientation {
        switch ((quarterTurns % 4) + 4) % 4 {
        case 1:
            return mirrored ? .leftMirrored : .right
        case 2:
            return mirrored ? .downMirrored : .down
        case 3:
            return mirrored ? .rightMirrored : .left
        default:
            return mirrored ? .upMirrored : .up
        }
    }
}

/// One frame processor for every camera pipeline (CameraNeo, the legacy camera, calls): a frame in,
/// a frame of the same size and pixel format out. It runs once per frame, before the frame reaches
/// both the recorder and the live preview, so a mask is never rendered twice.
public protocol WGCameraFrameProcessor: AnyObject {
    /// Capture queue, every frame of the camera the user sees. Returns a new buffer of the same
    /// width, height and pixel format, or nil to keep the frame untouched (no mask selected, an
    /// unsupported format, a mask that is still being prepared).
    func process(_ pixelBuffer: CVPixelBuffer, info: WGCameraFrameInfo) -> CVPixelBuffer?
}

/// What the round-video camera screen tells a feature that extends it.
public struct WGRoundVideoCameraContext {
    public let accountId: WGAccountID
    /// Presents a UIKit controller (menus) over the camera screen.
    public let present: (UIViewController) -> Void

    public init(accountId: WGAccountID, present: @escaping (UIViewController) -> Void) {
        self.accountId = accountId
        self.present = present
    }
}

public struct WGRoundVideoCameraLayout: Equatable {
    public let containerSize: CGSize
    /// The preview circle in the container's coordinates.
    public let previewFrame: CGRect
    /// A recorded clip is shown instead of the camera: controls are hidden.
    public let isShowingResult: Bool
    public let isRecording: Bool
    public let isFrontCamera: Bool
    public let safeInsets: UIEdgeInsets

    public init(containerSize: CGSize, previewFrame: CGRect, isShowingResult: Bool, isRecording: Bool, isFrontCamera: Bool, safeInsets: UIEdgeInsets) {
        self.containerSize = containerSize
        self.previewFrame = previewFrame
        self.isShowingResult = isShowingResult
        self.isRecording = isRecording
        self.isFrontCamera = isFrontCamera
        self.safeInsets = safeInsets
    }
}

/// A feature's part of the round-video camera screen (masks). Created once per screen, only when
/// the feature is on; everything heavy inside is created lazily.
public protocol WGRoundVideoCameraExtension: AnyObject {
    /// Passed to the camera through `Camera.Configuration.frameProcessor`.
    var frameProcessor: WGCameraFrameProcessor? { get }
    /// Lives inside the preview circle above the camera preview and shows the processed frames
    /// while they differ from the raw camera. The screen sizes it to the circle.
    var previewOverlayView: UIView? { get }
    /// Lives above the screen's content and lays itself out in `update(layout:animated:)`.
    var controlsView: UIView? { get }
    /// Vertical band the controls occupy (container coordinates), for the zoom slider to avoid.
    var occupiedFrame: CGRect? { get }
    func update(layout: WGRoundVideoCameraLayout, animated: Bool)
    /// The screen is going away: stop everything, drop caches.
    func invalidate()
}

/// Format of the PCM a round-video audio stage receives.
public struct WGRoundVideoAudioFormat {
    public let sampleRate: Double
    public let channelCount: Int
    public let accountId: WGAccountID?

    public init(sampleRate: Double, channelCount: Int, accountId: WGAccountID?) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.accountId = accountId
    }
}

/// A PCM effect applied to the audio track of a recorded round video (the voice changer, W3-1).
/// Created for one pass over one clip; `process` is called with consecutive chunks.
public protocol WGRoundVideoAudioStage: AnyObject {
    /// Interleaved Float32 samples in −1…1, processed in place. The frame count never changes:
    /// a round video keeps the length of its picture (pitch and timbre only, no tempo).
    func process(_ samples: UnsafeMutablePointer<Float>, frameCount: Int)
    /// The stage could not do its work (it silenced the samples instead): the clip must not be sent.
    var hasFailed: Bool { get }
}

public extension WGRoundVideoAudioStage {
    var hasFailed: Bool {
        return false
    }
}

public enum WGCameraHooks {
    /// Asked once per round-video camera screen, on the main thread. The first non-nil answer wins.
    public static let roundVideoCamera = WGHookPoint<(WGRoundVideoCameraContext) -> WGRoundVideoCameraExtension?>("camera.roundVideoCamera")

    /// Asked for every pass over a recorded clip's audio (background queue). Return nil when the
    /// effect is off or would not change the sound; every non-nil stage is applied in `order`.
    public static let roundVideoAudioStage = WGHookPoint<(WGRoundVideoAudioFormat) -> WGRoundVideoAudioStage?>("camera.roundVideoAudioStage")

    public static func makeRoundVideoCameraExtension(context: WGRoundVideoCameraContext) -> WGRoundVideoCameraExtension? {
        if WGCameraHooks.roundVideoCamera.isEmpty {
            return nil
        }
        for handler in WGCameraHooks.roundVideoCamera.handlers {
            if let result = handler(context) {
                return result
            }
        }
        return nil
    }

    static func makeAudioStages(format: WGRoundVideoAudioFormat) -> [WGRoundVideoAudioStage] {
        if WGCameraHooks.roundVideoAudioStage.isEmpty {
            return []
        }
        var result: [WGRoundVideoAudioStage] = []
        for handler in WGCameraHooks.roundVideoAudioStage.handlers {
            if let stage = handler(format) {
                result.append(stage)
            }
        }
        return result
    }

    /// True when some stage would currently process a clip (cheap: asks with a nominal format).
    static func hasActiveAudioStage(accountId: WGAccountID?) -> Bool {
        return !WGCameraHooks.makeAudioStages(format: WGRoundVideoAudioFormat(sampleRate: 48000.0, channelCount: 1, accountId: accountId)).isEmpty
    }
}
