import Foundation
import SwiftSignalKit
import WGCore
import WGFeaturesShared
import WGVoiceDSP

/// The playback equalizer's control side: publishes the gains to the C core (`WGAudioEqualizerSetParameters`)
/// when they change and keeps the preset and the bands consistent. The renderers (MediaPlayer, the video
/// player ChunkMediaPlayerV2 — videos and round videos stay on their upstream player) pick changes up on
/// their next block without resetting their filters, so a change does not click.
enum WGVoiceEqualizer {
    enum Preset: String, CaseIterable {
        case flat
        case bass
        case vocal
        case treble
        case custom

        var gains: [Double]? {
            switch self {
            case .flat:
                return [0.0, 0.0, 0.0, 0.0, 0.0]
            case .bass:
                return [8.0, 5.0, 0.0, -1.0, -2.0]
            case .vocal:
                return [-2.0, 0.0, 6.0, 4.0, -1.0]
            case .treble:
                return [-3.0, -1.0, 0.0, 5.0, 8.0]
            case .custom:
                return nil
            }
        }

        var title: String {
            switch self {
            case .flat:
                return WGStrings.Voice.Eq.presetFlat
            case .bass:
                return WGStrings.Voice.Eq.presetBass
            case .vocal:
                return WGStrings.Voice.Eq.presetVocal
            case .treble:
                return WGStrings.Voice.Eq.presetTreble
            case .custom:
                return WGStrings.Voice.Eq.presetCustom
            }
        }
    }

    private static var disposable: Disposable?
    private static var lastPublished: [Float]?
    private static var lastPreset: String?
    /// The bands of a newly chosen preset are being written. The revision is delivered synchronously
    /// on the main thread, so every band written re-enters `syncPresetAndBands` while the others
    /// still hold the old values: without this the first band «moved by hand» turned the preset
    /// into «Свой» at once.
    private static var isApplyingPreset = false

    static var currentGains: [Double] {
        return WGVoiceSettings.eqBands.map { $0.value }
    }

    /// Main thread, from `register()`: one subscription for the lifetime of the process.
    static func start() {
        if WGVoiceEqualizer.disposable != nil {
            return
        }
        WGVoiceEqualizer.lastPreset = WGVoiceSettings.eqPreset.value
        WGVoiceEqualizer.publish()
        WGVoiceEqualizer.disposable = (WGSettingsStore.shared.revision
        |> deliverOnMainQueue).start(next: { _ in
            if WGVoiceEqualizer.isApplyingPreset {
                // The outer pass publishes once every band is written.
                return
            }
            WGVoiceEqualizer.syncPresetAndBands()
            WGVoiceEqualizer.publish()
        })
    }

    /// A newly chosen preset sets the bands; a band moved by hand turns the preset into «Свой».
    private static func syncPresetAndBands() {
        let preset = WGVoiceSettings.eqPreset.value
        let bands = WGVoiceEqualizer.currentGains
        if preset != WGVoiceEqualizer.lastPreset {
            WGVoiceEqualizer.lastPreset = preset
            if let gains = Preset(rawValue: preset)?.gains, gains != bands {
                WGVoiceEqualizer.isApplyingPreset = true
                for (index, setting) in WGVoiceSettings.eqBands.enumerated() {
                    setting.set(gains[index])
                }
                WGVoiceEqualizer.isApplyingPreset = false
            }
        } else if let gains = Preset(rawValue: preset)?.gains, gains != bands {
            WGVoiceEqualizer.lastPreset = Preset.custom.rawValue
            WGVoiceSettings.eqPreset.set(Preset.custom.rawValue)
        }
    }

    private static func publish() {
        let enabled = WGVoiceSettings.eqEnabled.value
        let gains = WGVoiceEqualizer.currentGains.map { Float($0) }
        let audio = enabled && WGVoiceSettings.eqAudio.value
        let roundVideo = enabled && WGVoiceSettings.eqRoundVideos.value
        let video = enabled && WGVoiceSettings.eqVideos.value
        let snapshot = gains + [audio ? 1.0 : 0.0, roundVideo ? 1.0 : 0.0, video ? 1.0 : 0.0]
        if snapshot == WGVoiceEqualizer.lastPublished {
            return
        }
        WGVoiceEqualizer.lastPublished = snapshot
        gains.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                WGAudioEqualizerSetParameters(base, audio, roundVideo, video)
            }
        }
    }

    /// For the menu preview: the gains that are in effect for a preview (nil = off).
    static func previewGains() -> [Float]? {
        guard WGVoiceSettings.eqEnabled.value else {
            return nil
        }
        let gains = WGVoiceEqualizer.currentGains.map { Float($0) }
        return gains.contains(where: { abs($0) > 0.05 }) ? gains : nil
    }

    static func bandTitle(_ index: Int) -> String {
        let frequency = WGAudioEqualizerBandFrequency(Int32(index))
        if frequency >= 1000.0 {
            let kilohertz = Double(frequency) / 1000.0
            let formatted = kilohertz.truncatingRemainder(dividingBy: 1.0) == 0.0 ? String(Int(kilohertz)) : String(format: "%.1f", kilohertz)
            return WGStrings.Voice.Eq.kilohertz(value: formatted)
        }
        return WGStrings.Voice.Eq.hertz(value: String(Int(frequency)))
    }
}
