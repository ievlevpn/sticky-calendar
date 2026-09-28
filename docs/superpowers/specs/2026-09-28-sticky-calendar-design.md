# Sticky Calendar — Design

Date: 2026-09-28
Status: approved in conversation, pending written-spec review

## Purpose

A very lightweight, modern-looking macOS utility that shows **today's calendar as a
floating sticky window**, so the user can *see how the day's time moves along their
planned events*. Events are editable directly on the timeline; anything beyond simple
edits is handed off to Calendar.app.

### Success criteria

- A glance at the sticky shows the whole working day, planned events, and where "now" is.
- Common edits (create, move, resize, rename, delete, change calendar/location/notes)
  happen in the sticky without opening Calendar.app.
- Changes made elsewhere (Calendar.app, other devices) appear in the sticky within ~1 s.
- The app stays small: ~1–2 MB bundle, ~30 MB RAM, no Dock icon.

### Decisions (from the user)

| Topic | Decision |
|---|---|
| What the window shows | Our own rendering of EventKit data (not Calendar.app's window, not a web view) |
| Editing | Direct manipulation on timeline + quick popover; "Open in Calendar" for the rest |
| Time range | Fixed configurable range (default 08:00–20:00) scaled to fit window, no scrolling |
| App presence | Menu-bar app, no Dock icon, no global hotkey |
| Day navigation (‹ ›, Today) | Keep |
| Undo (⌘Z) | Keep |

### Out of scope

- Inviting attendees, responding to invitations (EventKit exposes attendees read-only).
- Editing recurrence rules, alarms, all-day flag, travel time, URL — use "Open in Calendar".
- Week/month views, reminders, global hotkey, multiple sticky windows.

## Architecture

Native Swift: SwiftUI for content, AppKit where SwiftUI lacks control (floating panel,
status item), EventKit for data. Built with SwiftPM (no Xcode project); a script
assembles and ad-hoc signs the `.app`. Deployment target: macOS 14.

```
StickyCalendar.app  (LSUIElement — menu-bar only)
├─ AppDelegate            – bootstraps, requests Calendar access, owns components
├─ StatusItemController   – menu-bar icon: Show/Hide · Settings… · Quit
├─ StickyPanel            – NSPanel: floating level, joins all Spaces + full-screen
│                           auxiliary, borderless, rounded translucent material,
│                           frame autosaved
├─ CalendarStore          – @Observable; single owner of EKEventStore access via the
│                           EventSource protocol; loads a day's events, create/update/
│                           delete, reloads on .EKEventStoreChanged; undo registration
├─ TimelineLayout         – pure functions: time↔y mapping, snapping, overlap columns,
│                           out-of-range counts (unit-tested)
├─ TimelineView (SwiftUI) – hour grid, event blocks, now-line, past-time wash,
│                           "+N earlier/later" pills, gestures
├─ EventEditPopover       – title, start/end, calendar, location, notes;
│                           Delete · Open in Calendar
└─ SettingsView (SwiftUI) – hour range, visible calendars, opacity, launch at login
```

### Data flow

EventKit → `CalendarStore` (observable state: `day`, `events`, `allDayEvents`, `calendars`,
`authorization`, `lastError`) → views. Edits: view → store → EventKit save; the resulting
`EKEventStoreChanged` notification triggers a reload, which is the source of truth.

### Time

- A 60 s timer (aligned to the minute) advances the now-line.
- `NSCalendarDayChanged` and `NSWorkspace.didWakeNotification` re-evaluate "today": if the
  user was viewing today, the view rolls over to the new today.

### Settings (UserDefaults)

- `startHour` (default 8), `endHour` (default 20), `endHour > startHour`.
- `hiddenCalendarIDs` (default empty = all visible).
- `opacity` (default 0.92, range 0.5–1.0).
- Launch at login via `SMAppService.mainApp` (state read from the service, not stored).
- Panel frame via `NSWindow` frame autosave name.

## Interaction & Layout

### Window

- Default ~280 × 520 pt, resizable (min ~220 × 300). Hour scale stretches with height.
- Header: date ("Mon 28 Sep"), ‹ › day navigation, "Today" button (visible when not on
  today). Header is the drag area for moving the window.
- Background: `NSVisualEffectView` material with the configured opacity; follows
  light/dark mode.

### Timeline

- Hour labels each hour, faint half-hour gridlines.
- Past time (on today only) under a subtle grey wash; red now-line with a dot.
- Event blocks tinted by calendar colour; show title + time (+ location if height allows).
  Events that have ended are rendered at reduced opacity.
- Overlapping events laid out side by side in columns (Calendar.app-style: group
  transitively overlapping events into clusters, assign each event the first free column,
  width = cluster width / column count).
- All-day events: compact chips in a strip under the header.
- Events partly outside the range are clipped to it; events entirely outside produce
  "+N earlier" / "+N later" pills. Clicking a pill temporarily expands the range to
  include those events (until the day changes or the user navigates).
- Multi-day events that cover part of the viewed day are clipped to that day.

### Editing

| Gesture | Result |
|---|---|
| Drag on empty space | Create event in default calendar (15-min snap, min 15 min); opens popover with title focused |
| Drag event body | Move, 15-min snap, duration preserved |
| Drag event top/bottom edge (6 pt hit zone) | Resize start/end, 15-min snap, min 15 min |
| Click event | Select |
| Double-click event | Open popover |
| ⌫ on selected event | Delete after confirmation |
| ⌘Z / ⇧⌘Z | Undo / redo last move, resize, create, delete, popover edit |

- Recurring events: move/resize/delete prompts "This event only / This and future events"
  (`EKSpan.thisEvent` / `.futureEvents`).
- Read-only calendars (`!allowsContentModifications`): no drag handles, popover view-only.
- Popover commits on close; Esc cancels. Empty title on a newly created event → event is
  discarded.
- Open in Calendar: `ical://ekevent/<calendarItemExternalIdentifier>?method=show&options=more`;
  if the URL fails to open, fall back to activating Calendar.app on the viewed date.

### Menu bar

Status item with an SF Symbol calendar icon. Menu: Show/Hide Sticky, Settings…, Quit.

## Error Handling

- First launch: `requestFullAccessToEvents()`.
- Denied/restricted: sticky shows an explanation + "Open Privacy Settings" button
  (`x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`); status
  re-checked on app activation.
- Save/remove failure: optimistic change reverted (reload), transient banner with the
  error's localized description for ~4 s.
- No visible calendars: empty timeline with a hint pointing to Settings.

## Testing

- **Unit (XCTest, `swift test`)**: `TimelineLayout` — time↔y mapping and inverse,
  snapping, overlap column assignment, out-of-range counting, clipping of multi-day and
  midnight-crossing events; `CalendarStore` against a fake `EventSource` — load for a
  day, filtering hidden calendars, move/resize/delete + undo, error → `lastError`.
- **Manual smoke checklist**: create / move / resize / delete / undo; recurring edit
  prompt; edit in Calendar.app appears in sticky; Open in Calendar; panel stays on top
  across Spaces and over full-screen apps; permission-denied screen; day rollover.

## Build & Packaging

- SwiftPM package: executable target `StickyCalendar`, library target `StickyCalendarCore`
  (layout + store, testable), test target `StickyCalendarCoreTests`.
- `scripts/build-app.sh`: `swift build -c release`, assemble `StickyCalendar.app`
  (Info.plist with `LSUIElement=YES`, `NSCalendarsFullAccessUsageDescription`, bundle id
  `com.ievlevpn.StickyCalendar`, icon), ad-hoc `codesign`, optional copy to
  `~/Applications`.
- Known caveat: TCC ties Calendar permission to the code signature; ad-hoc re-signing
  may re-prompt after rebuilds. A stable self-signed certificate can be added later.

## Amendments (2026-09-29, during planning)

- Window is a titled `NSPanel` with a transparent, button-less title bar rather than a
  literally borderless one — native edge-resize, rounded corners and shadow; looks borderless.
- "Open in Calendar" fallback just opens Calendar.app (jumping to a date needs AppleScript
  + Automation permission).
- Deleting a recurring event is not undoable (EventKit cannot recreate a series); the
  confirmation dialog says so.
- No custom `.icns`; the menu-bar icon is the SF Symbol `calendar.day.timeline.left`.
- Tests use Swift Testing via `scripts/test.sh` (Command Line Tools lack XCTest).

## Amendments (2026-09-29, after first build — requested by the user)

- The timeline is no longer a fixed hour range scaled to fit: it covers the whole day at
  48 pt/hour in a vertical scroll view; resizing the window shows more or fewer hours.
  The "Visible hours" setting and the "+N earlier/later" pills are removed.
- Today opens scrolled so now sits a third of the way down; other days open at their
  first timed event, or 08:00. The view does not auto-follow the clock.
- The now-line is a full-width red ruler with the current time in a capsule over the hour
  labels. A header clock button (shown when now is off-screen or another day is viewed)
  jumps to today and scrolls to now; it replaces the "Today" button.
- ⌃S (and a header pin button) toggles stickiness: pinned = floating on every Space and
  over full-screen apps (default); unpinned = an ordinary window. Persisted.
- Dragging an event to the viewport edge does not auto-scroll.
