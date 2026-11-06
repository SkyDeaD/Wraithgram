load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Wraithgram core: settings registry and storage, canonical keys, foreground tasks, logger, network
# helper, shared inbox, hook point container, strings runtime + generated accessors. No UIKit, and
# nothing above SwiftSignalKit: TelegramCore and the extensions depend on it.
swift_library(
    name = "WGCore",
    module_name = "WGCore",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# The parts of WGCore that need TelegramCore / Postbox types (AccountRecordId.wg, PeerId.wgKey,
# MessageId.wgKey, the proxy and account bridges). Compiled INTO TelegramCore:
# submodules/TelegramCore/BUILD lists this label in its srcs (FOUNDATION_SPEC §1.2, done by W1-2).
filegroup(
    name = "TelegramCoreBridgeSources",
    srcs = glob([
        "Bridge/TelegramCore/**/*.swift",
    ]),
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) tests, like //submodules/MetalEngine:MetalPipelineCacheTests: WGCore's own sources are
# compiled into the test module (internal API is reachable without @testable), only SwiftSignalKit
# besides. Run with
#   ./build-input/bazel-9.2.0-darwin-arm64 test //Wraithgram/WGCore:WGCoreTests
# The string tools have their own tests: python3 Wraithgram/Strings/tests/test_tools.py
swift_test(
    name = "WGCoreTests",
    srcs = glob([
        "Sources/**/*.swift",
        "Tests/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
)
