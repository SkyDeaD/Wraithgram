load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ImageCompression",
    module_name = "ImageCompression",
    srcs = glob([
        "Sources/**/*.swift",
    ]) + [
        # WRAITH: outgoing photo size / quality / pixels (WGOutgoingImageHooks)
        "//Wraithgram/WGHooks:ImageCompressionHookSources",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/MozjpegBinding:MozjpegBinding",
        # WRAITH: hook points
        "//Wraithgram/WGCore:WGCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
