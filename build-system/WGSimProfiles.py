#!/usr/bin/env python3
"""Copy a codesigning folder for a simulator build, extending expired provisioning profiles.

    python3 build-system/WGSimProfiles.py SOURCE DEST [BUNDLE_ID]

The simulator does not check signatures, but rules_apple refuses a profile whose ExpirationDate
is in the past. Telegram's fake profiles (build-system/fake-codesigning) expired on 2026-10-30.
This writes DEST/profiles with each profile's ExpirationDate moved 10 years ahead, re-wrapped as
CMS with a throwaway self-signed key (the content is all the build reads), and copies
SOURCE/certs as is. Used by WGBuild.sh only; device builds keep real profiles.

With BUNDLE_ID, every "ph.telegra.Telegraph" in the profiles' entitlements (application identifiers,
the app group, iCloud containers) becomes BUNDLE_ID. WGBuildResign.sh uses this for an IPA that is
re-signed on the device: it must not carry Telegram's bundle ID, or it installs over Telegram.
"""

import datetime
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile


def decode(path):
    return plistlib.loads(subprocess.run(
        ['openssl', 'smime', '-inform', 'der', '-verify', '-noverify', '-in', path],
        check=True, capture_output=True).stdout)


OFFICIAL_BUNDLE_ID = 'ph.telegra.Telegraph'


def retarget(value, bundle_id):
    if isinstance(value, str):
        return value.replace(OFFICIAL_BUNDLE_ID, bundle_id)
    if isinstance(value, list):
        return [retarget(item, bundle_id) for item in value]
    if isinstance(value, dict):
        return {key: retarget(item, bundle_id) for key, item in value.items()}
    return value


def main(source, dest, bundle_id=None):
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(os.path.join(dest, 'profiles'))
    if os.path.isdir(os.path.join(source, 'certs')):
        shutil.copytree(os.path.join(source, 'certs'), os.path.join(dest, 'certs'))

    later = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None, microsecond=0) \
        + datetime.timedelta(days=3650)
    with tempfile.TemporaryDirectory() as work:
        key = os.path.join(work, 'key.pem')
        cert = os.path.join(work, 'cert.pem')
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '3650',
                        '-subj', '/CN=Wraithgram simulator profiles', '-keyout', key, '-out', cert],
                       check=True, capture_output=True)
        profiles = os.path.join(source, 'profiles')
        for name in sorted(os.listdir(profiles)):
            if not name.endswith('.mobileprovision'):
                continue
            profile = decode(os.path.join(profiles, name))
            profile['ExpirationDate'] = later
            if bundle_id:
                profile['Entitlements'] = retarget(profile['Entitlements'], bundle_id)
            plist = os.path.join(work, name + '.plist')
            with open(plist, 'wb') as f:
                plistlib.dump(profile, f)
            subprocess.run(['openssl', 'cms', '-sign', '-nodetach', '-binary', '-outform', 'der',
                            '-in', plist, '-signer', cert, '-inkey', key,
                            '-out', os.path.join(dest, 'profiles', name)],
                           check=True, capture_output=True)


if __name__ == '__main__':
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) == 4 else None)
