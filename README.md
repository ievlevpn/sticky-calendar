# Sticky Calendar

A tiny menu-bar app that shows the day's calendar as a floating, always-on-top timeline.
Scroll through the day (48 pt per hour — a taller window shows more hours); the red
ruler marks the current time and the clock button jumps back to it.
Drag to create, move and resize events; double-click to edit; ⌫ to delete; ⌘Z to undo;
⌃S (or the pin button) toggles whether the sticky stays on top of other windows.

## Build

Requires macOS 14+ and the Swift toolchain (Command Line Tools are enough).

    ./scripts/test.sh               # unit tests
    ./scripts/build-app.sh          # → build/StickyCalendar.app
    ./scripts/build-app.sh --install  # also copies to ~/Applications

Always launch the bundle (`open build/StickyCalendar.app`), not the bare binary —
Calendar permission belongs to the signed app.

## Notes

- The app is ad-hoc signed, so macOS may ask for Calendar access again after a rebuild.
- Invitations, attendees, repeat rules and alerts are edited in Calendar.app
  (popover → Open in Calendar).
