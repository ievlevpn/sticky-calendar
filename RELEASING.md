# Releasing Sticky Calendar

Releases are built by GitHub Actions when a version tag is pushed. The repository is
private for now: releases exist, but nobody else can download them, the app's update
check stays silent, and the Homebrew cask is not published. See "Going public" below.

## Cutting a release

    git tag v1.2.3
    git push origin v1.2.3

The `Release` workflow tests, builds a universal DMG signed with the self-signed
certificate, verifies it, and creates the GitHub release `v1.2.3` with
`StickyCalendar-1.2.3.dmg` attached. The build number is the commit count.

Tags must be `vX.Y.Z` (a release) or `vX.Y.Z-suffix`, e.g. `v1.3.0-beta.1` (published as a
GitHub pre-release: never "Latest", never offered by the app's update check, never pushed
to Homebrew). Any other tag fails the workflow before anything is built.

To build the same DMG locally: `./scripts/build-dmg.sh 1.2.3` (then
`./scripts/verify-dmg.sh build/StickyCalendar-1.2.3.dmg 1.2.3`).

## One-time setup: signing certificate

Every build is signed with one self-signed certificate, "Sticky Calendar Self-Signed", so
the app keeps its Calendar permission across updates. (There is no Apple Developer ID;
see "First launch" below.)

1. Create it and import it into your login keychain:

       ./scripts/create-signing-cert.sh ~/.sticky-calendar-signing

   The first build that uses it may ask to use the key — choose **Always Allow**.
2. Give it to GitHub Actions:

       gh secret set SIGNING_CERT_P12 < ~/.sticky-calendar-signing/signing-cert.p12.base64
       gh secret set SIGNING_CERT_PASSWORD < ~/.sticky-calendar-signing/signing-cert.password

3. Back up `~/.sticky-calendar-signing` somewhere private (e.g. a password manager).
   Losing it means the next release is signed differently and every user is asked for
   Calendar access again.
4. Releases are pinned to this exact certificate: `RELEASE_CERT_SHA1` in
   `scripts/lib/signing.sh` holds its SHA-1, and release builds and `verify-dmg.sh` refuse
   anything else, even a certificate with the same name. Only change it on purpose (the
   script prints the new value when it creates a certificate).

## Going public

1. Make `ievlevpn/sticky-calendar` public. From then on the app's daily update check
   finds new releases.
2. Create a public repo `ievlevpn/homebrew-tap` with an empty `Casks/` directory.
3. Create a fine-grained personal access token with **Contents: read and write** on
   `ievlevpn/homebrew-tap` only, and save it as the `TAP_TOKEN` secret of
   `ievlevpn/sticky-calendar`.
4. Publish the cask for the current release (later releases do it automatically):

       gh release download vX.Y.Z --pattern '*.dmg'
       ./scripts/update-cask.sh X.Y.Z "$(shasum -a 256 StickyCalendar-X.Y.Z.dmg | cut -d' ' -f1)" \
           ../homebrew-tap/Casks/sticky-calendar.rb

   then commit and push the tap.

## First launch (no Apple notarization)

The app is not notarized, so macOS blocks the first launch of a downloaded copy. Open
System Settings → Privacy & Security and click **Open Anyway** once. Updates installed
over it (DMG or `brew upgrade`) keep working and keep their Calendar access.
