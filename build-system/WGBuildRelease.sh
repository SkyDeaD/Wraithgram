#!/bin/bash
# Build a distribution-signed Wraithgram IPA for TestFlight (release_arm64).
#
#   build-system/WGBuildRelease.sh <buildNumber> [extra Make.py args...]
#
# Config:  build-system/wraithgram-configuration.json (gitignored keys, see WGBuild.sh).
# Signing: build-system/wraithgram-codesigning/{certs,profiles} — App Store distribution
#          certificate (.p12, empty password, as Make.py imports it) and profiles for
#          org.wraithgram.app and its extensions. Gitignored; never commit it.
# Output:  build-output/ipa/Wraithgram.ipa
#
# The build number must be higher than any build already uploaded for this version.
#
# WG_CONFIG and WG_CODESIGN override the two paths above. A purchased ad-hoc certificate with one
# App ID (docs/ios/codesigning.md): its own config with "app_group", and --disableExtensions:
#
#   WG_CONFIG=build-system/wraithgram-configuration-device.json \
#   WG_CODESIGN=build-system/wraithgram-codesigning-device \
#   build-system/WGBuildRelease.sh 1 --disableExtensions
#
# codesign looks for the identity in the keychain search list. When $CODESIGN/certs holds a .p12, it
# is imported into a throwaway keychain in build-input/ for the duration of the build (password in
# $CODESIGN/certs/password, empty when missing; .cer files there, e.g. Apple's WWDR intermediate,
# are imported too), and the search list is restored afterwards.

set -uo pipefail
cd "$(dirname "$0")/.."

BUILD_NUMBER="${1:-}"
[ -n "$BUILD_NUMBER" ] || { echo "usage: $0 <buildNumber> [extra Make.py args...]" >&2; exit 2; }
shift

CONFIG="${WG_CONFIG:-build-system/wraithgram-configuration.json}"
CODESIGN="${WG_CODESIGN:-build-system/wraithgram-codesigning}"
OUTPUT_DIR="build-output/ipa"
[ -f "$CONFIG" ] || { echo "ERROR: $CONFIG is missing." >&2; exit 1; }
[ -d "$CODESIGN/certs" ] && [ -d "$CODESIGN/profiles" ] || { echo "ERROR: $CODESIGN/{certs,profiles} is missing." >&2; exit 1; }
# An IPA with Telegram's bundle ID installs over the official Telegram (also after re-signing on the device).
if [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["bundle_id"])' "$CONFIG")" = "ph.telegra.Telegraph" ]; then
    echo "ERROR: bundle_id in $CONFIG is Telegram's own (ph.telegra.Telegraph); a device IPA with it replaces Telegram." >&2
    exit 1
fi

LOG="${WG_BUILD_LOG:-/tmp/wg-build-release.log}"
echo "config     : $CONFIG"
echo "signing    : $CODESIGN"
echo "build      : $BUILD_NUMBER (release_arm64)"
echo "log        : $LOG"
echo

build-system/WGXcodeConfig.sh || exit 1
# Patches inside submodules (rules_apple, tgcalls) — same as WGBuild.sh.
WG_PATCHES_ONLY=1 build-system/WGBuild.sh || exit 1

KEYCHAIN=""
if ls "$CODESIGN"/certs/*.p12 >/dev/null 2>&1; then
    KEYCHAIN="$(pwd)/build-input/wg-signing.keychain-db"
    KEYCHAIN_PASSWORD="wraithgram"
    P12_PASSWORD="$(cat "$CODESIGN/certs/password" 2>/dev/null || true)"
    OLD_KEYCHAINS=()
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"; line="${line//\"/}"
        [ -n "$line" ] && OLD_KEYCHAINS+=("$line")
    done < <(security list-keychains -d user)
    restore_keychains() {
        security list-keychains -d user -s "${OLD_KEYCHAINS[@]}"
        security delete-keychain "$KEYCHAIN" 2>/dev/null
    }
    trap restore_keychains EXIT
    mkdir -p build-input
    security delete-keychain "$KEYCHAIN" 2>/dev/null
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" || exit 1
    security set-keychain-settings "$KEYCHAIN"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" || exit 1
    for cer in "$CODESIGN"/certs/*.cer; do
        [ -f "$cer" ] && security import "$cer" -k "$KEYCHAIN" >/dev/null
    done
    for p12 in "$CODESIGN"/certs/*.p12; do
        security import "$p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null \
            || { echo "ERROR: could not import $p12 (wrong password, or re-export it with -legacy)." >&2; exit 1; }
    done
    security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1
    security list-keychains -d user -s "$KEYCHAIN" "${OLD_KEYCHAINS[@]}"
    echo "keychain   : $KEYCHAIN (until the build ends)"
fi

mkdir -p "$OUTPUT_DIR"
python3 build-system/Make/Make.py --overrideXcodeVersion \
    --cacheDir ~/telegram-bazel-cache \
    build \
    --configurationPath "$CONFIG" \
    --codesigningInformationPath "$CODESIGN" \
    --buildNumber="$BUILD_NUMBER" --configuration=release_arm64 \
    --outputBuildArtifactsPath "$OUTPUT_DIR" \
    "$@" 2>&1 | tee "$LOG"

status=${PIPESTATUS[0]}
echo
if [ "$status" = "0" ] && [ -f "$OUTPUT_DIR/Telegram.ipa" ]; then
    mv -f "$OUTPUT_DIR/Telegram.ipa" "$OUTPUT_DIR/Wraithgram.ipa"
    echo "BUILD OK: $OUTPUT_DIR/Wraithgram.ipa"
else
    echo "BUILD FAILED (exit $status) — errors:"
    grep -E "^ERROR:|error: " "$LOG" | head -20
    [ "$status" = "0" ] && status=1
fi
exit "$status"
