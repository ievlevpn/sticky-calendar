# Changelog

What changed in each release of Sticky Calendar, newest first. Each section becomes that release's notes on GitHub (see RELEASING.md).

## 0.21.3 — 2026-09-30

### Fixed
- **Unticked reminders no longer vanish for a moment** (the real cause this time). A refresh still running from an earlier tick could finish after an untick and read the task as neither open nor completed, so it disappeared until the next refresh. Refreshes that began before a change are now ignored. Tested against Todoist, which turned out to show its changes immediately; 0.21.2's allowance for a slow Todoist is removed.

## 0.21.2 — 2026-09-30

### Fixed
- **Todoist: unticked tasks no longer vanish for a moment.** Todoist can take a few seconds to show its own changes, so a task you unticked (or ticked, or deleted) could disappear or flip back until the next refresh. For a few seconds after a change, Sticky Calendar now keeps what you did and checks again, and unticking straight after ticking reopens the task in Todoist as it should.
- **The ✓ button hides completed reminders, including ones you just ticked.** It used to do nothing visible when the only completed reminders were ones ticked in the app; now it's lit whenever completed reminders show, and clicking it hides them all.

## 0.21.1 — 2026-09-30

### Fixed
- **Redo works for reminders.** After ⌘Z on a reminder change (ticking, editing, postponing, adding or deleting), ⇧⌘Z did nothing, and a second ⌘Z redid the change instead of undoing further. Undo and redo now step back and forth as expected.

## 0.21.0 — 2026-09-30

### Added
- **Postpone a reminder**: its editor has +1 h, +3 h, Tomorrow and Next week buttons, and right-clicking a reminder has a Postpone menu that applies at once. Hours count from now (so an overdue reminder moves into the future); Tomorrow and Next week keep its time. ⌘Z undoes it.
- **Edit reminders in compact mode**: clicking the reminder opens its editor, and right-clicking it opens the same menu as the full list, so you no longer have to expand the sticky first.

### Fixed
- **Ticking a repeating reminder no longer makes it vanish.** Todoist, TickTick and Reminders move a repeating task to its next date instead of completing it, so it used to disappear from Today (or jump back unticked in Lists) a moment after you ticked it. It now stays ticked until the next day, showing when it's due next ("Next Tue 09:00").
- **Unticking a repeating reminder, or ⌘Z, puts its date back.** Before, it ticked the task again, skipping one more occurrence.
- **Todoist**: completed tasks are fetched with Todoist's default page size, and a repeating task's earlier completions no longer show up as a duplicate.
- **Changing the notes folder brings your latest notes along.** Moving from one folder to another used to copy Sticky Calendar's older copies of the notes, not what you'd written in the first folder; now the first folder's notes go to the new one.
- **Choosing a folder tells you about notes it kept.** When the folder already has a different note for a day, that file is left as it is, and Settings now says how many weren't copied.
- **Leaving a notes folder that can't be found asks first** (e.g. on a drive that isn't connected), since notes written there can't come along.

## 0.20.0 — 2026-09-30

### Added
- **Name your note files** (Settings → Note, with notes kept in a folder): choose how day notes are named using the date tokens Obsidian's daily notes use (`YYYY`, `MM`, `MMM`, `DD`, `ddd`, `dddd`, `[text]`), with presets and a live example. A `/` puts them in folders, e.g. `YYYY/MM/YYYY-MM-DD` → `2026/09/2026-09-30.md`. The single note's name can be changed too. Files already there keep their names.

## 0.19.0 — 2026-09-30

### Added
- **Cut, copy and paste events**: select one or several events and press ⌘C to copy or ⌘X to cut them, then ⌘V to paste copies onto the day you're viewing, at the same times. One ⌘Z undoes a cut or a paste. Copied events can also be pasted as text into other apps ("09:00–10:00 Standup"). Cutting a repeating event, or one with invitees, asks first, since it can't be undone.

## 0.18.1 — 2026-09-30

### Fixed
- **Opacity at 100 % is now solid.** The stickies stayed see-through even at full opacity. Above the default (92 %) they now turn gradually solid, and at 100 % nothing shows through; at the default and below they look as before.

## 0.18.0 — 2026-09-30

### Added
- **Open your reminders' app**: with reminders showing, the ••• menu (and ⌘O) opens where they come from: Reminders, the Todoist or TickTick app (or their web app), or your Obsidian vault.
- **Drag the note closed**: drag the note's bar all the way down to close it. Just before, the bar says "Release to close the note", the note dims and the trackpad clicks; drag back up to keep it. It reopens at its old height.

## 0.17.1 — 2026-09-30

### Fixed
- With keyboard navigation turned on in System Settings, pressing Tab could put a blue focus ring on one of the header's buttons (e.g. Settings) that seemed stuck there. The stickies' icon buttons no longer take keyboard focus; their shortcuts work as before.

## 0.17.0 — 2026-09-30

### Added
- **Notes as Markdown files** (Settings → Note → Keep notes): keep your notes as `.md` files in a folder you choose, e.g. an Obsidian vault. Each day's note is a file like `2026-09-30.md` (as Obsidian's daily notes); a single note is `Sticky Note.md`. Notes already in the app are copied there without overwriting any file, and edits made to the files elsewhere show up in the sticky.
- **Search in Settings**: type a few letters to find any setting from every tab ("fde" finds Fade when idle).

### Changed
- **Settings has tabs**: General, Calendars, Note, Reminders, Shortcuts and Updates. The Calendar button setting moved to Calendars.

## 0.16.0 — 2026-09-30

### Added
- **Fade when idle** (Settings → Appearance, off by default): the stickies fade when the pointer isn't over them and you're not typing in them, and come back as soon as you point at them. Choose how long they wait (5 seconds to 10 minutes) and how much they fade.
- **The note in the Reminders tab**: the note button works there too, opening the note under your reminders just as it does under the timeline.

## 0.15.0 — 2026-09-30

### Added
- **Compact reminders**: in the Reminders tab, compact mode (⌘M) shows one reminder at a time, with its due time and list. Scroll over it, or use the arrows that appear on hover, to flip through them; tick it off and the next slides in. The chip in the header shows Today or Lists and how many are left (click to switch). While an event is on, it sits above the reminder, filling with its colour as it goes.

### Changed
- **Compact mode stays on** when you switch between the calendar and the Reminders tab.
- The menu-bar menu only offers **Show/Hide Reminders** when reminders have their own sticky.

## 0.14.0 — 2026-09-30

### Added
- **Select several events**: ⌘- or ⇧-click adds an event to the selection (or takes it out). Drag any of them to move them all together, keeping their spacing; ⌫ deletes them after asking. One ⌘Z undoes either. With repeating events among them, you're asked once whether to change just these or future ones too.

### Fixed
- The **••• menu** opened when the pointer merely passed over the header near it, getting in the way of dragging the window and of the **Now** / **Today** chip. It now opens only from the ••• button.

## 0.13.0 — 2026-09-29

### Added
- **Hide from screen sharing and screenshots** (Settings → Appearance, off by default): asks macOS to leave Sticky Calendar's windows out of screen shares and screenshots. Some apps capture the screen in ways that may ignore this.

## 0.12.1 — 2026-09-29

### Changed
- In **compact mode**, the bar fills with the event's colour as it goes, from empty when it starts to full when it ends.

## 0.12.0 — 2026-09-29

### Changed
- **The date is the control**: click it for a month picker (today ringed in red), or scroll over it to step a day at a time; the day arrows are gone. A red **Today** chip takes you back from another day, and **Now** appears on today when the current time is scrolled out of view.
- The **reminders and note stickies** use the same unfurling ••• menu as the calendar (Refresh, Pin, Settings, Hide; for the note also Clear and Put back).

## 0.11.0 — 2026-09-29

### Changed
- **A tidier header**: it shows just the date and day arrows. Hover the ••• button and the rest (Reminders, Note, Pin, Refresh, Open in Calendar, Compact, Settings) unfurl in a capsule, with a label naming each one and its shortcut; click ••• to keep it open.

### Added
- An **About** window (top of the menu-bar menu, or About… in Settings) with the version, links to the website, what's new and reporting an issue, and credits.

## 0.10.1 — 2026-09-29

### Added
- **Links and Markdown in reminders' notes**: the editor's notes show formatting as you type (like the note), and links open when clicked. A reminder with a link in its notes gets a 🔗 button in the list that opens it directly.
- **Plain web addresses are links** now, in the note and in reminders, and **#tags** are highlighted.

### Fixed
- **Checking for updates** failed with "Couldn't check for updates" when GitHub's API was busy (it allows 60 anonymous requests an hour per network, shared by every app on it). The app now falls back to GitHub's website, retries a failed check within the hour instead of the next day, and says what happened.

## 0.10.0 — 2026-09-29

### Added
- **Edit reminders**: click one to change its title, date and time, importance (!, !!, !!!) and notes. Rows show the importance and the first line of the notes. Works with Apple Reminders, Todoist and TickTick; for Obsidian, importance uses the Tasks plugin's ⏫🔼🔽 and notes (the indented lines under a task) are shown read-only.
- A button on the note's bar moves the note into **its own sticky**, and one in that sticky puts it back under the timeline.
- **Fuzzy search** in reminders (the magnifying glass or ⌘F): finds reminders across all your lists from a few letters in order, in titles and notes.

## 0.9.0 — 2026-09-29

### Added
- The note can have **its own sticky** (Settings → Note → Show the note), with its own pin and position; per-day notes still follow the calendar's date.

### Changed
- **Settings open over full-screen apps**: the Settings window now floats like the stickies instead of switching to the desktop. ⌘W closes it.

## 0.8.0 — 2026-09-29

### Added
- A **refresh button** and **⌘R** for the calendar and for reminders; Apple Calendar and Reminders also sync with their servers first.

### Changed
- Reminders now open **as a tab** of the calendar sticky by default. The first time you open them, Sticky Calendar asks whether to keep them there or give them their own sticky.
- The Reminders/Calendar button is now the header's **last button** in both modes, so it stays in the same place when you switch.
- The sticky opens **wide enough** for the whole header; a window saved narrower by an earlier version is widened once (you can still make it narrower).

### Fixed
- The timeline's **00:00 and 24:00** labels were cut off when scrolled to the very top or bottom; both ends now have room to breathe.

## 0.7.0 — 2026-09-29

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
