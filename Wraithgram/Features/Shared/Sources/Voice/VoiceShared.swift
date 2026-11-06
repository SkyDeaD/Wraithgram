import Foundation
import WGCore

/// The part of WGVoice that the extensions (notification service, share) also link: settings with
/// `.extensions` and NSE handlers. Owner: W3-1.
///
/// The voice settings are declared here rather than in WGVoice because upstream modules below the
/// feature layer read them on their hot paths (TelegramUI: the recorder and the playlist). Reading
/// is a snapshot load (WGCore), nothing else.
public enum WGVoiceShared {
    /// Called from `WGFeaturesShared.registerForApp()` and `.registerForExtension()`; check
    /// `WGCore.environment?.process` for what only one of them needs.
    public static func register() {
        WGVoiceSettings.declare()
    }
}

/// Every setting of the «Голос» zone, declared once. User switches are off by default; the «where to
/// apply» switches only act under their master switch, so the master alone gives a working default.
public enum WGVoiceSettings {
    // MARK: Voice changer

    public static let morphEnabled = WGSetting<Bool>("voice.morph.enabled", default: false)
    /// Preset id: anonymous, female, male, child, robot, custom (`WGVoicePresetID`).
    public static let morphPreset = WGSetting<String>("voice.morph.preset", default: "anonymous")
    public static let morphVoiceMessages = WGSetting<Bool>("voice.morph.voiceMessages", default: true)
    public static let morphRoundVideos = WGSetting<Bool>("voice.morph.roundVideos", default: true)
    public static let morphCalls = WGSetting<Bool>("voice.morph.calls", default: false)

    // MARK: «Свой голос» (user units, see WGVoiceParams)

    public static let customName = WGSetting<String>("voice.custom.name", default: "")
    /// Semitones −12…12.
    public static let customPitch = WGSetting<Double>("voice.custom.pitch", default: 0.0)
    /// −100…100 %.
    public static let customTimbre = WGSetting<Double>("voice.custom.timbre", default: 0.0)
    /// dB −12…12.
    public static let customBass = WGSetting<Double>("voice.custom.bass", default: 0.0)
    public static let customMid = WGSetting<Double>("voice.custom.mid", default: 0.0)
    public static let customTreble = WGSetting<Double>("voice.custom.treble", default: 0.0)
    public static let customGain = WGSetting<Double>("voice.custom.gain", default: 0.0)
    /// 0…100 %.
    public static let customDistortion = WGSetting<Double>("voice.custom.distortion", default: 0.0)
    public static let customReverb = WGSetting<Double>("voice.custom.reverb", default: 0.0)
    public static let customEcho = WGSetting<Double>("voice.custom.echo", default: 0.0)
    public static let customCompression = WGSetting<Double>("voice.custom.compression", default: 0.0)
    public static let customBreathiness = WGSetting<Double>("voice.custom.breathiness", default: 0.0)
    public static let customChorus = WGSetting<Double>("voice.custom.chorus", default: 0.0)
    public static let customFlanger = WGSetting<Double>("voice.custom.flanger", default: 0.0)
    public static let customVibratoDepth = WGSetting<Double>("voice.custom.vibratoDepth", default: 0.0)
    public static let customWet = WGSetting<Double>("voice.custom.wet", default: 100.0)
    /// Hz 0…12.
    public static let customVibratoRate = WGSetting<Double>("voice.custom.vibratoRate", default: 5.0)
    /// Hz 0…1000, 0 = off.
    public static let customRingMod = WGSetting<Double>("voice.custom.ringMod", default: 0.0)
    /// Bits 2…16, 16 = off.
    public static let customBitcrush = WGSetting<Double>("voice.custom.bitcrush", default: 16.0)
    public static let customTelephone = WGSetting<Bool>("voice.custom.telephone", default: false)

    // MARK: Playback equalizer

    public static let eqEnabled = WGSetting<Bool>("voice.eq.enabled", default: false)
    /// flat, bass, vocal, treble, custom.
    public static let eqPreset = WGSetting<String>("voice.eq.preset", default: "flat")
    /// dB −12…12; 60 Hz, 230 Hz, 910 Hz, 3.6 kHz, 14 kHz.
    public static let eqBand0 = WGSetting<Double>("voice.eq.band0", default: 0.0)
    public static let eqBand1 = WGSetting<Double>("voice.eq.band1", default: 0.0)
    public static let eqBand2 = WGSetting<Double>("voice.eq.band2", default: 0.0)
    public static let eqBand3 = WGSetting<Double>("voice.eq.band3", default: 0.0)
    public static let eqBand4 = WGSetting<Double>("voice.eq.band4", default: 0.0)
    public static let eqAudio = WGSetting<Bool>("voice.eq.audio", default: true)
    public static let eqRoundVideos = WGSetting<Bool>("voice.eq.roundVideos", default: true)
    public static let eqVideos = WGSetting<Bool>("voice.eq.videos", default: true)

    public static var eqBands: [WGSetting<Double>] {
        return [WGVoiceSettings.eqBand0, WGVoiceSettings.eqBand1, WGVoiceSettings.eqBand2, WGVoiceSettings.eqBand3, WGVoiceSettings.eqBand4]
    }

    // MARK: Playback and recording

    /// Do not play the next unheard voice message / round video after the current one ends.
    public static let disableAutoplay = WGSetting<Bool>("voice.disableAutoplay", default: false)
    /// Record voice messages and round videos with the built-in microphone even with a headset (SG-F3).
    public static let builtInMicrophone = WGSetting<Bool>("voice.builtInMicrophone", default: false)
    /// Mirror of the upstream `MediaInputSettings.pauseMusicOnRecording` (inverted) so the menu row
    /// redraws when Data & Storage changes it. Upstream stays the only source of truth.
    public static let keepMusicMirror = WGSetting<Bool>("voice.keepMusicMirror", default: false, flags: [.noExport])

    static func declare() {
        let _ = WGVoiceSettings.morphEnabled
        let _ = WGVoiceSettings.morphPreset
        let _ = WGVoiceSettings.morphVoiceMessages
        let _ = WGVoiceSettings.morphRoundVideos
        let _ = WGVoiceSettings.morphCalls
        let _ = WGVoiceSettings.customName
        let _ = WGVoiceSettings.customPitch
        let _ = WGVoiceSettings.customTimbre
        let _ = WGVoiceSettings.customBass
        let _ = WGVoiceSettings.customMid
        let _ = WGVoiceSettings.customTreble
        let _ = WGVoiceSettings.customGain
        let _ = WGVoiceSettings.customDistortion
        let _ = WGVoiceSettings.customReverb
        let _ = WGVoiceSettings.customEcho
        let _ = WGVoiceSettings.customCompression
        let _ = WGVoiceSettings.customBreathiness
        let _ = WGVoiceSettings.customChorus
        let _ = WGVoiceSettings.customFlanger
        let _ = WGVoiceSettings.customVibratoDepth
        let _ = WGVoiceSettings.customWet
        let _ = WGVoiceSettings.customVibratoRate
        let _ = WGVoiceSettings.customRingMod
        let _ = WGVoiceSettings.customBitcrush
        let _ = WGVoiceSettings.customTelephone
        let _ = WGVoiceSettings.eqEnabled
        let _ = WGVoiceSettings.eqPreset
        let _ = WGVoiceSettings.eqBand0
        let _ = WGVoiceSettings.eqBand1
        let _ = WGVoiceSettings.eqBand2
        let _ = WGVoiceSettings.eqBand3
        let _ = WGVoiceSettings.eqBand4
        let _ = WGVoiceSettings.eqAudio
        let _ = WGVoiceSettings.eqRoundVideos
        let _ = WGVoiceSettings.eqVideos
        let _ = WGVoiceSettings.disableAutoplay
        let _ = WGVoiceSettings.builtInMicrophone
        let _ = WGVoiceSettings.keepMusicMirror
    }
}

/// An effect the voice recorder runs over every captured block before the waveform and the encoder
/// see it, so the real voice is never written anywhere. Created once per recording (recorder queue).
public protocol WGVoiceRecordingEffect: AnyObject {
    /// Mono Int16 samples, processed in place; the length never changes. Recorder queue.
    func process(_ samples: UnsafeMutablePointer<Int16>, count: Int, sampleRate: Int)
}

public enum WGVoiceRecordingHooks {
    /// Provider (first non-nil wins), asked when a voice message recording starts. WGVoice.
    public static let effect = WGHookPoint<() -> WGVoiceRecordingEffect?>("voice.recordingEffect")

    /// `ManagedAudioRecorderContext.init`. Without handlers: nil, upstream behaviour.
    public static func makeEffect() -> WGVoiceRecordingEffect? {
        if WGVoiceRecordingHooks.effect.isEmpty {
            return nil
        }
        for handler in WGVoiceRecordingHooks.effect.handlers {
            if let effect = handler() {
                return effect
            }
        }
        return nil
    }

    /// `SharedMediaPlayer.setActionAtEnd`: stop after a voice message / round video instead of
    /// playing the next unheard one.
    public static var disablesNextVoiceAutoplay: Bool {
        return WGVoiceSettings.disableAutoplay.value
    }
}
