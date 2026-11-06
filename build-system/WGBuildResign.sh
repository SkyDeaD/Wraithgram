#!/bin/bash
# Build a Wraithgram IPA to re-sign on the device (ESign, LCSign, ...), extensions included.
#
#   build-system/WGBuildResign.sh [buildNumber] [extra Make.py args...]
#
# Signs with Telegram's test profiles, retargeted to the bundle ID below; the signing app replaces the
# signature. The bundle ID must not be Telegram's, or the IPA installs over the official app. At
# launch the app opens the app group of the profile it was re-signed with (BuildConfig.appGroupName).
#
# Config: build-system/wraithgram-configuration.json with bundle_id WG_RESIGN_BUNDLE_ID
#         (default org.wraithgram.app), written to the gitignored wraithgram-configuration-resign.json.
# Output: build-output/ipa/Wraithgram-for-resign.ipa

set -uo pipefail
cd "$(dirname "$0")/.."

BUILD_NUMBER="${1:-1}"
[ $# -gt 0 ] && shift
BUNDLE_ID="${WG_RESIGN_BUNDLE_ID:-org.wraithgram.app}"
SOURCE_CONFIG="build-system/wraithgram-configuration.json"
CONFIG="build-system/wraithgram-configuration-resign.json"
CODESIGN="build-system/WGResignCodesigning"
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
python3 build-system/WGSimProfiles.py build-system/fake-codesigning "$CODESIGN" "$BUNDLE_ID" || exit 1

WG_CONFIG="$CONFIG" WG_CODESIGN="$CODESIGN" build-system/WGBuildRelease.sh "$BUILD_NUMBER" "$@"
status=$?
if [ "$status" = "0" ]; then
    mv -f build-output/ipa/Wraithgram.ipa build-output/ipa/Wraithgram-for-resign.ipa
    echo "IPA for re-signing: build-output/ipa/Wraithgram-for-resign.ipa (bundle ID $BUNDLE_ID)"
fi
exit "$status"
