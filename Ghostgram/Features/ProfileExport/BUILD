load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Feature module GGProfileExport: fake gifts, chat export. Owner: W4-1.
# May depend on everything below TelegramUI; never on TelegramUI or another GG<Feature> module
# (FOUNDATION_SPEC §1.1).
swift_library(
    name = "GGProfileExport",
    module_name = "GGProfileExport",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Ghostgram/GGCore:GGCore",
        "//Ghostgram/GGHooks:GGHooks",
        "//Ghostgram/GGSettingsUI:GGSettingsUI",
        "//Ghostgram/Features/Shared:GGFeaturesShared",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/Display:Display",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        # Screens: lists, inputs, alerts, toasts, context menus.
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AlertUI:AlertUI",
        "//submodules/UndoUI:UndoUI",
        "//submodules/ContextUI:ContextUI",
        # «Локальные звёзды»: the amount is typed into a prompt.
        "//submodules/PromptUI:PromptUI",
        "//submodules/AppBundle:AppBundle",
        # Names (displayTitle) and service message texts in bulletins, editors and the export.
        "//submodules/LocalizedPeerData:LocalizedPeerData",
        "//submodules/TelegramStringFormatting:TelegramStringFormatting",
        # Fake gifts: the gift screen's menu point (GGGiftViewHooks).
        "//submodules/TelegramUI/Components/Gifts/GiftViewScreen:GiftViewScreen",
        # Chat export: the archive.
        "//third-party/ZipArchive:ZipArchive",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# The gift screen's menu point (GGGiftViewHooks), compiled INTO GiftViewScreen: it reads
# GiftViewScreen.Subject's internal `arguments`.
filegroup(
    name = "GiftViewScreenHookSources",
    srcs = glob([
        "GiftViewHooks/*.swift",
    ]),
    visibility = [
        "//submodules/TelegramUI/Components/Gifts/GiftViewScreen:__pkg__",
    ],
)
