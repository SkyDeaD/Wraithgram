load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Owner: W2-4. Two targets:
#
#   WGAppearanceSettings — the appearance settings and their snapshot. WGCore only, so the upstream
#                          modules that draw them (bubble background, status line, text formatting…)
#                          can read the registry directly, down to below TelegramCore.
#   WGAppearance         — the feature: menu rows, previews, theme transformer, bubble shape, fonts,
#                          chat overlays, chat-list header decorations, profile rows, imports, migration.
#                          May depend on everything below TelegramUI (FOUNDATION_SPEC §1.1).
#
# No font files: the font choice offers only the fonts that ship with iOS (owner decision 2026-10-22).

swift_library(
    name = "WGAppearanceSettings",
    module_name = "WGAppearanceSettings",
    srcs = glob([
        "Settings/Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Wraithgram/WGCore:WGCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Compiled INTO ChatMessageItemImpl: the online dot on authors' avatars.
filegroup(
    name = "ChatMessageItemImplSources",
    srcs = glob([
        "Upstream/ChatMessageItemImpl/**/*.swift",
    ]),
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "WGAppearance",
    module_name = "WGAppearance",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":WGAppearanceSettings",
        "//Wraithgram/WGCore:WGCore",
        "//Wraithgram/WGHooks:WGHooks",
        "//Wraithgram/WGSettingsUI:WGSettingsUI",
        "//Wraithgram/Features/Shared:WGFeaturesShared",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramStringFormatting:TelegramStringFormatting",
        "//submodules/Display:Display",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/LegacyComponents:LegacyComponents",
        "//submodules/TelegramUI/Components/EdgeEffect:EdgeEffect",
        "//submodules/TelegramUI/Components/ChatListHeaderComponent:ChatListHeaderComponent",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/UndoUI:UndoUI",
        # The sticker-size preview: the chat's wallpaper, the time format, the account's name.
        "//submodules/WallpaperBackgroundNode:WallpaperBackgroundNode",
        "//submodules/TextFormat:TextFormat",
        "//submodules/LocalizedPeerData:LocalizedPeerData",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) tests of the choices that replaced switch pairs and the screen-edge rows (2026-10-27):
# only Settings/Sources/WGAppearanceChoices.swift (Foundation). Run with
#   ./build-input/bazel-9.2.0-darwin-arm64 test //Wraithgram/Features/Appearance:WGAppearanceChoicesTests
swift_test(
    name = "WGAppearanceChoicesTests",
    srcs = [
        "Settings/Sources/WGAppearanceChoices.swift",
    ] + glob([
        "Tests/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
)
