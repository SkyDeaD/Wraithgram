load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Feature module WGExtras (W5-SG): the Swiftgram user features Wraithgram did not have yet, written as
# Wraithgram features. Settings and the policy read by upstream call sites live in WGFeaturesShared
# (Sources/Extras). May depend on everything below TelegramUI; never on TelegramUI or another
# WG<Feature> module (FOUNDATION_SPEC §1.1).
swift_library(
    name = "WGExtras",
    module_name = "WGExtras",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":WGExtrasHooks",
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
        "//submodules/ContextUI:ContextUI",
        "//submodules/AppBundle:AppBundle",
        "//submodules/UndoUI:UndoUI",
        "//submodules/PeerInfoUI:PeerInfoUI",
        "//submodules/ChatInterfaceState:ChatInterfaceState",
        # «Переслать без автора»: the picker's comment and «Запланировать» (as in Telegram's forward).
        "//submodules/TextFormat:TextFormat",
        "//submodules/TelegramUI/Components/ChatScheduleTimeController:ChatScheduleTimeController",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# UI points with AccountContext (selection panel buttons, link menu, in-app browser). Below every
# module that calls them: ChatMessageSelectionInputPanelNode, TelegramUI.
swift_library(
    name = "WGExtrasHooks",
    module_name = "WGExtrasHooks",
    srcs = glob([
        "Hooks/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Wraithgram/WGCore:WGCore",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/Display:Display",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Points TelegramCore itself calls (in-chat search fallback, restriction text): compiled INTO
# TelegramCore, like //Wraithgram/WGHooks:TelegramCoreHookSources.
filegroup(
    name = "TelegramCoreSources",
    srcs = glob(["Core/**/*.swift"]),
    visibility = ["//visibility:public"],
)
