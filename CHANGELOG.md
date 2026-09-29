# Changelog

What changed in each release of Sticky Calendar, newest first. Each section becomes that release's notes on GitHub (see RELEASING.md).

## Unreleased

### Added
- **Reminders from Todoist, TickTick or an Obsidian vault**, as well as Apple Reminders. The first time you open reminders, Sticky Calendar asks where they should come from; change it any time in Settings → Reminders.
  - **Todoist** and **TickTick** use a personal API token (kept in your keychain): projects become lists, and ticking, adding, renaming and deleting go straight to your account.
  - **Obsidian**: every `- [ ]` task in the vault's notes, with 📅 due dates from the Tasks plugin; each note is a list. Ticking writes `[x]` and `✅ date` like the Tasks plugin, and new reminders go to an inbox note you choose. Edits made in Obsidian show up straight away.
- **Open in …** (right-click a reminder) opens it in Todoist, TickTick, Obsidian or Reminders.

## 0.6.0 — 2026-09-29

### Added
- **Reminders**, in their own sticky or as a tab of the calendar sticky (Settings → Reminders). Switch between **Today** (overdue, then due today) and **whole lists**. Tick, add, rename and delete them, all undoable with ⌘Z; a date typed into a new reminder ("Call Sam tomorrow 10am") becomes its due date. The checklist button in the header, the menu-bar menu and ⌃⌥R (from any app) show or hide them. macOS asks for Reminders access the first time you open them.
- Join buttons for **8x8** and **self-hosted Jitsi** meetings (`meet.…` and `jitsi.…` addresses with a room).

### Changed
- In a narrow window, the header folds Open in Calendar, Compact and Settings into a "…" menu instead of crowding.

## 0.5.0 — 2026-09-29

### Added
- A **join button** on events with a Zoom, Google Meet, Teams, Webex, Whereby, FaceTime or similar link (in the event's URL, location or notes).
- **A note for each day**, following the date arrows like a journal. Your existing note becomes today's; Settings → Note switches back to a single note.
- **Compact mode** (⌘M, the header button, or double-clicking the header): just the header and what's on now or next, with a countdown and a join button.
- **⌃⌥S** shows or hides the sticky from any app (Settings → Shortcuts to change it).

### Changed
- The note's bar shortens its title in narrow windows instead of overlapping the grip.

## 0.4.0 — 2026-09-29

### Added
- **Zoom**: ⌘= / ⌘- / ⌘0, or Settings → Zoom (80–200%), scales the timeline and the note together.
- A **gear button** and **⌘,** open Settings from the sticky.

### Fixed
- The date in the header no longer wraps onto two lines in narrow windows.

## 0.3.0 — 2026-09-29

### Added
- **LaTeX math** in the note: `$…$` inline and `$$…$$` display formulas are typeset on lines you're not editing; TeX that doesn't parse is shown in red.

## 0.2.0 — 2026-09-29

### Added
- **A note** under the timeline for quick thoughts, with **live Markdown preview** like Obsidian: headings, bold, italic, code, links, lists, quotes, and checkboxes that tick with a click. Only the line you're editing shows its syntax.
- An **app icon**.

## 0.1.2 — 2026-09-29

### Added
- **Keyboard navigation**: ←/→ change the day, ↑/↓ move between events (or scroll), Page Up/Down scroll, Return edits the selected event, Esc deselects.

### Fixed
- The calendar button showed the wrong year when the system uses a non-Gregorian calendar.

## 0.1.1 — 2026-09-29

### Added
- A **calendar button** (and ⌘O) that opens Calendar, optionally on the day you're viewing.

## 0.1.0 — 2026-09-29

The first release.

- The day's calendar as a **floating, always-on-top timeline** in the corner of the screen; ⌃S or the pin button makes it an ordinary window.
- **Drag** to create, move and resize events; double-click to edit; ⌫ to delete; ⌘Z to undo.
- A red line marks the current time, with a button to jump back to it.
- A **menu-bar item**, and Settings for which calendars to show and the sticky's opacity.
- A daily check for new versions; install from the DMG or with Homebrew.
