load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@rules_cc//cc:objc_library.bzl", "objc_library")

# Owner: W3-1 («Голос»). Targets:
#
#   WGVoiceDSP           — plain C: the one voice effect graph (voice messages, round videos, calls)
#                          and the playback equalizer. No Foundation, realtime-safe processing. Linked
#                          into UniversalMediaPlayer (equalizer in the audio renderers) and WGVoice.
#   WGVoice              — the feature: menu, preview, voice changer for voice messages / round
#                          videos / calls, equalizer parameters, migrations.
#
# Filegroups compiled INTO upstream modules (their BUILD lists the label in srcs), so the code stays
# under Wraithgram/:
#   TelegramAudioPoints                 — the built-in microphone policy (ManagedAudioSession).
#   UniversalMediaPlayerSources         — the equalizer instance of the audio renderers.
#   ChatMessageInteractiveFileNodeSources — "Quote" in the transcription's text selection.

objc_library(
    name = "WGVoiceDSP",
    enable_modules = True,
    module_name = "WGVoiceDSP",
    srcs = glob([
        "DSP/Sources/**/*.c",
    ]),
    hdrs = glob([
        "DSP/PublicHeaders/**/*.h",
    ]),
    includes = [
        "DSP/PublicHeaders",
        "DSP/PublicHeaders/WGVoiceDSP",
    ],
    copts = [
        "-std=c11",
        "-O2",
        "-Werror",
    ],
    visibility = [
        "//visibility:public",
    ],
)

filegroup(
    name = "TelegramAudioPoints",
    srcs = glob([
        "Points/TelegramAudio/**/*.swift",
    ]),
    visibility = [
        "//submodules/TelegramAudio:__pkg__",
    ],
)

filegroup(
    name = "UniversalMediaPlayerSources",
    srcs = glob([
        "Points/UniversalMediaPlayer/**/*.swift",
    ]),
    visibility = [
        "//submodules/MediaPlayer:__pkg__",
    ],
)

filegroup(
    name = "ChatMessageInteractiveFileNodeSources",
    srcs = glob([
        "Points/ChatMessageInteractiveFileNode/**/*.swift",
    ]),
    visibility = [
        "//submodules/TelegramUI/Components/Chat/ChatMessageInteractiveFileNode:__pkg__",
    ],
)

# Feature module WGVoice. May depend on everything below TelegramUI; never on TelegramUI or another
# WG<Feature> module (FOUNDATION_SPEC §1.1). WGCameraPipeline, WGCallAudio and WGCallsMediaHooks are
# the light point libraries of W3-2 / W3-3, not their feature modules.
swift_library(
    name = "WGVoice",
    module_name = "WGVoice",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":WGVoiceDSP",
        "//Wraithgram/WGCore:WGCore",
        "//Wraithgram/WGHooks:WGHooks",
        "//Wraithgram/WGSettingsUI:WGSettingsUI",
        "//Wraithgram/Features/Shared:WGFeaturesShared",
        "//Wraithgram/Features/CameraMasks:WGCameraPipeline",
        "//Wraithgram/Features/CallsMedia/CallAudio:WGCallAudio",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/Display:Display",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/TelegramAudio:TelegramAudio",
        "//submodules/TelegramVoip:TelegramVoip",
        "//submodules/TelegramCallsUI:TelegramCallsUI",
        "//submodules/UndoUI:UndoUI",
        "//submodules/PromptUI:PromptUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)
