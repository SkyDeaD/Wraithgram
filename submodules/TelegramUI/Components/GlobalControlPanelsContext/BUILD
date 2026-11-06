load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "GlobalControlPanelsContext",
    module_name = "GlobalControlPanelsContext",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/TelegramStringFormatting",
        "//submodules/AccountContext",
        # WRAITH: Swiftgram-parity settings (W5-SG)
        "//Wraithgram/Features/Shared:WGFeaturesShared",
        "//submodules/TelegramUIPreferences",
        "//submodules/TelegramCallsUI",
        "//submodules/Display",
        "//submodules/UndoUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)
