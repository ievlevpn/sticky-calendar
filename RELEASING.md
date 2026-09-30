# Releasing Sticky Calendar

Releases are built by GitHub Actions when a version tag is pushed. The app's daily update
check reads the latest GitHub release; Homebrew installs from the `ievlevpn/homebrew-tap`
cask (see "Homebrew" below).

## Cutting a release

1. Add a section for the version to the top of `CHANGELOG.md`, written for users:

       ## 1.2.3 — 2026-10-01

       ### Added
       - …

   One line per bullet: GitHub shows line breaks in release notes as they are.
   `./scripts/release-notes.sh 1.2.3` prints what the release will say.
2. Commit, then tag and push:

       git tag v1.2.3
       git push origin v1.2.3

The `Release` workflow first takes the version's section of `CHANGELOG.md` as the release
notes (and stops if there isn't one), then tests, builds a universal DMG signed with the
self-signed certificate, verifies it, and creates the GitHub release `v1.2.3` with
`StickyCalendar-1.2.3.dmg` attached. The build number is the commit count.

Tags must be `vX.Y.Z` (a release) or `vX.Y.Z-suffix`, e.g. `v1.3.0-beta.1` (published as a
GitHub pre-release: never "Latest", never offered by the app's update check, never pushed
to Homebrew). A pre-release needs no changelog section: it uses its base version's, or a
one-line note. Any other tag fails the workflow before anything is built.

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

## Homebrew

The cask lives in the public repo `ievlevpn/homebrew-tap` (`Casks/sticky-calendar.rb`).
The release workflow updates it when the `TAP_TOKEN` secret exists:

1. Create a fine-grained personal access token with **Contents: read and write** on
   `ievlevpn/homebrew-tap` only, and save it as the `TAP_TOKEN` secret of
   `ievlevpn/sticky-calendar`.

Without the secret, publish the cask by hand after each release:

    gh release download vX.Y.Z --pattern '*.dmg'
    ./scripts/update-cask.sh X.Y.Z "$(shasum -a 256 StickyCalendar-X.Y.Z.dmg | cut -d' ' -f1)" \
        ../homebrew-tap/Casks/sticky-calendar.rb

then commit and push the tap.

## App icon

`Resources/AppIcon.icns` is drawn by `swift scripts/make-icon.swift`; edit the script and
rerun it to change the icon. README images live in `docs/images/`.

## First launch (no Apple notarization)

The app is not notarized, so macOS blocks the first launch of a downloaded copy. Open
System Settings → Privacy & Security and click **Open Anyway** once. Updates installed
over it (DMG or `brew upgrade`) keep working and keep their Calendar access.

## Microsoft To Do: app registration (once)

Microsoft To Do is offered only when `MicrosoftAuth.clientID`
(`Sources/StickyCalendarCore/MicrosoftAuth.swift`) is set.

1. Sign in to https://entra.microsoft.com with a Microsoft account (a free Azure account
   creates the directory if you have none).
2. App registrations → New registration: name "Sticky Calendar"; supported account types
   "Accounts in any organizational directory and personal Microsoft accounts".
3. Authentication → Add a platform → Mobile and desktop applications → custom redirect URI
   `http://localhost`. Under Advanced settings, set "Allow public client flows" to Yes.
4. API permissions: Microsoft Graph → Delegated → `Tasks.ReadWrite` (and `offline_access`).
   No admin consent needed.
5. Copy the Application (client) ID into `MicrosoftAuth.clientID`. It's not a secret.

The consent screen shows the app as unverified; personal accounts can still sign in, some
work or school directories need an admin to approve it.
