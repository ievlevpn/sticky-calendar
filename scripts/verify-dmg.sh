#!/bin/bash
# Checks a release DMG: contents, version, architectures, and (with REQUIRE_SIGNING=1)
# that it is signed with the pinned release certificate. Exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/signing.sh

DMG="${1:?usage: verify-dmg.sh DMG X.Y.Z}"
VERSION="${2:?usage: verify-dmg.sh DMG X.Y.Z}"
fail() { echo "FAIL: $*" >&2; exit 1; }

MOUNT="$(mktemp -d)"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" >/dev/null
# Best-effort cleanup: a busy volume must not turn a passed check into a failure.
cleanup() {
    hdiutil detach "$MOUNT" -quiet 2>/dev/null || hdiutil detach "$MOUNT" -force -quiet 2>/dev/null || true
    rmdir "$MOUNT" 2>/dev/null || true
}
trap cleanup EXIT

APP="$MOUNT/StickyCalendar.app"
[[ -d "$APP" ]] || fail "StickyCalendar.app missing"
[[ "$(readlink "$MOUNT/Applications")" == /Applications ]] || fail "Applications link missing"
PLIST="$APP/Contents/Info.plist"
[[ "$(plutil -extract CFBundleShortVersionString raw "$PLIST")" == "$VERSION" ]] || fail "version is not $VERSION"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/StickyCalendar")"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || fail "not universal: $ARCHS"
codesign --verify --strict "$APP" || fail "app signature invalid"
if [[ "${REQUIRE_SIGNING:-0}" == 1 ]]; then
    # The designated requirement names the exact certificate (by hash), which is what
    # users' Calendar permission is tied to — not just its name. Captured first: with
    # pipefail, `codesign | grep -q` fails whenever grep exits early.
    REQUIREMENT="$(codesign -d -r- "$APP" 2>&1)"
    PINNED="$(echo "$RELEASE_CERT_SHA1" | tr 'A-F' 'a-f')"
    [[ "$REQUIREMENT" == *"certificate leaf = H\"$PINNED\""* ]] \
        || fail "app not signed with the release certificate $RELEASE_CERT_SHA1"
fi
echo "OK: $DMG (version $VERSION, $ARCHS)"
