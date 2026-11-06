import Foundation
import Darwin
import os
import SwiftSignalKit
import WGCore

/// Bubble geometry and paint of the bubble editor (nil in the snapshot while the editor is off).
public struct WGBubbleAppearance: Equatable {
    public var incomingRadius: Double
    public var outgoingRadius: Double
    public var padding: Double
    /// 0.4…1, share of the upstream maximum width.
    public var widthFraction: Double
    /// 0…1.
    public var backgroundAlpha: Double
    /// 0…1.
    public var outlineAlpha: Double
}

/// Everything about Wraithgram's appearance that changes the theme or the layout of messages and
/// chrome, as one immutable value. Built once per settings change; the hot paths (cells, layout) read
/// `WGAppearanceSnapshot.current` — one lock-protected load, no disk, no JSON.
///
/// Decorations that do not need a relayout (animated backgrounds, snow, screen-edge blur) are not
/// part of it: they follow their own settings' signals, so they never rebuild the theme.
public struct WGAppearanceSnapshot: Equatable {
    // Theme
    public var amoled = false
    public var amoledKeyboard = false
    public var hideSeparators = false
    /// 0…1; 1 = the server's colors.
    public var nameColorSaturation: Double = 1.0
    public var readCheckRGB: UInt32?
    public var unreadCheckRGB: UInt32?
    public var checkColorsInChatList = false
    public var bubbles: WGBubbleAppearance?
    public var hideTails = false

    // Messages
    public var wideChannelPosts = false
    public var secondsInTime = false
    public var hideReactionsInChats = false
    public var hideReactionsInChannels = false
    public var hideEdited = false
    public var hideTime = false
    public var hideIncomingFormatting = false
    public var hideOutgoingFormatting = false
    public var hideChannelComments = false
    public var hideViewCounts = false
    public var colorSwatches = false
    public var authorOnlineIndicator = false
    public var exactLastSeen = false
    public var tripleTapDelete: WGTripleTapDelete = .off
    public var noSelectionBlur = false
    /// 0.5…2.
    public var stickerScale: Double = 1.0
    public var stickerHideTime = false

    // Chat top bar
    public var hideBackButton = false
    public var hideTitlePanel = false
    public var hideAvatar = false
    public var hidePinnedMessages = false

    public init() {
    }

    /// All upstream: the theme transformer returns the PresentationData untouched.
    public var isDefault: Bool {
        return self == WGAppearanceSnapshot()
    }

    /// The parts that change the theme's colors or images (the rest only needs a relayout).
    public var changesThemeColors: Bool {
        if self.amoled || self.amoledKeyboard || self.hideSeparators {
            return true
        }
        if self.readCheckRGB != nil || self.unreadCheckRGB != nil {
            return true
        }
        if self.bubbles != nil {
            return true
        }
        return false
    }

    /// The current snapshot. Any thread; the hot path. Inside `withPreview` on the main thread —
    /// the preview's snapshot.
    public static var current: WGAppearanceSnapshot {
        if pthread_main_np() != 0, let preview = WGAppearanceSnapshotStore.mainThreadPreview {
            return preview
        }
        return WGAppearanceSnapshotStore.shared.current()
    }

    /// Runs `body` with `current` answering `snapshot` on the main thread only (other threads keep
    /// the real one): the menu's live preview lays its bubbles out with the values a slider is
    /// being dragged to, while the settings are written only on release. Main thread, synchronous.
    public static func withPreview(_ snapshot: WGAppearanceSnapshot, _ body: () -> Void) {
        assert(pthread_main_np() != 0)
        let previous = WGAppearanceSnapshotStore.mainThreadPreview
        WGAppearanceSnapshotStore.mainThreadPreview = snapshot
        body()
        WGAppearanceSnapshotStore.mainThreadPreview = previous
    }

    /// The snapshot as the settings would make it with these slider values (setting key → value):
    /// what a live preview shows while a slider is dragged.
    public static func make(overriding values: [String: Double]) -> WGAppearanceSnapshot {
        if values.isEmpty {
            return WGAppearanceSnapshot.current
        }
        return WGAppearanceSnapshot.make(double: { setting in
            return values[setting.key] ?? setting.value
        })
    }

    /// The current snapshot first, then every distinct one. Delivered on the writer's thread.
    public static var signal: Signal<WGAppearanceSnapshot, NoError> {
        return WGAppearanceSnapshotStore.shared.signal()
    }

    /// `double` reads the sliders (the stored value, or a preview's draft).
    static func make(double: (WGSetting<Double>) -> Double = { $0.value }) -> WGAppearanceSnapshot {
        var result = WGAppearanceSnapshot()

        result.amoled = WGAppearanceSettings.amoled.value
        result.amoledKeyboard = WGAppearanceSettings.amoledKeyboard.value
        result.hideSeparators = WGAppearanceSettings.hideSeparators.value
        result.nameColorSaturation = wgClamp(double(WGAppearanceSettings.nameColorSaturation) / 100.0, 0.0, 1.0)

        let readRGB = wgAppearanceParseColor(WGAppearanceSettings.readCheckColor.value)
        result.readCheckRGB = readRGB
        if WGAppearanceSettings.unreadCheckSameAsRead.value, let readRGB {
            result.unreadCheckRGB = readRGB
        } else {
            result.unreadCheckRGB = wgAppearanceParseColor(WGAppearanceSettings.unreadCheckColor.value)
        }
        result.checkColorsInChatList = readRGB != nil && WGAppearanceSettings.checkColorsInChatList.value

        if WGAppearanceSettings.bubbleEditor.value {
            result.bubbles = WGBubbleAppearance(
                incomingRadius: wgClamp(double(WGAppearanceSettings.bubbleIncomingRadius), 0.0, 16.0),
                outgoingRadius: wgClamp(double(WGAppearanceSettings.bubbleOutgoingRadius), 0.0, 16.0),
                padding: wgClamp(double(WGAppearanceSettings.bubblePadding), 0.0, 24.0),
                widthFraction: wgClamp(double(WGAppearanceSettings.bubbleWidth) / 100.0, 0.4, 1.0),
                backgroundAlpha: wgClamp(double(WGAppearanceSettings.bubbleBackgroundOpacity) / 100.0, 0.0, 1.0),
                outlineAlpha: wgClamp(double(WGAppearanceSettings.bubbleOutlineOpacity) / 100.0, 0.0, 1.0)
            )
        }
        result.hideTails = WGAppearanceSettings.bubbleHideTails.value

        result.wideChannelPosts = WGAppearanceSettings.wideChannelPosts.value
        result.secondsInTime = WGAppearanceSettings.secondsInTime.value
        let hiddenReactions = WGHiddenReactions(rawValue: WGAppearanceSettings.hideReactions.value) ?? .off
        result.hideReactionsInChats = hiddenReactions.inChats
        result.hideReactionsInChannels = hiddenReactions.inChannels
        result.hideEdited = WGAppearanceSettings.hideEdited.value
        result.hideTime = WGAppearanceSettings.hideTime.value
        let hiddenFormatting = WGHiddenFormatting(rawValue: WGAppearanceSettings.hideFormatting.value) ?? .off
        result.hideIncomingFormatting = hiddenFormatting.inIncoming
        result.hideOutgoingFormatting = hiddenFormatting.inOutgoing
        result.hideChannelComments = WGAppearanceSettings.hideChannelComments.value
        result.hideViewCounts = WGAppearanceSettings.hideViewCounts.value
        result.colorSwatches = WGAppearanceSettings.colorSwatches.value
        result.authorOnlineIndicator = WGAppearanceSettings.authorOnlineIndicator.value
        result.exactLastSeen = WGAppearanceSettings.exactLastSeen.value
        result.tripleTapDelete = WGTripleTapDelete(rawValue: WGAppearanceSettings.tripleTapDelete.value) ?? .off
        result.noSelectionBlur = WGAppearanceSettings.noSelectionBlur.value
        result.stickerScale = wgClamp(double(WGAppearanceSettings.stickerSize) / 100.0, 0.5, 2.0)
        result.stickerHideTime = WGAppearanceSettings.stickerHideTime.value

        result.hideBackButton = WGAppearanceSettings.hideBackButton.value
        result.hideTitlePanel = WGAppearanceSettings.hideTitlePanel.value
        result.hideAvatar = WGAppearanceSettings.hideAvatar.value
        result.hidePinnedMessages = WGAppearanceSettings.hidePinnedMessages.value

        return result
    }
}

@inline(__always)
func wgClamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    if value.isNaN {
        return lower
    }
    return min(upper, max(lower, value))
}

/// Holds the snapshot. Rebuilt from `WGSettingsStore.shared.revision`, which moves on every write
/// (one rebuild ≈ 60 lock-protected copies, i.e. microseconds, only on writes); subscribers see only
/// distinct snapshots, so a write to an unrelated setting changes nothing downstream.
final class WGAppearanceSnapshotStore {
    static let shared = WGAppearanceSnapshotStore()

    /// The menu preview's snapshot (`WGAppearanceSnapshot.withPreview`). Written and read on the
    /// main thread only (`current` checks the thread first), so other threads never see it.
    static var mainThreadPreview: WGAppearanceSnapshot?

    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var value: WGAppearanceSnapshot?
    private var isObserving = false
    private let promise = ValuePromise<WGAppearanceSnapshot>(ignoreRepeated: true)
    private var disposable: Disposable?

    private init() {
        self.lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        self.lock.initialize(to: os_unfair_lock())
    }

    func current() -> WGAppearanceSnapshot {
        os_unfair_lock_lock(self.lock)
        if let value = self.value {
            os_unfair_lock_unlock(self.lock)
            return value
        }
        let startObserving = !self.isObserving
        self.isObserving = true
        os_unfair_lock_unlock(self.lock)

        if startObserving {
            self.startObserving()
        }
        return self.storeIfNeeded(WGAppearanceSnapshot.make())
    }

    func signal() -> Signal<WGAppearanceSnapshot, NoError> {
        let _ = self.current()
        return self.promise.get()
    }

    private func startObserving() {
        // The revision signal delivers its current value synchronously: done outside the lock.
        let disposable = (WGSettingsStore.shared.revision
        |> distinctUntilChanged).start(next: { [weak self] _ in
            guard let self else {
                return
            }
            let updated = WGAppearanceSnapshot.make()
            os_unfair_lock_lock(self.lock)
            let changed = self.value != updated
            self.value = updated
            os_unfair_lock_unlock(self.lock)
            if changed {
                self.promise.set(updated)
            }
        })
        os_unfair_lock_lock(self.lock)
        self.disposable = disposable
        os_unfair_lock_unlock(self.lock)
    }

    private func storeIfNeeded(_ snapshot: WGAppearanceSnapshot) -> WGAppearanceSnapshot {
        os_unfair_lock_lock(self.lock)
        if let value = self.value {
            os_unfair_lock_unlock(self.lock)
            return value
        }
        self.value = snapshot
        os_unfair_lock_unlock(self.lock)
        self.promise.set(snapshot)
        return snapshot
    }
}
