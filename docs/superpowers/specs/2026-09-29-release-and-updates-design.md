# Sticky Calendar — Release & Updates Design

Date: 2026-09-29
Status: approved in conversation, pending written-spec review

## Purpose

Ship Sticky Calendar from a GitHub repository as an installable DMG and a Homebrew cask,
with the app able to tell users when a newer version exists. The repository starts
**private**; nothing is published until the owner makes it public. Everything must be
ready so that going public is a short checklist, not new engineering.

### Success criteria

- Pushing a tag `vX.Y.Z` produces a GitHub Release containing a signed, universal
  `StickyCalendar-X.Y.Z.dmg`, with no manual steps.
- Installing an update (DMG or `brew upgrade`) keeps Calendar access — no re-prompt.
- Once public: the app notices a newer release within a day and points the user to the
  right way to update; `brew install --cask ievlevpn/tap/sticky-calendar` works.
- While private: the update check stays silent; CI still produces releases.
- App bundle stays small (~2.2 MB universal); no third-party dependencies.

### Decisions (from the user)

| Topic | Decision |
|---|---|
| Repository | `ievlevpn/sticky-calendar`, private for now |
| Updates before going public | Not required to work; the app side must be ready |
| Apple Developer ID | Not planned — use a stable self-signed certificate |
| Update mechanism | Homebrew tap + DMG + a lightweight in-app "update available" notice (no Sparkle) |

### Out of scope

- Sparkle or any in-app download/installation of updates.
- Notarization and Developer ID signing.
- Submission to the official `homebrew/cask` (requires notarized apps).
- Publishing the tap before the repo is public.

## App side

### Update check (`StickyCalendarCore`)

- `UpdateChecker` fetches `https://api.github.com/repos/ievlevpn/sticky-calendar/releases/latest`
  (unauthenticated) through an injectable `ReleaseFetcher` protocol, and reads
  `tag_name` and `html_url`.
- Versions are compared as semantic versions (`MAJOR.MINOR.PATCH`, leading `v` ignored;
  missing parts count as 0; pre-release suffixes are never "newer" than a release).
- Result states: `.upToDate`, `.available(version, pageURL)`, `.unknown` (never checked,
  network error, HTTP 404/403, malformed response). `.unknown` is never shown as an error.
- Automatic checks: at launch and then every 24 h, only if enabled and if the last
  successful or attempted check is ≥ 24 h old (timestamp persisted in UserDefaults).
- Manual check ("Check for Updates…") always runs, ignoring the 24 h limit.
- A development build (version `0.0.0-dev`) never reports an update.

### Install-method detection

- The app is considered Homebrew-installed if `Caskroom/sticky-calendar` exists under
  `/opt/homebrew` or `/usr/local`.

### UI

- Menu-bar menu: **Check for Updates…** always; plus **Update Available: vX.Y.Z…** when one
  is known. For Homebrew installs that item copies `brew upgrade --cask sticky-calendar`
  to the clipboard and shows a short confirmation; otherwise it opens the release page.
- Settings: "Version X.Y.Z (build N)"; update status line; toggle
  **Check for updates automatically** (default on).
- A manual check shows its outcome in the Settings status line and, when invoked from the
  menu, in a small alert ("You're up to date" / "Version X is available" / "Couldn't check
  for updates").

### Versioning

- `CFBundleShortVersionString` = tag without `v`; `CFBundleVersion` = `git rev-list --count HEAD`.
- Local builds without a version argument use `0.0.0-dev` and the commit count.

### Signing

- A self-signed code-signing certificate named **"Sticky Calendar Self-Signed"** (10-year
  validity) is created once, kept in the login keychain, and exported as a password-protected
  `.p12` for CI.
- Every build (local and CI) signs with it, so the app's designated requirement is stable
  and TCC Calendar permission survives updates.
- Without Developer ID, the first launch of a downloaded copy requires System Settings →
  Privacy & Security → **Open Anyway** (documented).

## Release pipeline

### Build scripts

- `scripts/build-app.sh [--version X.Y.Z] [--universal] [--sign "<identity>"] [--install]` —
  existing script extended; defaults preserve today's local behaviour (ad-hoc signing if the
  identity is absent, so a fresh clone still builds).
- `scripts/build-dmg.sh X.Y.Z` — builds the app (universal, signed) and creates
  `build/StickyCalendar-X.Y.Z.dmg` (compressed UDZO; app + `/Applications` symlink; volume
  name "Sticky Calendar"); signs the DMG.

### GitHub Actions (`.github/workflows/release.yml`)

- Trigger: push of a tag matching `v*`.
- Runner: `macos-latest`. Steps: checkout (full history for the build number) → run tests →
  import the certificate from secrets into a temporary keychain → `build-dmg.sh` →
  `gh release create` with the DMG and generated notes → if `TAP_TOKEN` is set, update the
  cask in `ievlevpn/homebrew-tap`.
- Secrets: `SIGNING_CERT_P12` (base64), `SIGNING_CERT_PASSWORD`; later `TAP_TOKEN`.
- A second workflow (`ci.yml`) runs the tests on pushes and pull requests.

### Homebrew (prepared, inactive)

- `packaging/homebrew/sticky-calendar.rb.template` — cask with `version`, `sha256`, `url`
  pointing at the release DMG, `app "StickyCalendar.app"`, `depends_on macos: ">= :sonoma"`,
  `zap` for preferences, and a caveat about "Open Anyway".
- `scripts/update-cask.sh VERSION SHA256` renders the template into a tap checkout.

### Documentation

- `RELEASING.md`: cutting a release; one-time certificate setup; the go-public checklist
  (make repo public → create `ievlevpn/homebrew-tap` → add `TAP_TOKEN` → re-run the last
  release's cask step); the "Open Anyway" note.
- README gains Install (DMG / Homebrew) and Updating sections.

## Repository

- Create `ievlevpn/sticky-calendar` as a **private** GitHub repo, push `master` and the
  current work, and configure the signing secrets. No release is published publicly.

## Testing

- Unit tests: version parsing/comparison (incl. `v` prefix, missing parts, pre-release,
  dev builds), release JSON decoding, 404/403/network/malformed → `.unknown`, the 24 h
  throttle and manual override, auto-check toggle persisted.
- Script checks: `build-app.sh --version 1.2.3` produces the right `Info.plist` values;
  `codesign -dv` shows the self-signed authority; `build-dmg.sh` mounts and contains the app
  and the Applications link; `lipo -archs` shows `x86_64 arm64`.
- End-to-end: push a test tag (`v0.1.0`) to the private repo and confirm the release and
  DMG appear; install from the DMG and confirm Calendar access is kept after installing a
  second build.
