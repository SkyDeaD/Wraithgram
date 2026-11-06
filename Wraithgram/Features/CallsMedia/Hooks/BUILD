load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Extension points of the «Calls» zone for the upstream call modules (TelegramCallsUI) that sit BELOW
# WGCallsMedia and do not see WGHooks. Owner: W3-3. The handlers live in WGCallsMedia (and, for the
# masks column of the call overlay, in W3-2's module); an empty point means upstream behaviour.
# Same pattern as //Wraithgram/Features/Appearance:WGAppearanceSettings (W2-4).
swift_library(
    name = "WGCallsMediaHooks",
    module_name = "WGCallsMediaHooks",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Wraithgram/WGCore:WGCore",
        "//Wraithgram/Features/CallsMedia/CallAudio:WGCallAudio",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramVoip:TelegramVoip",
        "//submodules/AccountContext:AccountContext",
    ],
    visibility = [
        "//visibility:public",
    ],
)
