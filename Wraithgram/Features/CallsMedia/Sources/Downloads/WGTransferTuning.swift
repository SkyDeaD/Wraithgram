import Foundation
import UIKit
import TelegramCore
import ImageCompression
import WGCore
import WGFeaturesShared

/// Upload / download boost (SG-F6 / SG-F7) and outgoing photo quality and size (SG-F1 / SG-F2).
/// All of it goes through the network and image points; nothing here touches the network itself.
enum WGTransferTuning {
    /// Files up to this size keep upstream's parts: boosting tiny files (avatars, thumbnails) gains
    /// nothing and only multiplies requests.
    static let minimumBoostedFileSize: Int64 = 1024 * 1024

    static func register() {
        WGNetworkHooks.uploadParameters.register({ parameters in
            guard WGCallsMediaSettings.uploadBoost.value else {
                return
            }
            // Larger parts and more of them in parallel — what the server grants Premium. A burst of
            // FLOOD_PREMIUM_WAIT is handled by upstream's upload loop (it waits and retries).
            parameters.useLargerParts = true
            parameters.increaseParallelParts = true
        })

        WGNetworkHooks.downloadParameters.register({ parameters in
            guard let mode = WGDownloadBoostMode(rawValue: WGCallsMediaSettings.downloadBoost.value), mode != .off else {
                return
            }
            guard let fileSize = parameters.fileSize, fileSize > WGTransferTuning.minimumBoostedFileSize else {
                return
            }
            // The point asks for one value at a time; the other one is 0.
            if parameters.partSize != 0 {
                // Part sizes must be divisible by 4 KB and divide 1 MB.
                let boosted: Int64 = mode == .maximum ? 1024 * 1024 : 512 * 1024
                parameters.partSize = max(parameters.partSize, boosted)
            }
            if parameters.pendingParts != 0 {
                let boosted = mode == .maximum ? 12 : 8
                parameters.pendingParts = max(parameters.pendingParts, boosted)
            }
        })

        // The share extension registers the same handler (`wgShareExtensionDidStart`).
        WGOutgoingImageHooks.parameters.register({ parameters in
            WGOutgoingPhotoSettings.apply(maxSide: &parameters.maxSide, jpegQuality: &parameters.jpegQuality, isHd: parameters.isHd)
        })
    }
}
