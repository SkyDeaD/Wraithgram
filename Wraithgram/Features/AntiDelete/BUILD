load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Feature module WGAntiDelete. Owner: W2-2 (from wave 2 on this BUILD belongs to the owner).
# May depend on everything below TelegramUI; never on TelegramUI or another WG<Feature> module
# (FOUNDATION_SPEC §1.1). The capture, the attributes and the index are in WGFeaturesShared
# (Sources/AntiDelete): the notification service links them too.
swift_library(
    name = "WGAntiDelete",
    module_name = "WGAntiDelete",
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
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/Display:Display",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/AppBundle:AppBundle",
        "//submodules/ContextUI:ContextUI",
        "//submodules/PromptUI:PromptUI",
        "//submodules/Pasteboard:Pasteboard",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/ItemListPeerItem:ItemListPeerItem",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/LocalizedPeerData:LocalizedPeerData",
        "//submodules/TelegramStringFormatting:TelegramStringFormatting",
        # WGChatListHooks (chat list preview) and chatListFilterPredicate (folder exclusions).
        "//submodules/ChatListUI:ChatListUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# The bookmark row under the chat search field. A separate small library because the upstream
# component ChatSearchNavigationContentNode (W2-2's file, HOOKS.md §3) links it: it may only
# depend on modules below that component, never on WGAntiDelete itself.
swift_library(
    name = "WGBookmarkSearchRow",
    module_name = "WGBookmarkSearchRow",
    srcs = glob([
        "SearchRow/Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Wraithgram/WGCore:WGCore",
        "//Wraithgram/Features/Shared:WGFeaturesShared",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/Display:Display",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) tests of the pure model of anti-delete: the index (logs, caps, pruning, pages,
# summaries), the inbox records of the notification service, the migration of the old Wraithgram
# archive and the reply quote. Only those sources and WGCore are compiled, like WGCoreTests.
#   ./build-input/bazel-9.2.0-darwin-arm64 test //Wraithgram/Features/AntiDelete:WGAntiDeleteTests
# The model sources live in WGFeaturesShared (Sources/AntiDelete/Model); the filegroup that exports
# them is requested from the orchestrator (requests/W2-2.md, P5).
swift_test(
    name = "WGAntiDeleteTests",
    srcs = glob([
        "Tests/**/*.swift",
    ]) + [
        "//Wraithgram/Features/Shared:AntiDeleteModelSources",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Wraithgram/WGCore:WGCore",
    ],
)
