#!/bin/bash
# Builds build/StickyCalendar-X.Y.Z.dmg: universal, signed, with an Applications link.
# Set REQUIRE_SIGNING=1 (CI does) to fail rather than ship an ad-hoc-signed build.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/signing.sh

VERSION="${1:?usage: build-dmg.sh X.Y.Z}"
IDENTITY="${SIGN_IDENTITY:-$DEFAULT_SIGNING_IDENTITY}"
REQUIRE=()
[[ "${REQUIRE_SIGNING:-0}" == 1 ]] && REQUIRE=(--require-sign)

./scripts/build-app.sh --version "$VERSION" --universal --sign "$IDENTITY" ${REQUIRE[@]+"${REQUIRE[@]}"}

DMG="build/StickyCalendar-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R build/StickyCalendar.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Sticky Calendar" -srcfolder "$STAGE" -format UDZO -fs HFS+ -ov "$DMG" >/dev/null

HASH="$(signing_hash "$IDENTITY")"
[[ -n "$HASH" ]] && codesign --force --timestamp=none --sign "$HASH" "$DMG"
shasum -a 256 "$DMG" | awk '{ print $1 }' > "$DMG.sha256"
echo "Built $DMG ($(du -h "$DMG" | cut -f1), sha256 $(cat "$DMG.sha256"))"
