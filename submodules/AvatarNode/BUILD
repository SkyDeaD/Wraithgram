load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "AvatarNode",
    module_name = "AvatarNode",
    srcs = glob([
        "Sources/**/*.swift",
    ]) + [
        # WRAITH: avatar shape point (square avatars, W2-5)
        "//Wraithgram/Features/Interface:AvatarNodePointSources",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Postbox",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/AnimationUI:AnimationUI",
        "//submodules/AppBundle:AppBundle",
        "//submodules/AccountContext:AccountContext",
        "//submodules/Emoji:Emoji",
        "//submodules/TinyThumbnail:TinyThumbnail",
        "//submodules/FastBlur:FastBlur",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/Stories/AvatarStoryIndicatorComponent",
        "//submodules/DirectMediaImageCache",
        # WRAITH: hook points
        "//Wraithgram/WGCore:WGCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
