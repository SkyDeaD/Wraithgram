import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import PromptUI
import WGCore
import WGSettingsUI
import WGFeaturesShared

/// «Медиа и звонки › Голос». Section orders on the skeleton tab start at 300 (100 = preview, 200 = main).
enum WGVoiceMenu {
    static let customTab = WGMenuTabID("voice.custom")
    static let bandsTab = WGMenuTabID("voice.eqBands")

    static let morphSection = WGMenuSectionID("voice.morph")
    static let eqSection = WGMenuSectionID("voice.eq")
    static let playbackSection = WGMenuSectionID("voice.playback")

    static func register() {
        WGVoiceMenu.registerPreview()
        WGVoiceMenu.registerMorph()
        WGVoiceMenu.registerCustomVoice()
        WGVoiceMenu.registerEqualizer()
        WGVoiceMenu.registerPlayback()
    }

    private static func toggle(_ id: String, section: WGMenuSectionID, order: Int, setting: WGSetting<Bool>, title: @escaping () -> String, subtitle: (() -> String)? = nil, isVisible: ((WGMenuContext) -> Bool)? = nil, keywords: @escaping () -> [String] = { [] }) -> WGMenuRow {
        return WGMenuRow(id: id, section: section, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting)), isVisible: isVisible, searchKeywords: keywords)
    }

    private static func slider(_ id: String, section: WGMenuSectionID, order: Int, setting: WGSetting<Double>, range: ClosedRange<Double>, step: Double, title: @escaping () -> String, format: @escaping (Double) -> String) -> WGMenuRow {
        return WGMenuRow(id: id, section: section, order: order, title: title, kind: .slider(.global(setting), range: range, step: step, format: format))
    }

    static func signed(_ value: Double, decimals: Bool = false) -> String {
        let rounded = decimals ? (value * 10.0).rounded() / 10.0 : value.rounded()
        let text: String
        if decimals && rounded.truncatingRemainder(dividingBy: 1.0) != 0.0 {
            text = String(format: "%.1f", abs(rounded))
        } else {
            text = String(Int(abs(rounded)))
        }
        if rounded > 0.0 {
            return "+" + text
        } else if rounded < 0.0 {
            return "−" + text
        }
        return text
    }

    static func percent(_ value: Double) -> String {
        return WGStrings.Voice.Unit.percent(value: String(Int(value.rounded())))
    }

    // MARK: Preview

    private static func registerPreview() {
        WGMenuRegistry.register(WGMenuRow(id: "voice.preview", section: .preview(of: .mediaVoice), order: 100, title: { "" }, kind: .preview(.custom(height: 138.0, make: { _ in
            return WGVoicePreviewView(frame: .zero)
        }))))
    }

    // MARK: Voice changer

    private static func registerMorph() {
        let screen = WGMenuScreenID.tab(.mediaVoice)
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGVoiceMenu.morphSection, screen: screen, order: 300, header: { WGStrings.Voice.Menu.morphHeader }, footer: { _ in
            return WGStrings.Voice.Menu.morphFooter
        }))
        let morphOn: (WGMenuContext) -> Bool = { _ in
            return WGVoiceSettings.morphEnabled.value
        }
        WGMenuRegistry.register(WGVoiceMenu.toggle("voice.morph.enabled", section: WGVoiceMenu.morphSection, order: 100, setting: WGVoiceSettings.morphEnabled, title: { WGStrings.Voice.Menu.morph }, subtitle: { WGStrings.Voice.Menu.morphInfo }, keywords: { [WGStrings.Voice.Menu.keywordMorph, WGStrings.Voice.Menu.keywordAnonymous] }))
        let presetOptions = WGVoicePresetID.allCases.map { preset in
            return WGMenuChoiceOption(value: preset.rawValue, title: { preset.title })
        }
        WGMenuRegistry.register(WGMenuRow(id: "voice.morph.preset", section: WGVoiceMenu.morphSection, order: 200, title: { WGStrings.Voice.Menu.preset }, subtitle: { WGVoicePresets.selectedPreset.subtitle }, kind: .choice(.global(WGVoiceSettings.morphPreset), options: presetOptions), searchKeywords: { [WGStrings.Voice.Menu.keywordMorph] }))
        WGMenuRegistry.register(WGVoiceMenu.toggle("voice.morph.voiceMessages", section: WGVoiceMenu.morphSection, order: 300, setting: WGVoiceSettings.morphVoiceMessages, title: { WGStrings.Voice.Menu.morphVoiceMessages }, subtitle: { WGStrings.Voice.Menu.morphVoiceMessagesInfo }, isVisible: morphOn))
        WGMenuRegistry.register(WGVoiceMenu.toggle("voice.morph.roundVideos", section: WGVoiceMenu.morphSection, order: 400, setting: WGVoiceSettings.morphRoundVideos, title: { WGStrings.Voice.Menu.morphRoundVideos }, isVisible: morphOn))
        WGMenuRegistry.register(WGVoiceMenu.toggle("voice.morph.calls", section: WGVoiceMenu.morphSection, order: 500, setting: WGVoiceSettings.morphCalls, title: { WGStrings.Voice.Menu.morphCalls }, subtitle: { WGStrings.Voice.Menu.morphCallsInfo }, isVisible: morphOn))
        WGMenuRegistry.register(tab: WGMenuTabDescriptor(id: WGVoiceMenu.customTab, parent: screen, title: { WGStrings.Voice.Custom.title }, topView: WGMenuTopView(content: .emoji("🎛"), text: { WGStrings.Voice.Custom.info }), searchKeywords: { [WGStrings.Voice.Menu.keywordMorph] }), linkIn: WGVoiceMenu.morphSection, order: 600, subtitle: { WGStrings.Voice.Menu.customInfo }, icon: .system("slider.horizontal.3"), label: { _ in
            return WGVoicePresets.selectedPreset == .custom ? WGStrings.Voice.Menu.selected : nil
        })

        // The anonymous mode (W3-2) offers the same presets; its choice overrides, nothing is rewritten.
        WGAnonymousMode.voicePresets.register({
            return WGVoicePresetID.allCases.map { preset in
                return WGAnonymousVoicePreset(id: preset.rawValue, title: { preset.title })
            }
        }, order: 100)
    }

    private static func registerCustomVoice() {
        let screen = WGMenuScreenID.tab(WGVoiceMenu.customTab)
        let pitch = WGMenuSectionID("voice.custom.pitch")
        let tone = WGMenuSectionID("voice.custom.tone")
        let effects = WGMenuSectionID("voice.custom.effects")
        let modulation = WGMenuSectionID("voice.custom.modulation")
        let mix = WGMenuSectionID("voice.custom.mix")
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: .main(of: WGVoiceMenu.customTab), screen: screen, order: 200))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: pitch, screen: screen, order: 300, header: { WGStrings.Voice.Custom.pitchHeader }, footer: { _ in WGStrings.Voice.Custom.pitchFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: tone, screen: screen, order: 400, header: { WGStrings.Voice.Custom.toneHeader }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: effects, screen: screen, order: 500, header: { WGStrings.Voice.Custom.effectsHeader }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: modulation, screen: screen, order: 600, header: { WGStrings.Voice.Custom.modulationHeader }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: mix, screen: screen, order: 700, header: { WGStrings.Voice.Custom.mixHeader }, footer: { _ in WGStrings.Voice.Custom.mixFooter }))

        WGMenuRegistry.register(WGMenuRow(id: "voice.custom.name", section: .main(of: WGVoiceMenu.customTab), order: 100, title: { WGStrings.Voice.Custom.name }, kind: .action({ context in
            context.present(promptController(context: context.context, text: WGStrings.Voice.Custom.namePrompt, value: WGVoiceSettings.customName.value, characterLimit: 32, apply: { value in
                if let value {
                    WGVoiceSettings.customName.set(value.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }))
        }), label: { _ in
            let name = WGVoiceSettings.customName.value
            return name.isEmpty ? nil : name
        }))
        WGMenuRegistry.register(WGMenuRow(id: "voice.custom.use", section: .main(of: WGVoiceMenu.customTab), order: 200, title: { WGStrings.Voice.Custom.use }, kind: .action({ _ in
            WGVoiceSettings.morphPreset.set(WGVoicePresetID.custom.rawValue)
        }), isVisible: { _ in
            return WGVoicePresets.selectedPreset != .custom
        }))

        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.pitch", section: pitch, order: 100, setting: WGVoiceSettings.customPitch, range: -12.0 ... 12.0, step: 0.5, title: { WGStrings.Voice.Custom.pitch }, format: { value in
            return WGStrings.Voice.Unit.semitones(value: WGVoiceMenu.signed(value, decimals: true))
        }))
        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.timbre", section: pitch, order: 200, setting: WGVoiceSettings.customTimbre, range: -100.0 ... 100.0, step: 5.0, title: { WGStrings.Voice.Custom.timbre }, format: { value in
            return WGStrings.Voice.Unit.percent(value: WGVoiceMenu.signed(value))
        }))
        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.vibratoDepth", section: pitch, order: 300, setting: WGVoiceSettings.customVibratoDepth, range: 0.0 ... 100.0, step: 5.0, title: { WGStrings.Voice.Custom.vibratoDepth }, format: WGVoiceMenu.percent))
        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.vibratoRate", section: pitch, order: 400, setting: WGVoiceSettings.customVibratoRate, range: 0.0 ... 12.0, step: 0.5, title: { WGStrings.Voice.Custom.vibratoRate }, format: { value in
            return WGStrings.Voice.Eq.hertz(value: WGVoiceMenu.signed(value, decimals: true))
        }))

        let decibels: (Double) -> String = { value in
            return WGStrings.Voice.Unit.decibels(value: WGVoiceMenu.signed(value))
        }
        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.bass", section: tone, order: 100, setting: WGVoiceSettings.customBass, range: -12.0 ... 12.0, step: 1.0, title: { WGStrings.Voice.Custom.bass }, format: decibels))
        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.mid", section: tone, order: 200, setting: WGVoiceSettings.customMid, range: -12.0 ... 12.0, step: 1.0, title: { WGStrings.Voice.Custom.mid }, format: decibels))
        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.treble", section: tone, order: 300, setting: WGVoiceSettings.customTreble, range: -12.0 ... 12.0, step: 1.0, title: { WGStrings.Voice.Custom.treble }, format: decibels))
        WGMenuRegistry.register(WGVoiceMenu.toggle("voice.custom.telephone", section: tone, order: 400, setting: WGVoiceSettings.customTelephone, title: { WGStrings.Voice.Custom.telephone }))

        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.distortion", section: effects, order: 100, setting: WGVoiceSettings.customDistortion, range: 0.0 ... 100.0, step: 5.0, title: { WGStrings.Voice.Custom.distortion }, format: WGVoiceMenu.percent))
        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.reverb", section: effects, order: 200, setting: WGVoiceSettings.customReverb, range: 0.0 ... 100.0, step: 5.0, title: { WGStrings.Voice.Custom.reverb }, format: WGVoiceMenu.percent))
        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.echo", section: effects, order: 300, setting: WGVoiceSettings.customEcho, range: 0.0 ... 100.0, step: 5.0, title: { WGStrings.Voice.Custom.echo }, format: WGVoiceMenu.percent))
        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.breathiness", section: effects, order: 400, setting: WGVoiceSettings.customBreathiness, range: 0.0 ... 100.0, step: 5.0, title: { WGStrings.Voice.Custom.breathiness }, format: WGVoiceMenu.percent))
        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.compression", section: effects, order: 500, setting: WGVoiceSettings.customCompression, range: 0.0 ... 100.0, step: 5.0, title: { WGStrings.Voice.Custom.compression }, format: WGVoiceMenu.percent))

        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.chorus", section: modulation, order: 100, setting: WGVoiceSettings.customChorus, range: 0.0 ... 100.0, step: 5.0, title: { WGStrings.Voice.Custom.chorus }, format: WGVoiceMenu.percent))
        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.flanger", section: modulation, order: 200, setting: WGVoiceSettings.customFlanger, range: 0.0 ... 100.0, step: 5.0, title: { WGStrings.Voice.Custom.flanger }, format: WGVoiceMenu.percent))
        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.ringMod", section: modulation, order: 300, setting: WGVoiceSettings.customRingMod, range: 0.0 ... 1000.0, step: 10.0, title: { WGStrings.Voice.Custom.ringMod }, format: { value in
            return value < 1.0 ? WGStrings.Voice.Unit.off : WGStrings.Voice.Eq.hertz(value: String(Int(value.rounded())))
        }))
        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.bitcrush", section: modulation, order: 400, setting: WGVoiceSettings.customBitcrush, range: 2.0 ... 16.0, step: 1.0, title: { WGStrings.Voice.Custom.bitcrush }, format: { value in
            return value >= 15.5 ? WGStrings.Voice.Unit.off : WGStrings.Voice.Unit.bits(value: String(Int(value.rounded())))
        }))

        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.gain", section: mix, order: 100, setting: WGVoiceSettings.customGain, range: -12.0 ... 12.0, step: 1.0, title: { WGStrings.Voice.Custom.gain }, format: decibels))
        WGMenuRegistry.register(WGVoiceMenu.slider("voice.custom.wet", section: mix, order: 200, setting: WGVoiceSettings.customWet, range: 0.0 ... 100.0, step: 5.0, title: { WGStrings.Voice.Custom.wet }, format: WGVoiceMenu.percent))
        WGMenuRegistry.register(WGMenuRow(id: "voice.custom.reset", section: mix, order: 300, title: { WGStrings.Voice.Custom.reset }, kind: .action({ _ in
            WGVoiceMenu.resetCustomVoice()
        }), isDestructive: true))
    }

    private static func resetCustomVoice() {
        WGVoiceSettings.customPitch.reset()
        WGVoiceSettings.customTimbre.reset()
        WGVoiceSettings.customBass.reset()
        WGVoiceSettings.customMid.reset()
        WGVoiceSettings.customTreble.reset()
        WGVoiceSettings.customGain.reset()
        WGVoiceSettings.customDistortion.reset()
        WGVoiceSettings.customReverb.reset()
        WGVoiceSettings.customEcho.reset()
        WGVoiceSettings.customCompression.reset()
        WGVoiceSettings.customBreathiness.reset()
        WGVoiceSettings.customChorus.reset()
        WGVoiceSettings.customFlanger.reset()
        WGVoiceSettings.customVibratoDepth.reset()
        WGVoiceSettings.customVibratoRate.reset()
        WGVoiceSettings.customRingMod.reset()
        WGVoiceSettings.customBitcrush.reset()
        WGVoiceSettings.customTelephone.reset()
        WGVoiceSettings.customWet.reset()
    }

    // MARK: Equalizer

    private static func registerEqualizer() {
        let screen = WGMenuScreenID.tab(.mediaVoice)
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGVoiceMenu.eqSection, screen: screen, order: 400, header: { WGStrings.Voice.Eq.header }, footer: { _ in WGStrings.Voice.Eq.footer }))
        let eqOn: (WGMenuContext) -> Bool = { _ in
            return WGVoiceSettings.eqEnabled.value
        }
        WGMenuRegistry.register(WGVoiceMenu.toggle("voice.eq.enabled", section: WGVoiceMenu.eqSection, order: 100, setting: WGVoiceSettings.eqEnabled, title: { WGStrings.Voice.Eq.enabled }, keywords: { [WGStrings.Voice.Eq.keyword] }))
        let presetOptions = WGVoiceEqualizer.Preset.allCases.map { preset in
            return WGMenuChoiceOption(value: preset.rawValue, title: { preset.title })
        }
        WGMenuRegistry.register(WGMenuRow(id: "voice.eq.preset", section: WGVoiceMenu.eqSection, order: 200, title: { WGStrings.Voice.Eq.preset }, kind: .choice(.global(WGVoiceSettings.eqPreset), options: presetOptions), isVisible: eqOn, searchKeywords: { [WGStrings.Voice.Eq.keyword] }))
        WGMenuRegistry.register(tab: WGMenuTabDescriptor(id: WGVoiceMenu.bandsTab, parent: screen, title: { WGStrings.Voice.Eq.bandsTitle }, topView: WGMenuTopView(content: .emoji("🎚"), text: { WGStrings.Voice.Eq.bandsInfo }), searchKeywords: { [WGStrings.Voice.Eq.keyword] }), linkIn: WGVoiceMenu.eqSection, order: 300, subtitle: { WGStrings.Voice.Eq.bandsSubtitle }, icon: .system("slider.vertical.3"), label: { _ in
            return WGVoiceSettings.eqEnabled.value ? WGVoiceEqualizer.Preset(rawValue: WGVoiceSettings.eqPreset.value)?.title : nil
        })
        WGMenuRegistry.register(WGVoiceMenu.toggle("voice.eq.audio", section: WGVoiceMenu.eqSection, order: 400, setting: WGVoiceSettings.eqAudio, title: { WGStrings.Voice.Eq.audio }, isVisible: eqOn))
        WGMenuRegistry.register(WGVoiceMenu.toggle("voice.eq.roundVideos", section: WGVoiceMenu.eqSection, order: 500, setting: WGVoiceSettings.eqRoundVideos, title: { WGStrings.Voice.Eq.roundVideos }, isVisible: eqOn))
        WGMenuRegistry.register(WGVoiceMenu.toggle("voice.eq.videos", section: WGVoiceMenu.eqSection, order: 600, setting: WGVoiceSettings.eqVideos, title: { WGStrings.Voice.Eq.videos }, isVisible: eqOn))

        let decibels: (Double) -> String = { value in
            return WGStrings.Voice.Unit.decibels(value: WGVoiceMenu.signed(value))
        }
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: .main(of: WGVoiceMenu.bandsTab), screen: .tab(WGVoiceMenu.bandsTab), order: 200, footer: { _ in WGStrings.Voice.Eq.bandsFooter }))
        for (index, setting) in WGVoiceSettings.eqBands.enumerated() {
            WGMenuRegistry.register(WGVoiceMenu.slider("voice.eq.band\(index)", section: .main(of: WGVoiceMenu.bandsTab), order: 100 + index * 100, setting: setting, range: -12.0 ... 12.0, step: 1.0, title: { WGVoiceEqualizer.bandTitle(index) }, format: decibels))
        }
    }

    // MARK: Playback and recording

    private static func registerPlayback() {
        let screen = WGMenuScreenID.tab(.mediaVoice)
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGVoiceMenu.playbackSection, screen: screen, order: 600, header: { WGStrings.Voice.Playback.header }, footer: { _ in WGStrings.Voice.Playback.footer }))
        WGMenuRegistry.register(WGVoiceMenu.toggle("voice.disableAutoplay", section: WGVoiceMenu.playbackSection, order: 100, setting: WGVoiceSettings.disableAutoplay, title: { WGStrings.Voice.Playback.disableAutoplay }, subtitle: { WGStrings.Voice.Playback.disableAutoplayInfo }))
        WGMenuRegistry.register(WGVoiceMenu.toggle("voice.builtInMicrophone", section: WGVoiceMenu.playbackSection, order: 200, setting: WGVoiceSettings.builtInMicrophone, title: { WGStrings.Voice.Playback.builtInMicrophone }, subtitle: { WGStrings.Voice.Playback.builtInMicrophoneInfo }, keywords: { [WGStrings.Voice.Playback.keywordMicrophone] }))
        WGMenuRegistry.register(WGVoiceMenu.toggle("voice.keepMusic", section: WGVoiceMenu.playbackSection, order: 300, setting: WGVoiceSettings.keepMusicMirror, title: { WGStrings.Voice.Playback.keepMusic }, subtitle: { WGStrings.Voice.Playback.keepMusicInfo }))
    }
}
