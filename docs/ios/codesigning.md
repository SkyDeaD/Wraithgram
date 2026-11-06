# Signing with your own profiles

A device build needs provisioning profiles of your own. A simulator build doesn't: without them it uses
Telegram's test profiles from `build-system/fake-codesigning`, extended past their October 30, 2026 expiration
by `build-system/WGSimProfiles.py`. This page shows how to make your own profiles.

You need an Apple Developer account. A free account can't create the App Groups and push notification
entitlements that the app uses.

## Choose the identifiers

1. Pick a bundle ID for the app, for example `org.example.wraithgram`.
2. Find your Team ID under **Membership details** at [developer.apple.com/account](https://developer.apple.com/account).
3. Put both into `build-system/wraithgram-configuration.json`:

   ```json
   {
     "bundle_id": "org.example.wraithgram",
     "team_id": "ABCDE12345"
   }
   ```

   Leave the other fields of the file as they are.

## Create the App IDs

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list), create
one App ID for the app and one for each extension. `BUNDLE` is your bundle ID.

| App ID | Profile file name used by the build |
|--------|-------------------------------------|
| `BUNDLE` | `Telegram` |
| `BUNDLE.Share` | `Share` |
| `BUNDLE.NotificationService` | `NotificationService` |
| `BUNDLE.NotificationContent` | `NotificationContent` |
| `BUNDLE.Widget` | `Widget` |
| `BUNDLE.SiriIntents` | `Intents` |
| `BUNDLE.BroadcastUpload` | `BroadcastUpload` |

On the app's App ID, enable **Push Notifications**: the build stops with
`Could not find a valid aps-environment entitlement` if the app's profile has no push entitlement. Enable
**App Groups** on every App ID and add them all to one group, `group.BUNDLE`.

## Create the profiles

1. For each App ID, create an **iOS App Development** profile. A development profile is enough for the simulator
   and for your own devices.
2. Download the profiles and put them into `build-system/wraithgram-codesigning/profiles/`. Any file names work:
   the build finds each profile by its App ID and copies it under the name from the table.
3. Build:

   ```sh
   build-system/WGBuild.sh
   ```

   The first line of the output shows `signing    : build-system/wraithgram-codesigning`.

The folder is in `.gitignore`. To keep the profiles elsewhere, point `WG_CODESIGN` at a folder that has a
`profiles/` subfolder.

For a device IPA, `build-system/WGBuildRelease.sh` also needs a distribution certificate (`.p12` with an empty
password) in `build-system/wraithgram-codesigning/certs/` and distribution profiles for the same App IDs.

These steps follow what the build scripts check (`build-system/Make/BuildConfiguration.py`). They have not been
tried with a real account yet; if the build reports a missing or mismatched entitlement, enable that capability
on the App ID and download the profile again.

## Sign with a purchased certificate

A purchased certificate usually comes as a `.p12` with a password and one ad-hoc `.mobileprovision` for your
device. Its profile covers a single App ID and names its own app groups. The build can use it, but the app is
built without its extensions: no share sheet, widgets, Siri, or notification extension.

1. Read the profile:

   ```sh
   security cms -D -i PROFILE.mobileprovision
   ```

   `PROFILE` is the profile's file name. Note `application-identifier` (`TEAM.BUNDLE`), the first entry of
   `com.apple.security.application-groups`, and that `aps-environment` is present.

2. Create `build-system/wraithgram-configuration-device.json` as a copy of
   `build-system/wraithgram-configuration.json` with `bundle_id` set to `BUNDLE`, `team_id` to `TEAM`, and a new
   field `app_group` set to the group from step 1. The file is in `.gitignore`.

3. Create `build-system/wraithgram-codesigning-device/` with:
   - `profiles/` containing the profile;
   - `certs/` containing the `.p12`, a file `password` with its password, and Apple's intermediate certificate
     [`AppleWWDRCAG3.cer`](https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer).

   The folder is in `.gitignore`. If the import fails with `MAC verification failed`, re-export the `.p12` with
   algorithms that macOS accepts:

   ```sh
   openssl pkcs12 -in OLD.p12 -passin pass:PASSWORD -legacy -nodes -out identity.pem
   openssl pkcs12 -export -in identity.pem -out NEW.p12 -passout pass:PASSWORD -legacy \
       -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
   rm identity.pem
   ```

4. Build:

   ```sh
   WG_CONFIG=build-system/wraithgram-configuration-device.json \
   WG_CODESIGN=build-system/wraithgram-codesigning-device \
   build-system/WGBuildRelease.sh 1 --disableExtensions
   ```

   The script imports the certificate into a temporary keychain for the duration of the build and restores the
   keychain list afterwards. The result is `build-output/ipa/Wraithgram.ipa`, signed for your device.

When the seller's certificate is revoked, the installed app stops launching until it is signed again.

### Re-sign on the device instead

Signing apps such as ESign or LCSign re-sign an IPA with your certificate on the iPhone, extensions included.
For them, build an IPA with its own bundle ID:

```sh
build-system/WGBuildResign.sh
```

The result is `build-output/ipa/Wraithgram-for-resign.ipa` with the bundle ID `org.wraithgram.app`
(`WG_RESIGN_BUNDLE_ID` changes it). It is signed with Telegram's test profiles retargeted to that ID; the
signing app replaces the signature. Never re-sign an IPA whose bundle ID is `ph.telegra.Telegraph`: the signing
app may keep it, and the IPA then installs over the official Telegram. `WGBuildRelease.sh` refuses that bundle
ID. At launch, the app and each extension open the app group the re-signed profile names
(the first group in `embedded.mobileprovision`) when `group.<bundle ID>` isn't available.
