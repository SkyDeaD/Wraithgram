import Foundation
import SwiftSignalKit
import WGCore

/// The part of WGCameraMasks other zones read: the anonymous mode (a mask and a voice in one tap).
/// The voice changer (W3-1) asks `WGAnonymousMode.voicePreset(for:)` and, while it answers, uses
/// that preset instead of the user's own; it registers its presets for the menu in
/// `WGAnonymousMode.voicePresets`. Owner: W3-2.
public enum WGCameraMasksShared {
    /// Called from `WGFeaturesShared.registerForApp()` and `.registerForExtension()`.
    public static func register() {
        WGAnonymousMode.declare()
    }
}

/// A voice preset the anonymous mode can use (registered by the voice changer).
public struct WGAnonymousVoicePreset {
    public let id: String
    public let title: () -> String

    public init(id: String, title: @escaping () -> String) {
        self.id = id
        self.title = title
    }
}

/// «Анонимный режим»: a temporary override over the user's own choices, per account. While it is on,
/// round videos and calls of that account use the anonymous mask, and the voice changer uses the
/// anonymous preset. Nothing is snapshotted or restored: turning it off simply removes the override,
/// so it can never restore a preset of another account. Picking a mask by hand turns it off for that
/// account (the manual choice wins), so the two never disagree.
public enum WGAnonymousMode {
    public static let isActive = WGAccountSetting<Bool>("cameraMasks.anonymous.active", default: false)
    /// `WGMaskSelection` storage ("builtin:<id>", "catalog:<id>", "user:<id>").
    public static let mask = WGSetting<String>("cameraMasks.anonymous.mask", default: "builtin:pixelate")
    /// Id of a preset from `voicePresets`.
    public static let voice = WGSetting<String>("cameraMasks.anonymous.voice", default: "robot")

    /// The voice changer's presets for the menu. Empty: the voice row is hidden.
    public static let voicePresets = WGHookPoint<() -> [WGAnonymousVoicePreset]>("cameraMasks.anonymousVoicePresets")

    static func declare() {
        let _ = WGAnonymousMode.isActive
        let _ = WGAnonymousMode.mask
        let _ = WGAnonymousMode.voice
    }

    /// The preset the voice changer must use for this account now, or nil (the user's own settings).
    public static func voicePreset(for account: WGAccountID) -> String? {
        guard WGAnonymousMode.isActive.value(for: account) else {
            return nil
        }
        let value = WGAnonymousMode.voice.value
        return value.isEmpty ? nil : value
    }

    /// The anonymous mask storage for this account now, or nil.
    public static func maskOverride(for account: WGAccountID) -> String? {
        guard WGAnonymousMode.isActive.value(for: account) else {
            return nil
        }
        return WGAnonymousMode.mask.value
    }

    public static func allVoicePresets() -> [WGAnonymousVoicePreset] {
        var result: [WGAnonymousVoicePreset] = []
        for handler in WGAnonymousMode.voicePresets.handlers {
            result.append(contentsOf: handler())
        }
        return result
    }
}
