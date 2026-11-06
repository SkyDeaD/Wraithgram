#!/bin/bash
# Build a Ghostgram IPA to re-sign on the device (ESign, LCSign, ...), extensions included.
#
#   build-system/GGBuildResign.sh [buildNumber] [extra Make.py args...]
#
# Signs with Telegram's test profiles, retargeted to the bundle ID below; the signing app replaces the
# signature. The bundle ID must not be Telegram's, or the IPA installs over the official app. At
# launch the app opens the app group of the profile it was re-signed with (BuildConfig.appGroupName).
#
# Config: build-system/ghostgram-configuration.json with bundle_id GG_RESIGN_BUNDLE_ID
#         (default org.ghostgram.app), written to the gitignored ghostgram-configuration-resign.json.
# Output: build-output/ipa/Ghostgram-for-resign.ipa

set -uo pipefail
cd "$(dirname "$0")/.."

BUILD_NUMBER="${1:-1}"
[ $# -gt 0 ] && shift
BUNDLE_ID="${GG_RESIGN_BUNDLE_ID:-org.ghostgram.app}"
SOURCE_CONFIG="build-system/ghostgram-configuration.json"
CONFIG="build-system/ghostgram-configuration-resign.json"
CODESIGN="build-system/GGResignCodesigning"
[ -f "$SOURCE_CONFIG" ] || { echo "ERROR: $SOURCE_CONFIG is missing." >&2; exit 1; }

python3 - "$SOURCE_CONFIG" "$CONFIG" "$BUNDLE_ID" <<'PY' || exit 1
import json, sys
config = json.load(open(sys.argv[1]))
config['bundle_id'] = sys.argv[3]
config['team_id'] = 'C67CF9S4VU'  # the test profiles' team
config.pop('app_group', None)
json.dump(config, open(sys.argv[2], 'w'), indent=2)
PY
chmod 600 "$CONFIG"
python3 build-system/GGSimProfiles.py build-system/fake-codesigning "$CODESIGN" "$BUNDLE_ID" || exit 1

GG_CONFIG="$CONFIG" GG_CODESIGN="$CODESIGN" build-system/GGBuildRelease.sh "$BUILD_NUMBER" "$@"
status=$?
if [ "$status" = "0" ]; then
    mv -f build-output/ipa/Ghostgram.ipa build-output/ipa/Ghostgram-for-resign.ipa
    echo "IPA for re-signing: build-output/ipa/Ghostgram-for-resign.ipa (bundle ID $BUNDLE_ID)"
fi
exit "$status"
