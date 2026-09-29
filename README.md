<p align="center"><img src="docs/images/icon.png" width="128" alt="Sticky Calendar icon"></p>

# Sticky Calendar

A tiny menu-bar app that shows the day's calendar as a floating, always-on-top timeline.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/desktop-dark.png">
  <img src="docs/images/desktop-light.png" alt="A Mac desktop with a code editor and a document open; Sticky Calendar floats in the top-right corner showing the day's events, the current time and a Markdown checklist">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/sticky-dark.png">
  <img src="docs/images/sticky-light.png" align="right" width="240" alt="Close-up of the sticky: timeline with events, the red now-line, and a note with checkboxes">
</picture>

Scroll through the day (48 pt per hour — a taller window shows more hours); the red
ruler marks the current time and the clock button jumps back to it.
Drag to create, move and resize events; double-click to edit; ⌫ to delete; ⌘Z to undo;
⌃S (or the pin button) toggles whether the sticky stays on top of other windows;
⌘O (or the calendar button) opens Calendar, optionally on the day you're viewing;
⌘, (or the gear button) opens Settings; ⌘= / ⌘- zoom the timeline and note, ⌘0 resets
(also in Settings → Zoom).
Events with a Zoom, Meet, Teams or Webex link get a camera button that joins the call.
⌘M (or double-clicking the header) collapses the sticky to just what's on now or next;
⌃⌥S shows or hides it from any app (Settings → Shortcuts).
The note button opens a note under the timeline for quick, disposable thoughts — one per
day by default, following the date arrows like a journal (Settings → Note):
Markdown renders as you type, Obsidian-style — only the line you're editing shows its
syntax, and task boxes tick with a click; LaTeX math (`$…$`, `$$…$$`) is typeset too.
Drag its bar to resize; **Clear** empties it (⌘Z brings it back).
Keyboard: ←/→ change day; ↑/↓ move between events (or scroll when none is selected);
Page Up/Down scroll; Return edits the selected event; Esc deselects.

<br clear="right">

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
