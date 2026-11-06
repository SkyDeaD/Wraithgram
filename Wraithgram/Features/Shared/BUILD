load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Light shared part of the features, linked into the extensions. Sources/<Zone>/** belong to the
# zone owners; the aggregator Sources/WGFeaturesShared.swift and this BUILD belong to W1-2.
# May depend on WGCore, TelegramCore, Postbox, SwiftSignalKit and nothing else (FOUNDATION_SPEC §1.1).
swift_library(
    name = "WGFeaturesShared",
    module_name = "WGFeaturesShared",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Wraithgram/WGCore:WGCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# The anti-delete model (index, export, quotes) without iOS dependencies, for the host test
# WGAntiDeleteTests in //Wraithgram/Features/AntiDelete (W2-2 request P5). Not part of the app build.
filegroup(
    name = "AntiDeleteModelSources",
    srcs = glob(["Sources/AntiDelete/Model/**/*.swift"]),
    visibility = ["//Wraithgram/Features/AntiDelete:__pkg__"],
)

# Host (macOS) tests of the pure merges of 2026-10-27 — the one send delay and the one «no pull to the
# next channel or topic» switch: only their Foundation files. Not part of the app build. Run with
#   ./build-input/bazel-9.2.0-darwin-arm64 test //Wraithgram/Features/Shared:WGFeaturesSharedTests
swift_test(
    name = "WGFeaturesSharedTests",
    srcs = [
        "Sources/GhostMode/WGSendDelaySeconds.swift",
        "Sources/Messages/WGScrollToNextMerge.swift",
    ] + glob([
        "Tests/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
)
