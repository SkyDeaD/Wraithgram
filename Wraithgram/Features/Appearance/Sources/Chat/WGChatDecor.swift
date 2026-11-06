import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import WGCore
import WGHooks
import WGAppearanceSettings

/// Decorations of the chat screen, as feature overlays (WGChatScreenHooks.overlays) instead of edits
/// in ChatControllerNode: the animated background and the snowfall above the wallpaper, the blur and
/// gradient bands at the screen edges above the messages. Each overlay follows its settings with one
/// signal, created once per chat screen; nothing here takes part in theme rebuilds.
enum WGChatDecor {
    static func register() {
        WGChatScreenHooks.overlays.register({ screen in
            if screen.isPreview {
                return []
            }
            return [WGChatBackgroundOverlay(), WGChatEdgesOverlay(context: screen.context)]
        }, order: 100)

        WGLifecycleHooks.applicationDidBecomeActive.register({
            WGLoopingVideoView.resumeAll()
        }, order: 100)
    }
}

// MARK: - Settings as values

struct WGBackgroundDecorSettings: Equatable {
    var background: Bool
    var backgroundOpacity: Double
    var backgroundVersion: Int
    var snow: Bool
    var snowInChats: Bool
    var snowStyle: WGSnowStyle
    var snowIntensity: Double

    /// `double` reads the sliders (the stored value, or the menu preview's draft).
    static func current(double: (WGSetting<Double>) -> Double = { $0.value }) -> WGBackgroundDecorSettings {
        return WGBackgroundDecorSettings(
            background: WGAppearanceSettings.chatBackground.value,
            backgroundOpacity: wgClampPercent(double(WGAppearanceSettings.chatBackgroundOpacity)),
            backgroundVersion: WGAppearanceSettings.chatBackgroundVersion.value,
            snow: WGAppearanceSettings.snow.value,
            snowInChats: !WGAppearanceSettings.snowHideInChats.value,
            snowStyle: WGSnowStyle(rawValue: WGAppearanceSettings.snowStyle.value) ?? .snow,
            snowIntensity: wgClampPercent(double(WGAppearanceSettings.snowIntensity))
        )
    }

    /// Distinct values only, re-read on every settings revision (a struct compare, no disk).
    static var signal: Signal<WGBackgroundDecorSettings, NoError> {
        return WGSettingsStore.shared.revision
        |> map { _ -> WGBackgroundDecorSettings in
            return WGBackgroundDecorSettings.current()
        }
        |> distinctUntilChanged
    }
}

/// «Затемнение краёв»: one kind of band (blur or gradient) with one color, height and strength.
struct WGEdgeDecorSettings: Equatable {
    var style: WGEdgeStyle
    var rgb: UInt32?
    var size: Double
    var intensity: Double
    var hideInChatList: Bool

    var isEmpty: Bool {
        return self.style == .off
    }

    /// The chat list shows the gradient only (the blur is drawn in chats).
    var showsInChatList: Bool {
        return self.style == .gradient && !self.hideInChatList
    }

    /// `double` reads the sliders (the stored value, or the menu preview's draft).
    static func current(double: (WGSetting<Double>) -> Double = { $0.value }) -> WGEdgeDecorSettings {
        return WGEdgeDecorSettings(
            style: WGEdgeStyle(rawValue: WGAppearanceSettings.edgeStyle.value) ?? .off,
            rgb: wgAppearanceParseColor(WGAppearanceSettings.edgeColor.value),
            size: min(WGEdgeStyle.sizeRange.upperBound, max(WGEdgeStyle.sizeRange.lowerBound, double(WGAppearanceSettings.edgeSize))),
            intensity: wgClampPercent(double(WGAppearanceSettings.edgeIntensity)),
            hideInChatList: WGAppearanceSettings.edgeHideInChatList.value
        )
    }

    static var signal: Signal<WGEdgeDecorSettings, NoError> {
        return WGSettingsStore.shared.revision
        |> map { _ -> WGEdgeDecorSettings in
            return WGEdgeDecorSettings.current()
        }
        |> distinctUntilChanged
    }

    /// The band for one edge, with the theme's color where the user chose «automatic»: in the
    /// `blur` or the `gradient` slot, by the style.
    func bands(autoColor: UIColor) -> (blur: WGEdgeBandView.Band?, gradient: WGEdgeBandView.Band?) {
        let band = WGEdgeBandView.Band(color: self.rgb.flatMap { UIColor(rgb: $0) } ?? autoColor, size: CGFloat(self.size), intensity: CGFloat(self.intensity))
        switch self.style {
        case .off:
            return (nil, nil)
        case .blur:
            return (band, nil)
        case .gradient:
            return (nil, band)
        }
    }
}

/// 0…100 % → 0…1.
func wgClampPercent(_ value: Double) -> Double {
    return min(1.0, max(0.0, value / 100.0))
}

// MARK: - Above the wallpaper: animated background and snow

final class WGChatBackgroundOverlay: WGChatOverlay {
    let node: ASDisplayNode
    let placement: WGChatOverlayPlacement = .aboveWallpaper

    private var videoView: WGLoopingVideoView?
    private var snowView: WGSnowView?
    private var settings: WGBackgroundDecorSettings?
    private var reducesMotion = false
    private var bounds = CGRect()
    private var disposable: Disposable?

    init() {
        self.node = ASDisplayNode()
        self.node.isUserInteractionEnabled = false

        self.disposable = (combineLatest(WGBackgroundDecorSettings.signal, WGSystemState.reducesMotion)
        |> deliverOnMainQueue).start(next: { [weak self] settings, reducesMotion in
            guard let self else {
                return
            }
            self.settings = settings
            self.reducesMotion = reducesMotion
            self.apply()
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    func updateLayout(bounds: CGRect, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        self.bounds = bounds
        self.videoView?.frame = bounds
        self.snowView?.frame = bounds
    }

    private func apply() {
        guard let settings = self.settings else {
            return
        }
        if settings.background, let url = WGAnimatedBackgrounds.fileURL(.chat) {
            let videoView: WGLoopingVideoView
            if let current = self.videoView {
                videoView = current
            } else {
                videoView = WGLoopingVideoView(frame: self.bounds)
                self.node.view.insertSubview(videoView, at: 0)
                self.videoView = videoView
            }
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
                snowView = WGSnowView(frame: self.bounds, kind: .background)
                self.node.view.addSubview(snowView)
                self.snowView = snowView
            }
            snowView.update(style: settings.snowStyle, intensity: settings.snowIntensity, isPaused: self.reducesMotion)
        } else if let snowView = self.snowView {
            self.snowView = nil
            snowView.removeFromSuperview()
        }
    }
}

// MARK: - Above the messages: blur and gradient at the edges

final class WGChatEdgesOverlay: WGChatOverlay {
    let node: ASDisplayNode
    let placement: WGChatOverlayPlacement = .aboveHistory

    private let topView = WGEdgeBandView(edge: .top)
    private let bottomView = WGEdgeBandView(edge: .bottom)
    private var settings: WGEdgeDecorSettings?
    private var theme: PresentationTheme?
    private var layout: (bounds: CGRect, insets: UIEdgeInsets)?
    private var disposable: Disposable?

    init(context: AccountContext) {
        self.node = ASDisplayNode()
        self.node.isUserInteractionEnabled = false
        self.node.view.addSubview(self.topView)
        self.node.view.addSubview(self.bottomView)

        self.disposable = (combineLatest(WGEdgeDecorSettings.signal, context.sharedContext.presentationData)
        |> deliverOnMainQueue).start(next: { [weak self] settings, presentationData in
            guard let self else {
                return
            }
            self.settings = settings
            self.theme = presentationData.theme
            self.apply()
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    func updateLayout(bounds: CGRect, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        self.layout = (bounds, insets)
        self.apply()
    }

    private func apply() {
        guard let settings = self.settings, let theme = self.theme, let layout = self.layout else {
            return
        }
        self.node.isHidden = settings.isEmpty
        if settings.isEmpty {
            return
        }
        let width = layout.bounds.width
        let topBands = settings.bands(autoColor: theme.rootController.navigationBar.opaqueBackgroundColor)
        self.topView.update(width: width, inset: layout.insets.top, blur: topBands.blur, gradient: topBands.gradient)
        self.topView.frame = CGRect(x: 0.0, y: 0.0, width: width, height: self.topView.bandHeight(inset: layout.insets.top, blur: topBands.blur, gradient: topBands.gradient))

        // The overlay's bottom inset includes the input panels (WGChatScreenHooks.overlays).
        let bottomInset = layout.insets.bottom
        let bottomBands = settings.bands(autoColor: theme.chat.inputPanel.panelBackgroundColor.withAlphaComponent(1.0))
        self.bottomView.update(width: width, inset: bottomInset, blur: bottomBands.blur, gradient: bottomBands.gradient)
        let bottomHeight = self.bottomView.bandHeight(inset: bottomInset, blur: bottomBands.blur, gradient: bottomBands.gradient)
        self.bottomView.frame = CGRect(x: 0.0, y: layout.bounds.height - bottomHeight, width: width, height: bottomHeight)
    }
}

extension WGEdgeBandView {
    func bandHeight(inset: CGFloat, blur: Band?, gradient: Band?) -> CGFloat {
        return max(1.0, inset + max(blur?.size ?? 0.0, gradient?.size ?? 0.0))
    }
}
