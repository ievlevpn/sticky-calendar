# Sticky Calendar

A tiny menu-bar app that shows the day's calendar as a floating, always-on-top timeline.
Scroll through the day (48 pt per hour — a taller window shows more hours); the red
ruler marks the current time and the clock button jumps back to it.
Drag to create, move and resize events; double-click to edit; ⌫ to delete; ⌘Z to undo;
⌃S (or the pin button) toggles whether the sticky stays on top of other windows;
⌘O (or the calendar button) opens Calendar, optionally on the day you're viewing.

## Install

- **DMG:** download `StickyCalendar-X.Y.Z.dmg` from
  [Releases](https://github.com/ievlevpn/sticky-calendar/releases), open it and drag the app
  to Applications.
- **Homebrew:** `brew install --cask ievlevpn/tap/sticky-calendar`

The app isn't notarized by Apple: the first time, open System Settings → Privacy & Security
and click **Open Anyway**.

## Updating

The app checks for new releases once a day (Settings → Updates) and shows
**Update Available** in its menu. It never installs anything by itself: Homebrew users run
`brew upgrade --cask sticky-calendar` (the menu item copies the command), others download
the new DMG. See [RELEASING.md](RELEASING.md) for how releases are made.

## Build

Requires macOS 14+ and the Swift toolchain (Command Line Tools are enough).

    ./scripts/test.sh               # unit tests
    ./scripts/build-app.sh          # → build/StickyCalendar.app
    ./scripts/build-app.sh --install  # also copies to ~/Applications
    ./scripts/build-dmg.sh 1.2.3    # release DMG (universal, signed)

Always launch the bundle (`open build/StickyCalendar.app`), not the bare binary —
Calendar permission belongs to the signed app.

## Notes

- Builds are signed with the self-signed "Sticky Calendar Self-Signed" certificate when it's
  in your keychain (see RELEASING.md); otherwise ad-hoc, and macOS asks for Calendar access
  again after each rebuild.
- Invitations, attendees, repeat rules and alerts are edited in Calendar.app
  (popover → Open in Calendar).
