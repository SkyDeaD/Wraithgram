load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Feature module WGRegDate, «Дата регистрации» (W7-RD1: Model, Estimate, Data; W7-RD2: the rest).
# May depend on everything below TelegramUI; never on TelegramUI or another WG<Feature> module
# (FOUNDATION_SPEC §1.1).
swift_library(
    name = "WGRegDate",
    module_name = "WGRegDate",
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
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramStringFormatting:TelegramStringFormatting",
        # The explanation alert and the «copied» toast.
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/UndoUI:UndoUI",
        # The shared profile-photo cache of the profile header (`peerInfoProfilePhotosWithCache`).
        "//submodules/PeerAvatarGalleryUI:PeerAvatarGalleryUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) tests of the plain logic: the contract and the estimate (W7-RD1), the store, the
# remote contract and the display rules (W7-RD2). Foundation only. Run with
#   ./build-input/bazel-9.2.0-darwin-arm64 test //Wraithgram/Features/RegDate:WGRegDateTests
swift_test(
    name = "WGRegDateTests",
    srcs = glob([
        "Sources/Model/**/*.swift",
        "Sources/Estimate/**/*.swift",
        "Sources/Store/**/*.swift",
        "Tests/**/*.swift",
    ]) + [
        "Sources/Format/WGRegDateDisplay.swift",
        "Sources/Remote/WGRegDateRemoteResponse.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
)
