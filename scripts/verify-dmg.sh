#!/bin/bash
# Checks a release DMG: contents, version, architectures, and (with REQUIRE_SIGNING=1)
# that it is signed with the self-signed release certificate. Exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/signing.sh

DMG="${1:?usage: verify-dmg.sh DMG X.Y.Z}"
VERSION="${2:?usage: verify-dmg.sh DMG X.Y.Z}"
fail() { echo "FAIL: $*" >&2; exit 1; }

MOUNT="$(mktemp -d)"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" >/dev/null
trap 'hdiutil detach "$MOUNT" -quiet; rmdir "$MOUNT"' EXIT

APP="$MOUNT/StickyCalendar.app"
[[ -d "$APP" ]] || fail "StickyCalendar.app missing"
[[ "$(readlink "$MOUNT/Applications")" == /Applications ]] || fail "Applications link missing"
PLIST="$APP/Contents/Info.plist"
[[ "$(plutil -extract CFBundleShortVersionString raw "$PLIST")" == "$VERSION" ]] || fail "version is not $VERSION"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/StickyCalendar")"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || fail "not universal: $ARCHS"
codesign --verify --strict "$APP" || fail "app signature invalid"
if [[ "${REQUIRE_SIGNING:-0}" == 1 ]]; then
    # Capture first: with pipefail, `codesign | grep -q` fails whenever grep exits early.
    SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
    [[ "$SIGNATURE" == *"Authority=$DEFAULT_SIGNING_IDENTITY"* ]] \
        || fail "app not signed with $DEFAULT_SIGNING_IDENTITY"
fi
echo "OK: $DMG (version $VERSION, $ARCHS)"
