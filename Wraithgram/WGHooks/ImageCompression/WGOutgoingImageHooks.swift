// Compiled into ImageCompression (filegroup //Wraithgram/WGHooks:ImageCompressionHookSources).
// Outgoing photos: size and JPEG quality (photo quality / "large photos") and a pixel
// transform (watermark). Lives in ImageCompression because both sending paths — the legacy
// picker (LegacyMediaPickerUI) and photo-library resources (LocalMediaResources) — import it,
// and both sit below the UI library WGHooks.

import Foundation
import UIKit
import WGCore

public struct WGOutgoingPhotoParameters: Equatable {
    /// Longest side in pixels (upstream: 1280, 2560 for "HD").
    public var maxSide: CGFloat
    /// JPEG quality 0…1 (upstream: 0.6).
    public var jpegQuality: Float
    public let isHd: Bool

    public init(maxSide: CGFloat, jpegQuality: Float, isHd: Bool) {
        self.maxSide = maxSide
        self.jpegQuality = jpegQuality
        self.isHd = isHd
    }
}

public enum WGOutgoingImageHooks {
    /// Transformer of size / quality of an outgoing photo.
    public static let parameters = WGHookPoint<(inout WGOutgoingPhotoParameters) -> Void>("media.outgoingPhotoParameters")

    /// Transformer of the scaled pixels before compression (watermark). Called off the main
    /// thread; `Bool` = HD photo.
    public static let image = WGHookPoint<(UIImage, Bool) -> UIImage>("media.outgoingPhotoImage")

    public static func maxSide(_ side: CGFloat, hd: Bool) -> CGFloat {
        if WGOutgoingImageHooks.parameters.isEmpty {
            return side
        }
        return WGOutgoingImageHooks.resolve(WGOutgoingPhotoParameters(maxSide: side, jpegQuality: 0.6, isHd: hd)).maxSide
    }

    public static func jpegQuality(_ quality: Float, hd: Bool) -> Float {
        if WGOutgoingImageHooks.parameters.isEmpty {
            return quality
        }
        return WGOutgoingImageHooks.resolve(WGOutgoingPhotoParameters(maxSide: hd ? 2560.0 : 1280.0, jpegQuality: quality, isHd: hd)).jpegQuality
    }

    public static func transform(_ image: UIImage, hd: Bool) -> UIImage {
        if WGOutgoingImageHooks.image.isEmpty {
            return image
        }
        var result = image
        for handler in WGOutgoingImageHooks.image.handlers {
            result = handler(result, hd)
        }
        return result
    }

    private static func resolve(_ value: WGOutgoingPhotoParameters) -> WGOutgoingPhotoParameters {
        var result = value
        for handler in WGOutgoingImageHooks.parameters.handlers {
            handler(&result)
        }
        return result
    }
}
