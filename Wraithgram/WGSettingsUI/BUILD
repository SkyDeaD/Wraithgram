load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Wraithgram menu framework: the «Wraithgram» entry in Settings, root / categories / tabs generated from
# the registry, exteraGram-style rows, previews on the real renderers, search. Sits below SettingsUI
# and PeerInfoScreen (they depend on it) and above ChatListUI (real ChatListItem previews).
# Must never depend on SettingsUI, PeerInfoScreen or TelegramUI (FOUNDATION_SPEC §1.1).
swift_library(
    name = "WGSettingsUI",
    module_name = "WGSettingsUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Wraithgram/WGCore:WGCore",
        "//Wraithgram/WGHooks:WGHooks",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/AccountContext:AccountContext",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AppBundle:AppBundle",
        # Checkboxes of the expandable rows without a master switch (as in ItemListExpandableSwitchItem).
        "//submodules/CheckNode:CheckNode",
        # The slider and the discrete-choice rows (TGPhotoEditorSliderView, as upstream's pickers).
        "//submodules/LegacyComponents:LegacyComponents",
        "//submodules/UIKitRuntimeUtils:UIKitRuntimeUtils",
        # Mini chat on the real wallpaper, with the chat's glass header pills.
        "//submodules/WallpaperBackgroundNode:WallpaperBackgroundNode",
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent:GlassBackgroundComponent",
        # The account's emoji status in the mini chat's title pill, hidden with the chat list's
        # «Скрыть эмодзи-статусы» (WGChatListStyleHooks lives in ChatListTitleView).
        "//submodules/TelegramUI/Components/EmojiStatusComponent:EmojiStatusComponent",
        "//submodules/TelegramUI/Components/ChatListTitleView:ChatListTitleView",
        # Mini chat list on real ChatListItem rows.
        "//submodules/ChatListUI:ChatListUI",
        "//submodules/AvatarNode:AvatarNode",
        "//submodules/LocalizedPeerData:LocalizedPeerData",
        "//submodules/TextFormat:TextFormat",
        # Sub-screen headers with an animated sticker.
        "//submodules/LottieSettings:LottieSettings",
        "//submodules/AnimatedStickerNode:AnimatedStickerNode",
        "//submodules/TelegramAnimatedStickerNode:TelegramAnimatedStickerNode",
        # Toasts after export / import / reset.
        "//submodules/UndoUI:UndoUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Demo registration: one row of every kind and every preview. Not linked into the normal launch;
# see USAGE.md («Демо») for how the orchestrator enables it for a simulator check.
swift_library(
    name = "WGSettingsUIDemo",
    module_name = "WGSettingsUIDemo",
    srcs = glob([
        "Demo/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":WGSettingsUI",
        "//Wraithgram/WGCore:WGCore",
        "//submodules/Display:Display",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/ItemListUI:ItemListUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) tests of the menu model's pure parts: the summary of an expandable row without a master
# switch (2026-10-27), only Sources/Model/WGMenuGroupCount.swift (Foundation). Run with
#   ./build-input/bazel-9.2.0-darwin-arm64 test //Wraithgram/WGSettingsUI:WGSettingsUIModelTests
swift_test(
    name = "WGSettingsUIModelTests",
    srcs = [
        "Sources/Model/WGMenuGroupCount.swift",
    ] + glob([
        "Tests/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
)

# Menu assets (the ghost glyph). Must be listed in the app's resources next to
# //submodules/TelegramUI:TelegramUIAssets in Telegram/BUILD (asked of W1-2).
filegroup(
    name = "WGSettingsUIAssets",
    srcs = glob(["Assets/WGSettingsUI.xcassets/**"]),
    visibility = [
        "//visibility:public",
    ],
)
