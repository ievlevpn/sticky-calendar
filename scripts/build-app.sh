#!/bin/bash
# Builds build/StickyCalendar.app. Pass --install to also copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product StickyCalendar
BIN="$(swift build -c release --show-bin-path)/StickyCalendar"

APP=build/StickyCalendar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/StickyCalendar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/StickyCalendar.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "Installed to ~/Applications/StickyCalendar.app"
fi
echo "Built $APP"
