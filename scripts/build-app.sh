#!/bin/bash
# Builds build/StickyCalendar.app.
#   --version X.Y.Z   marketing version (default 0.0.0-dev: a local build that never
#                     reports updates)
#   --universal       Apple Silicon + Intel (default: this Mac's architecture only)
#   --sign NAME       code-signing identity (default "Sticky Calendar Self-Signed");
#                     without it, falls back to ad-hoc signing unless --require-sign
#   --require-sign    fail instead of falling back to ad-hoc signing (releases)
#   --install         also copy the app to ~/Applications
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/signing.sh

VERSION="0.0.0-dev"
UNIVERSAL=0
IDENTITY="$DEFAULT_SIGNING_IDENTITY"
REQUIRE_SIGN=0
INSTALL=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --universal) UNIVERSAL=1; shift ;;
        --sign) IDENTITY="$2"; shift 2 ;;
        --require-sign) REQUIRE_SIGN=1; shift ;;
        --install) INSTALL=1; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

HASH="$(signing_hash "$IDENTITY")"
if [[ -z "$HASH" && $REQUIRE_SIGN == 1 ]]; then
    echo "error: signing identity \"$IDENTITY\" not found in the keychain" >&2
    exit 1
fi

# Without Xcode, SwiftPM can't build several architectures at once: build each and merge.
binary_for() {
    swift build -c release --product StickyCalendar --triple "$1" >&2
    echo "$(swift build -c release --triple "$1" --show-bin-path)/StickyCalendar"
}

APP=build/StickyCalendar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ $UNIVERSAL == 1 ]]; then
    lipo -create "$(binary_for arm64-apple-macosx14.0)" "$(binary_for x86_64-apple-macosx14.0)" \
        -output "$APP/Contents/MacOS/StickyCalendar"
else
    swift build -c release --product StickyCalendar
    cp "$(swift build -c release --show-bin-path)/StickyCalendar" "$APP/Contents/MacOS/StickyCalendar"
fi

cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

if [[ -n "$HASH" ]]; then
    codesign --force --timestamp=none --sign "$HASH" "$APP"
else
    echo "warning: signing identity \"$IDENTITY\" not found; signing ad-hoc." >&2
    echo "         macOS will ask for Calendar access again after every rebuild." >&2
    codesign --force --sign - "$APP"
fi

if [[ $INSTALL == 1 ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/StickyCalendar.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "Installed to ~/Applications/StickyCalendar.app"
fi
echo "Built $APP (version $VERSION, build $BUILD_NUMBER)"
