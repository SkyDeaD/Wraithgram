load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TelegramPresentationData",
    module_name = "TelegramPresentationData",
    srcs = glob([
        "Sources/**/*.swift",
    ]) + [
        # WRAITH: PresentationData transformer chain (WGThemeHooks)
        "//Wraithgram/WGHooks:TelegramPresentationDataHookSources",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Postbox:Postbox",
        "//submodules/Display:Display",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/MediaResources:MediaResources",
        "//submodules/AppBundle:AppBundle",
        "//submodules/StringPluralization:StringPluralization",
        "//submodules/Sunrise:Sunrise",
        "//submodules/TinyThumbnail:TinyThumbnail",
        "//submodules/FastBlur:FastBlur",
        "//Telegram:PresentationStrings",
        # WRAITH: hook points
        "//Wraithgram/WGCore:WGCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
