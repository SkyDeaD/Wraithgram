load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Feature module WGCallsMedia. Owner: W3-3.
# May depend on everything below TelegramUI; never on TelegramUI or another WG<Feature> module
# (FOUNDATION_SPEC §1.1).
#
# Hooks/      — swift_library WGCallsMediaHooks: points for the call modules below this one
#               (TelegramCallsUI depends on it), handlers registered here and by W3-2.
# CallAudio/  — objc_library WGCallAudio: the realtime part of the call audio effects, linked into
#               TgVoipWebrtc and used from TelegramVoip.
swift_library(
    name = "WGCallsMedia",
    module_name = "WGCallsMedia",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Wraithgram/WGCore:WGCore",
        "//Wraithgram/WGHooks:WGHooks",
        "//Wraithgram/WGSettingsUI:WGSettingsUI",
        "//Wraithgram/Features/Shared:WGFeaturesShared",
        "//Wraithgram/Features/CallsMedia/Hooks:WGCallsMediaHooks",
        "//Wraithgram/Features/CallsMedia/CallAudio:WGCallAudio",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/Display:Display",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/TelegramAudio:TelegramAudio",
        "//submodules/TelegramVoip:TelegramVoip",
        "//submodules/TelegramCallsUI:TelegramCallsUI",
        "//submodules/ChatListUI:ChatListUI",
        "//submodules/FetchManagerImpl:FetchManagerImpl",
        "//submodules/ImageCompression:ImageCompression",
        "//submodules/ContextUI:ContextUI",
        "//submodules/UndoUI:UndoUI",
        "//submodules/AppBundle:AppBundle",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/PromptUI:PromptUI",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
        "//third-party/LibYuvBinding",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) tests of «Записывать звонки» as one choice (2026-10-27): only
# Sources/Settings/WGCallRecordingMode.swift (Foundation). Run with
#   ./build-input/bazel-9.2.0-darwin-arm64 test //Wraithgram/Features/CallsMedia:WGCallRecordingModeTests
swift_test(
    name = "WGCallRecordingModeTests",
    srcs = [
        "Sources/Settings/WGCallRecordingMode.swift",
    ] + glob([
        "Tests/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
)
