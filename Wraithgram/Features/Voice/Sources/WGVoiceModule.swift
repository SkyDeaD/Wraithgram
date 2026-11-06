import Foundation
import AccountContext
import TelegramAudio
import WGCore
import WGHooks
import WGFeaturesShared

/// Entry point of the WGVoice feature module. Owner: W3-1.
public enum WGVoiceModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `WGFeatures.registerAll()`, before `WGHookRegistry.freeze()`.
    public static func register() {
        // Settings are declared by WGVoiceShared (WGFeaturesShared): upstream modules read them.
        WGVoiceMigrations.register()
        WGVoiceMenu.register()

        // The voice changer: recorder (voice messages), round video audio stage, calls.
        WGVoiceMorphHooks.register()
        // «Всегда встроенный микрофон» (SG-F3), read by ManagedAudioSession while recording.
        WGAudioSessionHooks.prefersBuiltInMicrophoneForRecording.register({
            return WGVoiceSettings.builtInMicrophone.value
        }, order: 100)

        WGLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            let sharedContext = context.sharedContext
            WGVoiceAccounts.shared.start(sharedContext: sharedContext)
            WGVoiceCallEffectController.shared.start(sharedContext: sharedContext)
            WGVoiceKeepMusic.shared.start(sharedContext: sharedContext)
        }, order: 300)

        // Publishes the playback equalizer's parameters (one subscription for the process).
        WGVoiceEqualizer.start()
    }
}
