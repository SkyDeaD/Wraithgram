load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TabBarComponent",
    module_name = "TabBarComponent",
    srcs = glob([
        "Sources/**/*.swift",
    ]) + [
        # WRAITH: tab bar style point (organizer, labels, height — W2-5)
        "//Wraithgram/Features/Interface:TabBarComponentPointSources",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Display",
        "//submodules/LottieSettings:LottieSettings",
        "//submodules/TelegramPresentationData",
        "//submodules/ComponentFlow",
        "//submodules/Components/ComponentDisplayAdapters",
        "//submodules/Components/MultilineTextComponent",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent",
        "//submodules/TelegramUI/Components/LottieComponent",
        "//submodules/Components/BundleIconComponent",
        "//submodules/TelegramUI/Components/TextBadgeComponent",
        "//submodules/UIKitRuntimeUtils",
        "//submodules/TelegramUI/Components/LiquidLens",
        "//submodules/AppBundle",
        "//submodules/SearchBarNode",
        "//submodules/TelegramUI/Components/TabSelectionRecognizer",
        "//submodules/TelegramUI/Components/TabBarLayout",
        # WRAITH: hook points
        "//Wraithgram/WGCore:WGCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
