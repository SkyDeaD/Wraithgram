load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Aggregator of the feature modules: only `register()` calls. TelegramUI depends on it.
# Owner: W1-2; the twelve feature modules are listed once here so nobody edits it in waves 2–4.
swift_library(
    name = "WGFeatures",
    module_name = "WGFeatures",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Wraithgram/WGSettingsUI:WGSettingsUI",
        "//Wraithgram/Features/Shared:WGFeaturesShared",
        "//Wraithgram/Features/GhostMode:WGGhostMode",
        "//Wraithgram/Features/AntiDelete:WGAntiDelete",
        "//Wraithgram/Features/Messages:WGMessages",
        "//Wraithgram/Features/Appearance:WGAppearance",
        "//Wraithgram/Features/Interface:WGInterface",
        "//Wraithgram/Features/Voice:WGVoice",
        "//Wraithgram/Features/CameraMasks:WGCameraMasks",
        "//Wraithgram/Features/CallsMedia:WGCallsMedia",
        "//Wraithgram/Features/Security:WGSecurity",
        "//Wraithgram/Features/NetworkSpoof:WGNetworkSpoof",
        "//Wraithgram/Features/Vless:WGVless",
        "//Wraithgram/Features/ProfileExport:WGProfileExport",
        # W5-SG: Swiftgram-parity features
        "//Wraithgram/Features/Extras:WGExtras",
        # W7-RD2: «Дата регистрации»
        "//Wraithgram/Features/RegDate:WGRegDate",
    ],
    visibility = [
        "//visibility:public",
    ],
)
