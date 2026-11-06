load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Feature module WGVless («VPN по подписке»). Owner: W3-5.
# May depend on everything below TelegramUI; never on TelegramUI or another WG<Feature> module
# (FOUNDATION_SPEC §1.1). The Xray core is NOT a dependency: it is a separate dynamic framework
# opened with dlopen (see README.md), so nothing here links Go code.
swift_library(
    name = "WGVless",
    module_name = "WGVless",
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
        # Screens: lists, inputs, alerts.
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AlertUI:AlertUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# The Telegram app's ipa_post_processor (one line in Telegram/BUILD, requests/W3-5.md): copies the
# prebuilt WGXrayCore.framework slice into Frameworks/ before signing. The slices are outputs of
# Core/build-core.sh and are not committed; with none built the script does nothing.
genrule(
    name = "EmbedXrayCore",
    srcs = [
        "Core/make-embed-script.sh",
    ] + glob([
        "Core/build/*/WGXrayCore.framework.zip",
    ], allow_empty = True),
    outs = [
        "EmbedXrayCore.sh",
    ],
    cmd_bash = "bash $(location Core/make-embed-script.sh) $@ $(SRCS)",
    executable = True,
    visibility = [
        "//Telegram:__pkg__",
    ],
)
