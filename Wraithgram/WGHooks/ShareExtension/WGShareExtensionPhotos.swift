// Compiled into ShareExtensionContext (filegroup //Wraithgram/WGHooks:ShareExtensionHookSources):
// photos sent from other apps through the share extension get the same size, JPEG quality and
// watermark as photos sent from the app (MEDIA-12). The settings are App Group ones
// (`WGOutgoingPhotoSettings`, `WGPhotoWatermarkSettings`); the handlers are the app's own.

import Foundation
import UIKit
import ImageCompression
import WGCore
import WGFeaturesShared
import WGCameraPipeline

/// From `wgShareExtensionDidStart`, before `WGHookRegistry.freeze()`.
func wgShareExtensionRegisterPhotoHandlers() {
    WGPhotoWatermarkSettings.declare()
    WGOutgoingImageHooks.parameters.register({ parameters in
        WGOutgoingPhotoSettings.apply(maxSide: &parameters.maxSide, jpegQuality: &parameters.jpegQuality, isHd: parameters.isHd)
    })
    WGOutgoingImageHooks.image.register({ image, _ in
        return WGPhotoWatermarkConfig.applyCurrent(to: image)
    }, order: 500)
}

/// WRAITH hook target, before the shared items are read (`TGItemProviderSignals.setWGPhotoMaxPixelSize`):
/// the long side a shared photo is decoded to when Wraithgram changes something about it, 0 when
/// nothing changes (the item provider then compresses it itself, as upstream does).
func wgShareExtensionPhotoMaxPixelSize() -> CGFloat {
    let maxSide = WGOutgoingImageHooks.maxSide(1280.0, hd: false)
    let quality = WGOutgoingImageHooks.jpegQuality(0.52, hd: false)
    if maxSide == 1280.0 && quality == 0.52 && WGPhotoWatermarkConfig.current() == nil {
        return 0.0
    }
    return maxSide
}
