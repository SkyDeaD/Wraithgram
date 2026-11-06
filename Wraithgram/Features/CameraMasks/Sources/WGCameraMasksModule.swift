import Foundation
import TelegramCore
import AccountContext
import WGCore
import WGHooks
import WGCameraPipeline
import WGCallCameraHooks
import WGCallsMediaHooks
import WGFeaturesShared

/// Entry point of the WGCameraMasks feature module. Owner: W3-2.
public enum WGCameraMasksModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `WGFeatures.registerAll()`, before `WGHookRegistry.freeze()`.
    public static func register() {
        assert(Thread.isMainThread)
        WGCameraPipelineSettings.declare()
        WGMaskSettings.declare()
        WGVirtualCameraSettings.declare()
        WGCameraMasksMigrations.register()

        // Round videos: the masks button, panel and processor exist only while masks are on (or
        // the anonymous mode of this account is). Otherwise the camera screen is upstream's.
        WGCameraHooks.roundVideoCamera.register({ context in
            guard WGMaskEngine.isActive(for: context.accountId) else {
                return nil
            }
            return WGRoundVideoMasksExtension(accountId: context.accountId)
        }, order: 100)

        // Calls: one processor in the capturer's frame hook (returns at once while masks are off),
        // the virtual camera's capturer, and two buttons in the call screen's column.
        WGCallMasks.install()
        WGCallCameraHooks.cameraCapturer.register({
            return WGVirtualCameraFeeder.makeCapturer()
        }, order: 100)
        WGCallCameraHooks.cameraSwitch.register({ capturer, isFront in
            return WGVirtualCameraFeeder.switchCamera(capturer: capturer, isFront: isFront)
        }, order: 100)
        WGCallsMediaHooks.overlayItems.register({ screen in
            let accountId = screen.context.account.id.wg
            WGCallMasks.shared.currentAccount = accountId
            // Only the buttons of features that are on: with both off the call screen gets no overlay.
            var items: [WGCallOverlayItem] = []
            if WGMaskSettings.inCalls.value || WGAnonymousMode.isActive.value(for: accountId) {
                items.append(WGCallMasksOverlayItem(accountId: accountId))
            }
            if WGVirtualCameraSettings.enabled.value {
                items.append(WGVirtualCameraOverlayItem(call: screen.call, groupCall: screen.groupCall))
            }
            return items
        }, order: 200)

        // Outgoing media: the photo watermark and «video as a round video».
        WGPhotoWatermarkHandler.register()
        WGRoundVideoImportHandler.register()

        // Telegram's size limit of a round video, known before any round video is encoded (the
        // gallery ones too, which never open the round camera); the camera re-reads it.
        WGLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            WGRoundVideoServerLimits.update(encoding: context.getAppConfigValue("round_video_encoding") as? [String: Any])
            // The calls' account and own video for masks and the virtual camera, also without a call screen.
            WGCameraCallsMonitor.shared.start(sharedContext: context.sharedContext)
        }, order: 300)

        WGCameraMasksMenu.register()

        // Files of the old app (own masks, virtual camera media): moved once, off the launch
        // thread; each is a single existence check when there is nothing to move.
        WGMaskStore.migrateLegacyMasksIfNeeded()
        WGVirtualCameraLibrary.migrateLegacyFilesIfNeeded()
    }
}
