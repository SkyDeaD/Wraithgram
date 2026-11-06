load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Feature module WGSecurity. Owner: W3-4 (from wave 2 on this BUILD belongs to the owner).
# May depend on everything below TelegramUI; never on TelegramUI or another WG<Feature> module
# (FOUNDATION_SPEC §1.1).
swift_library(
    name = "WGSecurity",
    module_name = "WGSecurity",
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
        # W3-4: chat lock, secret folder, account button, passcode extras, menu.
        "//submodules/AppBundle:AppBundle",
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/ContextUI:ContextUI",
        "//submodules/AvatarNode:AvatarNode",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/ItemListPeerItem:ItemListPeerItem",
        "//submodules/LocalizedPeerData:LocalizedPeerData",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/UIKitRuntimeUtils:UIKitRuntimeUtils",
        "//submodules/PasscodeCore:PasscodeCore",
        "//submodules/PasscodeUI:PasscodeUI",
        "//submodules/SettingsUI:SettingsUI",
        "//submodules/ChatListUI:ChatListUI",
        "//submodules/TelegramUI/Components/ChatListHeaderComponent:ChatListHeaderComponent",
        "//submodules/TelegramUI/Components/NavigationBarComponent:NavigationBarComponent",
        "//submodules/TelegramUI/Components/PeerInfo/AccountPeerContextItem:AccountPeerContextItem",
    ],
    visibility = [
        "//visibility:public",
    ],
)
