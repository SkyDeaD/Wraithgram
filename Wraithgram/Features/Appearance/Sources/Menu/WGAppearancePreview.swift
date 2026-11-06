import Foundation
import UIKit
import TelegramPresentationData
import WGCore
import WGSettingsUI
import WGAppearanceSettings

/// The live mini chats of «Сообщения» and «Тема и фон» (W2-4 U6, U7): while a slider is dragged the
/// bubbles follow it (radii, padding, width, outline, background, name saturation) and the chat
/// layers of the theme tab (animated background, snow, edge bands) follow theirs. Nothing is
/// written before the finger is lifted: the drafts of the screen become a snapshot that the theme
/// transformer and the layout hooks see on the main thread for the duration of the preview's layout
/// (`WGAppearanceSnapshot.withPreview`). The chat's top bar follows «Скрыть в шапке чата».
enum WGAppearancePreview {
    /// Every slider the snapshot is built from (its drafts change the bubbles).
    private static var snapshotSliders: [WGSetting<Double>] {
        return [
            WGAppearanceSettings.bubbleIncomingRadius,
            WGAppearanceSettings.bubbleOutgoingRadius,
            WGAppearanceSettings.bubblePadding,
            WGAppearanceSettings.bubbleWidth,
            WGAppearanceSettings.bubbleBackgroundOpacity,
            WGAppearanceSettings.bubbleOutlineOpacity,
            WGAppearanceSettings.stickerSize,
            WGAppearanceSettings.nameColorSaturation
        ]
    }

    /// The configuration of a mini chat that follows the drafts of its screen.
    static func configuration(scope: String, overlays: Bool, content: @escaping (WGMenuContext) -> WGMiniChatContent) -> WGMiniChatConfiguration {
        var makeOverlays: ((WGMenuContext) -> [WGMiniChatOverlay])?
        if overlays {
            makeOverlays = { _ in
                let layers: [WGMiniChatOverlay] = [WGPreviewBackgroundOverlay(), WGPreviewEdgesOverlay()]
                return layers
            }
        }
        return WGMiniChatConfiguration(scope: scope, height: 196.0, content: content, presentationData: { context in
            // No slider is dragged: the app's own theme (already through the transformer).
            if WGAppearancePreview.drafts(context).isEmpty {
                return context.presentationData
            }
            return WGAppearanceTheme.previewPresentationData(context.presentationData)
        }, draftScope: { context, body in
            let drafts = WGAppearancePreview.drafts(context)
            if drafts.isEmpty {
                body()
            } else {
                WGAppearanceSnapshot.withPreview(WGAppearanceSnapshot.make(overriding: drafts), body)
            }
        }, overlays: makeOverlays)
    }

    /// The values the screen's sliders are being dragged to, of the sliders the snapshot is made of.
    private static func drafts(_ context: WGMenuContext) -> [String: Double] {
        var drafts: [String: Double] = [:]
        for setting in WGAppearancePreview.snapshotSliders {
            if let value = context.draftValue(forKey: setting.key) {
                drafts[setting.key] = value
            }
        }
        return drafts
    }

    /// The sample conversation with the chat's top bar as «Скрыть в шапке чата» sets it.
    static func sampleContent() -> WGMiniChatContent {
        var header = WGMiniChatContent.sampleHeader()
        header.hidesAvatar = WGAppearanceSettings.hideAvatar.value
        header.hidesTitle = WGAppearanceSettings.hideTitlePanel.value
        return WGMiniChatContent.sample(header: header)
    }

    /// A slider's value as the preview shows it: the draft while dragged.
    fileprivate static func reader(_ context: WGMenuContext) -> (WGSetting<Double>) -> Double {
        return { setting in
            return context.draftValue(forKey: setting.key) ?? setting.value
        }
    }
}

/// The animated chat background and the snow, under the bubbles.
private final class WGPreviewBackgroundOverlay: WGMiniChatOverlay {
    let view = UIView()
    let placement: WGMiniChatOverlayPlacement = .belowMessages

    private var videoView: WGLoopingVideoView?
    private var snowView: WGSnowView?

    init() {
        self.view.isUserInteractionEnabled = false
        self.view.clipsToBounds = true
    }

    func update(context: WGMenuContext, size: CGSize, insets: UIEdgeInsets) {
        let settings = WGBackgroundDecorSettings.current(double: WGAppearancePreview.reader(context))
        let bounds = CGRect(origin: CGPoint(), size: size)

        if settings.background, let url = WGAnimatedBackgrounds.fileURL(.chat) {
            let videoView: WGLoopingVideoView
            if let current = self.videoView {
                videoView = current
            } else {
                videoView = WGLoopingVideoView(frame: bounds)
                self.view.insertSubview(videoView, at: 0)
                self.videoView = videoView
            }
            videoView.frame = bounds
            videoView.alpha = CGFloat(settings.backgroundOpacity)
            videoView.setVideo(url: url, version: settings.backgroundVersion)
        } else if let videoView = self.videoView {
            self.videoView = nil
            videoView.setVideo(url: nil, version: 0)
            videoView.removeFromSuperview()
        }

        if settings.snow && settings.snowInChats {
            let snowView: WGSnowView
            if let current = self.snowView {
                snowView = current
            } else {
                snowView = WGSnowView(frame: bounds, kind: .background)
                self.view.addSubview(snowView)
                self.snowView = snowView
            }
            snowView.frame = bounds
            snowView.update(style: settings.snowStyle, intensity: settings.snowIntensity, isPaused: WGSystemState.current)
        } else if let snowView = self.snowView {
            self.snowView = nil
            snowView.removeFromSuperview()
        }
    }
}

/// The blur and gradient bands of the screen edges, above the bubbles: the top one under the
/// preview's top bar, the bottom one at the block's lower edge (the preview has no input panel).
private final class WGPreviewEdgesOverlay: WGMiniChatOverlay {
    let view = UIView()
    let placement: WGMiniChatOverlayPlacement = .aboveMessages

    private let topView = WGEdgeBandView(edge: .top)
    private let bottomView = WGEdgeBandView(edge: .bottom)

    init() {
        self.view.isUserInteractionEnabled = false
        self.view.clipsToBounds = true
        self.view.addSubview(self.topView)
        self.view.addSubview(self.bottomView)
    }

    func update(context: WGMenuContext, size: CGSize, insets: UIEdgeInsets) {
        let settings = WGEdgeDecorSettings.current(double: WGAppearancePreview.reader(context))
        self.view.isHidden = settings.isEmpty
        if settings.isEmpty {
            return
        }
        let theme = context.presentationData.theme
        let width = size.width

        let topBands = settings.bands(autoColor: theme.rootController.navigationBar.opaqueBackgroundColor)
        self.topView.update(width: width, inset: insets.top, blur: topBands.blur, gradient: topBands.gradient)
        self.topView.frame = CGRect(x: 0.0, y: 0.0, width: width, height: self.topView.bandHeight(inset: insets.top, blur: topBands.blur, gradient: topBands.gradient))

        let bottomBands = settings.bands(autoColor: theme.chat.inputPanel.panelBackgroundColor.withAlphaComponent(1.0))
        self.bottomView.update(width: width, inset: 0.0, blur: bottomBands.blur, gradient: bottomBands.gradient)
        let bottomHeight = self.bottomView.bandHeight(inset: 0.0, blur: bottomBands.blur, gradient: bottomBands.gradient)
        self.bottomView.frame = CGRect(x: 0.0, y: size.height - bottomHeight, width: width, height: bottomHeight)
    }
}
