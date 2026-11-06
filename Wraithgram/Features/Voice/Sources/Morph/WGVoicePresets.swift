import Foundation
import WGCore
import WGFeaturesShared
import WGVoiceDSP

/// The voice changer's presets. One parameter set drives the same C graph on all three paths
/// (voice messages, round videos, calls), so a preset sounds the same everywhere.
enum WGVoicePresetID: String, CaseIterable {
    case anonymous
    case female
    case male
    case child
    case robot
    case custom

    var title: String {
        switch self {
        case .anonymous:
            return WGStrings.Voice.Preset.anonymous
        case .female:
            return WGStrings.Voice.Preset.female
        case .male:
            return WGStrings.Voice.Preset.male
        case .child:
            return WGStrings.Voice.Preset.child
        case .robot:
            return WGStrings.Voice.Preset.robot
        case .custom:
            let name = WGVoiceSettings.customName.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? WGStrings.Voice.Preset.custom : name
        }
    }

    var subtitle: String {
        switch self {
        case .anonymous:
            return WGStrings.Voice.Preset.anonymousInfo
        case .female:
            return WGStrings.Voice.Preset.femaleInfo
        case .male:
            return WGStrings.Voice.Preset.maleInfo
        case .child:
            return WGStrings.Voice.Preset.childInfo
        case .robot:
            return WGStrings.Voice.Preset.robotInfo
        case .custom:
            return WGStrings.Voice.Preset.customInfo
        }
    }
}

/// Where a voice is changed. The anonymous mode (W3-2) overrides all three for its account.
enum WGVoiceScope {
    case voiceMessages
    case roundVideos
    case calls
}

enum WGVoicePresets {
    static func params(for preset: WGVoicePresetID) -> WGVoiceParams {
        var p = WGVoiceParams()
        WGVoiceParamsSetIdentity(&p)
        switch preset {
        case .anonymous:
            // Lower and darker, compressed, with breath and a slow random drift of the pitch: the drift is
            // the «hardening» against simply shifting the voice back, now in audible units.
            p.pitchSemitones = -3.5
            p.timbre = -0.35
            p.bassDb = 2.0
            p.trebleDb = -2.0
            p.distortion = 0.18
            p.reverbMix = 0.12
            p.reverbSize = 0.35
            p.jitter = 0.6
            p.breathiness = 0.15
            p.compression = 0.45
        case .female:
            p.pitchSemitones = 5.0
            p.timbre = 0.45
            p.trebleDb = 2.0
            p.reverbMix = 0.04
        case .male:
            p.pitchSemitones = -3.5
            p.timbre = -0.45
            p.bassDb = 3.0
            p.reverbMix = 0.03
        case .child:
            p.pitchSemitones = 7.0
            p.timbre = 0.65
            p.trebleDb = 3.0
            p.reverbMix = 0.05
        case .robot:
            p.ringModHz = 55.0
            p.ringModMix = 0.65
            p.distortion = 0.35
            p.bitcrushBits = 10.0
            p.telephone = 0.3
            p.reverbMix = 0.18
            p.reverbSize = 0.3
            p.echoMix = 0.12
            p.echoDelayMs = 70.0
            p.echoFeedback = 0.25
            p.compression = 0.5
        case .custom:
            p = WGVoicePresets.customParams()
        }
        return p
    }

    static func customParams() -> WGVoiceParams {
        var p = WGVoiceParams()
        WGVoiceParamsSetIdentity(&p)
        p.pitchSemitones = Float(WGVoiceSettings.customPitch.value)
        p.timbre = Float(WGVoiceSettings.customTimbre.value / 100.0)
        p.bassDb = Float(WGVoiceSettings.customBass.value)
        p.midDb = Float(WGVoiceSettings.customMid.value)
        p.trebleDb = Float(WGVoiceSettings.customTreble.value)
        p.gainDb = Float(WGVoiceSettings.customGain.value)
        p.distortion = Float(WGVoiceSettings.customDistortion.value / 100.0)
        p.reverbMix = Float(WGVoiceSettings.customReverb.value / 100.0)
        p.reverbSize = 0.5
        p.echoMix = Float(WGVoiceSettings.customEcho.value / 100.0)
        p.echoDelayMs = 180.0
        p.echoFeedback = 0.3
        p.compression = Float(WGVoiceSettings.customCompression.value / 100.0)
        p.breathiness = Float(WGVoiceSettings.customBreathiness.value / 100.0)
        p.chorus = Float(WGVoiceSettings.customChorus.value / 100.0)
        p.flanger = Float(WGVoiceSettings.customFlanger.value / 100.0)
        p.vibratoRateHz = Float(WGVoiceSettings.customVibratoRate.value)
        p.vibratoDepth = Float(WGVoiceSettings.customVibratoDepth.value / 100.0)
        p.ringModHz = Float(WGVoiceSettings.customRingMod.value)
        p.ringModMix = p.ringModHz > 0.0 ? 0.7 : 0.0
        p.bitcrushBits = Float(WGVoiceSettings.customBitcrush.value)
        p.telephone = WGVoiceSettings.customTelephone.value ? 1.0 : 0.0
        p.wet = Float(WGVoiceSettings.customWet.value / 100.0)
        return p
    }

    /// The selected preset (an unknown stored value falls back to the default, so the master switch
    /// always has something to apply — the old «on, but nothing chosen» state cannot happen).
    static var selectedPreset: WGVoicePresetID {
        return WGVoicePresetID(rawValue: WGVoiceSettings.morphPreset.value) ?? .anonymous
    }

    /// What to apply now on this path for this account, or nil (the sound stays untouched). Reads
    /// snapshots only. The anonymous mode wins over the user's own choice and needs no master switch.
    static func effectiveParams(scope: WGVoiceScope, account: WGAccountID?) -> WGVoiceParams? {
        if let account, let anonymous = WGAnonymousMode.voicePreset(for: account), let preset = WGVoicePresetID(rawValue: anonymous) {
            return WGVoicePresets.nonIdentity(WGVoicePresets.params(for: preset))
        }
        guard WGVoiceSettings.morphEnabled.value else {
            return nil
        }
        switch scope {
        case .voiceMessages:
            guard WGVoiceSettings.morphVoiceMessages.value else {
                return nil
            }
        case .roundVideos:
            guard WGVoiceSettings.morphRoundVideos.value else {
                return nil
            }
        case .calls:
            guard WGVoiceSettings.morphCalls.value else {
                return nil
            }
        }
        return WGVoicePresets.nonIdentity(WGVoicePresets.params(for: WGVoicePresets.selectedPreset))
    }

    static func nonIdentity(_ params: WGVoiceParams) -> WGVoiceParams? {
        var params = params
        return WGVoiceParamsIsIdentity(&params) ? nil : params
    }

    /// Byte image of a parameter set: equal sets need no new chain.
    static func fingerprint(_ params: WGVoiceParams?) -> Data? {
        guard var params else {
            return nil
        }
        return withUnsafeBytes(of: &params) { Data($0) }
    }
}
