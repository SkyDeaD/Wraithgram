import Foundation
import WGCore
import WGFeaturesShared

/// Old Wraithgram keys → `voice.*`. Same bundle id, so the old UserDefaults are still there.
/// Not carried over (owner's decisions 2026-10-21): the transcription engine switches
/// (`FontCustomization.useTelegramServerTranscription`, SG `transcriptionBackend`), the voice clone
/// (`WG.voiceClone.*` and its model files), tempo and reverse (no longer parameters: one graph that never
/// changes the length, for voice messages, round videos and calls alike).
enum WGVoiceMigrations {
    static func register() {
        WGMigrations.registerGlobal(id: "voice.v1") { legacy in
            WGVoiceMigrations.migrateMorpher(legacy)
            WGVoiceMigrations.migrateEqualizer(legacy)
            WGVoiceMigrations.dropLegacyTranscription(legacy)
            WGVoiceMigrations.migratePlayback(legacy)
            WGVoiceMigrations.dropRemoved(legacy)
        }
        // Wraithgram's own transcription (Apple Speech, word bubbles, auto-transcription) was removed:
        // transcription is Telegram's server one again, under Premium and its trial rules.
        WGMigrations.registerGlobal(id: "voice.transcription.removed.v1") { _ in
            WGRetiredSettings.remove(keys: ["voice.wordBubbles", "voice.autoTranscribe.enabled", "voice.autoTranscribe.roundVideos", "voice.autoTranscribe.format", "voice.autoTranscribe.translate", "voice.autoTranscribe.language"])
        }
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        return min(range.upperBound, max(range.lowerBound, value))
    }

    private static func migrateMorpher(_ legacy: WGLegacyDefaults) {
        let presetIds: [Int: String] = [1: "anonymous", 2: "female", 3: "male", 4: "child", 5: "robot", 6: "custom"]
        let enabled = legacy.bool("VoiceMorpher.isEnabled") ?? false
        if let preset = legacy.int("VoiceMorpher.selectedPreset") {
            if let id = presetIds[preset] {
                WGVoiceSettings.morphPreset.set(id)
                WGVoiceSettings.morphEnabled.set(enabled)
            } else {
                // 0 = «off», 7 = the voice clone, which is not carried over: the changer stays off rather
                // than silently using another voice.
                WGVoiceSettings.morphEnabled.set(false)
            }
        }
        if let name = legacy.string("VoiceMorpher.customName") {
            WGVoiceSettings.customName.set(name)
        }
        if let value = legacy.double("VoiceMorpher.customPitchShift") {
            WGVoiceSettings.customPitch.set(WGVoiceMigrations.clamp(value / 100.0, -12.0 ... 12.0))
        }
        if let value = legacy.double("VoiceMorpher.customFormantShift") {
            WGVoiceSettings.customTimbre.set(WGVoiceMigrations.clamp(value / 1200.0 * 100.0, -100.0 ... 100.0))
        }
        let decibels: [(String, WGSetting<Double>)] = [
            ("VoiceMorpher.customBassEQ", WGVoiceSettings.customBass),
            ("VoiceMorpher.customMidEQ", WGVoiceSettings.customMid),
            ("VoiceMorpher.customTrebleEQ", WGVoiceSettings.customTreble),
            ("VoiceMorpher.customGain", WGVoiceSettings.customGain)
        ]
        for (key, setting) in decibels {
            if let value = legacy.double(key) {
                setting.set(WGVoiceMigrations.clamp(value, -12.0 ... 12.0))
            }
        }
        let percents: [(String, WGSetting<Double>)] = [
            ("VoiceMorpher.customDistortionAmount", WGVoiceSettings.customDistortion),
            ("VoiceMorpher.customReverbAmount", WGVoiceSettings.customReverb),
            ("VoiceMorpher.customDelayAmount", WGVoiceSettings.customEcho),
            ("VoiceMorpher.customCompression", WGVoiceSettings.customCompression),
            ("VoiceMorpher.customBreathiness", WGVoiceSettings.customBreathiness),
            ("VoiceMorpher.customChorusAmount", WGVoiceSettings.customChorus),
            ("VoiceMorpher.customFlangerAmount", WGVoiceSettings.customFlanger),
            ("VoiceMorpher.customVibratoDepth", WGVoiceSettings.customVibratoDepth),
            ("VoiceMorpher.customDryWetMix", WGVoiceSettings.customWet)
        ]
        for (key, setting) in percents {
            if let value = legacy.double(key) {
                setting.set(WGVoiceMigrations.clamp(value, 0.0 ... 100.0))
            }
        }
        if let value = legacy.double("VoiceMorpher.customVibratoRate") {
            WGVoiceSettings.customVibratoRate.set(WGVoiceMigrations.clamp(value, 0.0 ... 12.0))
        }
        if let value = legacy.double("VoiceMorpher.customRingModFreq") {
            WGVoiceSettings.customRingMod.set(WGVoiceMigrations.clamp(value, 0.0 ... 1000.0))
        }
        if let value = legacy.double("VoiceMorpher.customBitcrushBits") {
            WGVoiceSettings.customBitcrush.set(WGVoiceMigrations.clamp(value, 2.0 ... 16.0))
        }
        if let value = legacy.bool("VoiceMorpher.customPhoneFilter") {
            WGVoiceSettings.customTelephone.set(value)
        }
        let keys = ["isEnabled", "selectedPreset", "customName", "customPitchShift", "customRate", "customDistortionAmount", "customReverbAmount", "customDelayAmount", "customFormantShift", "customBassEQ", "customMidEQ", "customTrebleEQ", "customCompression", "customGain", "customVibratoRate", "customVibratoDepth", "customBreathiness", "customDryWetMix", "customChorusAmount", "customRingModFreq", "customBitcrushBits", "customFlangerAmount", "customPhoneFilter", "customReverseAudio"]
        for key in keys {
            legacy.removeLegacyKey("VoiceMorpher." + key)
        }
    }

    private static func migrateEqualizer(_ legacy: WGLegacyDefaults) {
        // The preset first, then the bands: choosing a preset rewrites the bands with its own gains
        // (WGVoiceEqualizer), so bands written before it were lost. Written after it, bands that
        // differ from the preset turn it into «Свой», as moving a band by hand does.
        if let preset = legacy.string("GG.eq.preset"), ["flat", "bass", "vocal", "treble", "custom"].contains(preset) {
            WGVoiceSettings.eqPreset.set(preset)
        }
        var hasGain = false
        for (index, setting) in WGVoiceSettings.eqBands.enumerated() {
            let key = "GG.eq.band.\(index)"
            if let value = legacy.double(key) {
                let clamped = WGVoiceMigrations.clamp(value, -12.0 ... 12.0)
                setting.set(clamped)
                hasGain = hasGain || abs(clamped) > 0.05
            }
            legacy.removeLegacyKey(key)
        }
        let audio = legacy.bool("GG.eq.voice")
        let round = legacy.bool("GG.eq.videoCircle")
        let video = legacy.bool("GG.eq.video")
        if audio != nil || round != nil || video != nil {
            WGVoiceSettings.eqAudio.set(audio ?? false)
            WGVoiceSettings.eqRoundVideos.set(round ?? false)
            WGVoiceSettings.eqVideos.set(video ?? false)
            // The old equalizer was «on» when some band had gain and some kind of media was ticked.
            WGVoiceSettings.eqEnabled.set(hasGain && ((audio ?? false) || (round ?? false) || (video ?? false)))
        }
        for key in ["GG.eq.voice", "GG.eq.videoCircle", "GG.eq.video", "GG.eq.preset"] {
            legacy.removeLegacyKey(key)
        }
    }

    /// The old auto-transcription keys: the feature is gone, the keys are only dropped.
    private static func dropLegacyTranscription(_ legacy: WGLegacyDefaults) {
        for key in ["MiscSettings.autoTranscribeOwnVoice", "MiscSettings.voiceTranscriptionFormat", "MiscSettings.autoTranscribeTranslate", "MiscSettings.autoTranscribeTargetLanguage"] {
            legacy.removeLegacyKey(key)
        }
    }

    private static func migratePlayback(_ legacy: WGLegacyDefaults) {
        if let value = legacy.bool("disableNextVoiceAutoPlay") {
            WGVoiceSettings.disableAutoplay.set(value)
            legacy.removeLegacyKey("disableNextVoiceAutoPlay")
        }
        if let value = legacy.bool("forceBuiltInMic") {
            WGVoiceSettings.builtInMicrophone.set(value)
            legacy.removeLegacyKey("forceBuiltInMic")
        }
    }

    /// Keys and files of what is not carried over. The clone models were hundreds of megabytes in
    /// `Documents/voices`, in the iCloud backup: they are removed once, off the main thread.
    private static func dropRemoved(_ legacy: WGLegacyDefaults) {
        for key in ["FontCustomization.useTelegramServerTranscription", "transcriptionBackend", "GG.voiceClone.selectedVoiceId", "GG.voiceClone.cacheDiskLimitMB", "GG.voiceClone.catalog.json", "GG.voiceClone.catalogVersion", "GG.voiceClone.fetchedAt"] {
            legacy.removeLegacyKey(key)
        }
        DispatchQueue.global(qos: .utility).async {
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            let voices = documents.appendingPathComponent("voices", isDirectory: true)
            if FileManager.default.fileExists(atPath: voices.path) {
                try? FileManager.default.removeItem(at: voices)
            }
        }
    }
}
