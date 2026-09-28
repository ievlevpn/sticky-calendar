# Sticky Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A menu-bar macOS app that shows the day's calendar events on an always-on-top, translucent timeline sticky with a moving "now" line, and lets the user create, move, resize, edit and delete events directly on it.

**Architecture:** A SwiftPM package with two targets. `StickyCalendarCore` (library) holds all logic: value models, pure timeline-layout functions, persisted settings, the `CalendarStore` that owns state and undo, and an `EventSource` protocol with the real `EventKitSource`. It is unit-tested against an in-memory fake. `StickyCalendar` (executable) is a thin AppKit shell (`NSPanel`, `NSStatusItem`) that hosts SwiftUI views. A shell script turns the release binary into a signed `.app`.

**Tech Stack:** Swift 6.3 toolchain in Swift 5 language mode (tools-version 5.10), SwiftUI + AppKit, EventKit, ServiceManagement, Observation, Swift Testing. Command Line Tools only (no Xcode).

**Spec:** `docs/superpowers/specs/2026-09-28-sticky-calendar-design.md`

## Global Constraints

- Deployment target macOS 14 (`platforms: [.macOS(.v14)]`); `// swift-tools-version:5.10`.
- No third-party dependencies.
- Bundle id `com.ievlevpn.StickyCalendar`; `LSUIElement` = true (no Dock icon); `NSCalendarsFullAccessUsageDescription` present.
- Defaults: visible hours 08:00–20:00; opacity 0.92, clamped to 0.5–1.0; window 280 × 520 pt, minimum 220 × 300 pt.
- Snapping 15 minutes; minimum event duration 15 minutes.
- Run tests only through `./scripts/test.sh` (it adds the Swift Testing framework paths the Command Line Tools need); plain `swift test` fails with "no such module 'Testing'".
- `swift build` must finish with **zero warnings**.
- Always launch the app as the bundle (`open build/StickyCalendar.app`), never the bare binary. Calendar permission (TCC) is granted per signed bundle, and a bare binary gets attributed to Terminal.
- Every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

- **DST days:** on a 23- or 25-hour day, the timeline must use real elapsed time, with no gap or overlap around the clock change. Pinned by `TimelineGeometryTests.dstDayUsesRealElapsedTime` (Task 2).
- **Events crossing midnight or spanning several days:** they must be clipped to the viewed day, count as "later" or "earlier" correctly, and expanding the range must stop at 00:00 and 24:00. Pinned by `partitionsEventsOutsideRange` and `expansionClipsEventsCrossingMidnight` (Task 2).
- **Event deleted elsewhere (another device, Calendar.app) while its editor is open:** saving must show "The event no longer exists." and drop it from the view, with no crash and no ghost event. Pinned by `editingAnEventDeletedElsewhereReportsNotFound` (Task 4).
- **No visible calendar accepts new events** (all writable calendars hidden, or only subscriptions): dragging to create must produce no draft and an explanatory banner. Pinned by `draftUsesDefaultCalendarOrFirstVisibleWritable` (Task 4).
- **Confirmation dialog clears its pending state before running the button's action:** "Delete" or "This event only" must still apply. Pinned by `confirmStillWorksIfDialogClearedPendingStateFirst` (Task 4).

## Deviations from the spec, decided while planning

- **Window style:** the panel is a *titled* `NSPanel` with its title bar made transparent and its buttons hidden, not a literally borderless one. This gives native edge-resizing, rounded corners and a shadow for free. It looks borderless.
- **"Open in Calendar" fallback:** it just opens Calendar.app. Jumping Calendar to a specific date needs AppleScript and an Automation permission, which isn't worth it for a fallback.
- **Undo after deleting a repeating event** is not offered. EventKit can't recreate a series. The delete dialog says so.
- **No custom `.icns`:** the menu bar uses the SF Symbol `calendar.day.timeline.left`. An `LSUIElement` app has no Dock icon to show one.

## File Structure

```
Package.swift
.gitignore                                    (modify: add build/)
Resources/Info.plist
scripts/test.sh                               runs swift test with Swift Testing paths
scripts/build-app.sh                          release build → build/StickyCalendar.app, ad-hoc signed
Sources/StickyCalendarCore/
  Models.swift             RGBA, CalendarInfo, EventItem, minimumEventDuration
  TimelineLayout.swift     HourRange, TimelineGeometry, RangePartition, Snap, DragKind, EventDrag, ColumnSlot, OverlapLayout
  AppSettings.swift        @Observable persisted preferences
  EventSource.swift        CalendarAccess, EditSpan, EventSourceError, EventSource protocol
  CalendarStore.swift      @Observable state owner: loading, navigation, drafts, edits, undo
  EventKitSource.swift     EventSource backed by EKEventStore
Sources/StickyCalendar/
  StickyCalendarApp.swift  @main entry point
  AppDelegate.swift        wires components, main menu, clock observers, settings window
  StatusItemController.swift  menu-bar icon + menu
  StickyPanel.swift        floating NSPanel, key handling (⌫, ⌘Z, ⇧⌘Z), frame autosave
  Views/Support.swift      Color(rgba:), VisualEffectBackground, SystemLinks
  Views/HeaderView.swift   date + ‹ › Today
  Views/StatusViews.swift  AccessDeniedView, ErrorBanner
  Views/StickyContentView.swift  root view (list in Task 6, timeline + dialogs in Task 7)
  Views/SettingsView.swift hours, calendars, opacity, launch at login
  Views/AllDayStrip.swift  all-day chips
  Views/DayTimelineView.swift  timeline, gestures, HourGrid, EventBlockView
  Views/EventEditPopover.swift quick editor
Tests/StickyCalendarCoreTests/
  TestSupport.swift        UTC calendar, at(), event() helpers
  EventItemTests.swift
  TimelineLayoutTests.swift
  AppSettingsTests.swift
  FakeSource.swift         in-memory EventSource
  CalendarStoreTests.swift
```

---

### Task 1: Package scaffold, test runner, and event models

**Files:**
- Create: `Package.swift`, `scripts/test.sh`, `Sources/StickyCalendarCore/Models.swift`, `Sources/StickyCalendar/StickyCalendarApp.swift` (temporary stub), `Tests/StickyCalendarCoreTests/TestSupport.swift`, `Tests/StickyCalendarCoreTests/EventItemTests.swift`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public let minimumEventDuration: TimeInterval` (900)
  - `public struct RGBA { red, green, blue, alpha: Double; static let fallback }`
  - `public struct CalendarInfo: Identifiable { id: String; title: String; color: RGBA; isWritable: Bool }`
  - `public struct EventItem: Identifiable, Equatable`, with the fields `eventIdentifier, externalIdentifier, occurrenceDate, title, start, end, isAllDay, calendarID, location, notes, isRecurring, isReadOnly` and the members `id: String`, `isNew: Bool`, `duration: TimeInterval`, `withContent(of:) -> EventItem` and `normalized(minimumDuration:) -> EventItem`.
  - Test helpers: `utc: Calendar`, `at(_ hour:, _ minute:, day:) -> Date` (2026-09-<day> in UTC), and `event(_ id:, _ start:, _ end:, calendar:, recurring:, readOnly:, allDay:) -> EventItem`.

- [ ] **Step 1: Create the package manifest**

`Package.swift`:
```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "StickyCalendar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StickyCalendar", targets: ["StickyCalendar"]),
    ],
    targets: [
        .target(name: "StickyCalendarCore"),
        .executableTarget(name: "StickyCalendar", dependencies: ["StickyCalendarCore"]),
        .testTarget(name: "StickyCalendarCoreTests", dependencies: ["StickyCalendarCore"]),
    ]
)
```

- [ ] **Step 2: Create the test runner and ignore build output**

`scripts/test.sh`:
```bash
#!/bin/bash
# Runs the unit tests. With only the Command Line Tools installed (no Xcode),
# Swift Testing lives outside the default search paths, so point swift at it.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV="$(xcode-select -p)"
FW="$DEV/Library/Developer/Frameworks"
LIB="$DEV/Library/Developer/usr/lib"

if [[ -d "$FW/Testing.framework" ]]; then
    exec swift test \
        -Xswiftc -F -Xswiftc "$FW" \
        -Xlinker -rpath -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$LIB" \
        "$@"
else
    exec swift test "$@"
fi
```

Run: `chmod +x scripts/test.sh && printf 'build/\n' >> .gitignore`

- [ ] **Step 3: Add a temporary executable stub so the package builds**

`Sources/StickyCalendar/StickyCalendarApp.swift` (Task 6 replaces it):
```swift
print("StickyCalendar stub")
```

- [ ] **Step 4: Write the failing tests**

`Tests/StickyCalendarCoreTests/TestSupport.swift`:
```swift
import Foundation
@testable import StickyCalendarCore

let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// 2026-09-<day> hh:mm in UTC.
func at(_ hour: Int, _ minute: Int = 0, day: Int = 28) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

func event(
    _ id: String, _ start: Date, _ end: Date,
    calendar: String = "work", recurring: Bool = false, readOnly: Bool = false, allDay: Bool = false
) -> EventItem {
    EventItem(
        eventIdentifier: id, title: id, start: start, end: end, isAllDay: allDay,
        calendarID: calendar, isRecurring: recurring, isReadOnly: readOnly
    )
}
```

`Tests/StickyCalendarCoreTests/EventItemTests.swift`:
```swift
import Foundation
import Testing
@testable import StickyCalendarCore

struct EventItemTests {
    @Test func normalizedTrimsTitleAndFixesEndBeforeStart() {
        var e = event("n", at(10), at(9))
        e.title = "  Standup \n"
        let n = e.normalized()
        #expect(n.title == "Standup")
        #expect(n.end == at(10, 15))
    }

    @Test func recurringIdStaysStableWhenOccurrenceIsMoved() {
        var e = event("r", at(9), at(10), recurring: true)
        let before = e.id
        e.start = at(11)
        e.end = at(12)
        #expect(e.id == before)
    }
}
```

- [ ] **Step 5: Run the tests and confirm they fail**

Run: `./scripts/test.sh`
Expected: the build fails with `cannot find 'EventItem' in scope` (or a missing `StickyCalendarCore` sources error).

- [ ] **Step 6: Implement the models**

`Sources/StickyCalendarCore/Models.swift`:
```swift
import Foundation

/// Shortest event the UI will create or resize to.
public let minimumEventDuration: TimeInterval = 15 * 60

/// A colour in sRGB components, so the core stays free of AppKit/SwiftUI types.
public struct RGBA: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let fallback = RGBA(red: 0.23, green: 0.51, blue: 0.96)
}

public struct CalendarInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var color: RGBA
    public var isWritable: Bool

    public init(id: String, title: String, color: RGBA = .fallback, isWritable: Bool = true) {
        self.id = id
        self.title = title
        self.color = color
        self.isWritable = isWritable
    }
}

/// A value-type snapshot of one calendar event (or one occurrence of a recurring event).
public struct EventItem: Identifiable, Equatable, Sendable {
    /// EventKit `eventIdentifier`; empty for a draft that has not been saved yet.
    public var eventIdentifier: String
    /// EventKit `calendarItemExternalIdentifier`, used to open the event in Calendar.app.
    public var externalIdentifier: String?
    /// Original start of this occurrence; together with `eventIdentifier` it pins one occurrence.
    public var occurrenceDate: Date
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var location: String?
    public var notes: String?
    public var isRecurring: Bool
    public var isReadOnly: Bool

    public init(
        eventIdentifier: String = "",
        externalIdentifier: String? = nil,
        occurrenceDate: Date? = nil,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarID: String,
        location: String? = nil,
        notes: String? = nil,
        isRecurring: Bool = false,
        isReadOnly: Bool = false
    ) {
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.occurrenceDate = occurrenceDate ?? start
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.location = location
        self.notes = notes
        self.isRecurring = isRecurring
        self.isReadOnly = isReadOnly
    }

    /// Stable across moves: a non-recurring event keeps its identifier, and a recurring
    /// occurrence keeps its original occurrence date even when rescheduled.
    public var id: String {
        isRecurring ? "\(eventIdentifier)|\(occurrenceDate.timeIntervalSinceReferenceDate)" : eventIdentifier
    }

    public var isNew: Bool { eventIdentifier.isEmpty }
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// This item's identity with `other`'s user-editable fields.
    public func withContent(of other: EventItem) -> EventItem {
        var copy = self
        copy.title = other.title
        copy.start = other.start
        copy.end = other.end
        copy.calendarID = other.calendarID
        copy.location = other.location
        copy.notes = other.notes
        return copy
    }

    /// Trims the title and guarantees `end` is at least `minimumDuration` after `start`.
    public func normalized(minimumDuration: TimeInterval = minimumEventDuration) -> EventItem {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.end < copy.start.addingTimeInterval(minimumDuration), !isAllDay {
            copy.end = copy.start.addingTimeInterval(minimumDuration)
        }
        return copy
    }
}
```

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `./scripts/test.sh 2>&1 | grep -E "✘|Test run"`
Expected: `✔ Test run with 2 tests in 1 suite passed`

- [ ] **Step 8: Commit**

```bash
git add Package.swift .gitignore scripts/test.sh Sources Tests
git commit -m "Add package scaffold and event models

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Timeline layout (hour range, geometry, snapping, drag maths, overlap columns)

**Files:**
- Create: `Sources/StickyCalendarCore/TimelineLayout.swift`, `Tests/StickyCalendarCoreTests/TimelineLayoutTests.swift`

**Interfaces:**
- Consumes: `EventItem`, `minimumEventDuration` (Task 1).
- Produces:
  - `HourRange(start:end:)` clamps its values. It has `start`, `end`, `static let standard` (8–20), `withStart(_:)`, `withEnd(_:)`, `dates(on:calendar:) -> (start: Date, end: Date)` and `expanded(toInclude:dayStart:calendar:) -> HourRange`.
  - `TimelineGeometry(dayStart:range:height:calendar:)` has `rangeStart`, `rangeEnd`, `height: Double`, `pointsPerSecond`, `y(for:)`, `date(forY:)`, `y(forHour:)`, `frame(for:minHeight:) -> (top: Double, height: Double)` and `partition(_:) -> RangePartition`.
  - `RangePartition { visible, earlier, later: [EventItem] }`
  - `Snap.nearest(_:)` rounds to the nearest 15 minutes.
  - `DragKind { move, resizeStart, resizeEnd }`. `EventDrag.apply(_:to:delta:) -> EventItem` and `EventDrag.newInterval(from:to:) -> (start, end)`.
  - `ColumnSlot { column, count }`. `OverlapLayout.columns(for:) -> [String: ColumnSlot]`, keyed by `EventItem.id`.

- [ ] **Step 1: Write the failing tests**

`Tests/StickyCalendarCoreTests/TimelineLayoutTests.swift`:
```swift
import Foundation
import Testing
@testable import StickyCalendarCore

struct HourRangeTests {
    @Test func clampsInvalidValues() {
        #expect(HourRange(start: -3, end: 30) == HourRange(start: 0, end: 24))
        #expect(HourRange(start: 10, end: 10) == HourRange(start: 10, end: 11))
        #expect(HourRange(start: 24, end: 24) == HourRange(start: 23, end: 24))
    }

    @Test func withStartPushesEndOnlyWhenNeeded() {
        let r = HourRange(start: 8, end: 20)
        #expect(r.withStart(10) == HourRange(start: 10, end: 20))
        #expect(r.withStart(21) == HourRange(start: 21, end: 22))
    }

    @Test func withEndPullsStartOnlyWhenNeeded() {
        let r = HourRange(start: 8, end: 20)
        #expect(r.withEnd(18) == HourRange(start: 8, end: 18))
        #expect(r.withEnd(7) == HourRange(start: 6, end: 7))
    }

    @Test func datesUseNextMidnightForHour24() {
        let (s, e) = HourRange(start: 0, end: 24).dates(on: at(0), calendar: utc)
        #expect(s == at(0))
        #expect(e == at(0, day: 29))
    }

    @Test func expandsToIncludeEarlierAndLaterEvents() {
        let events = [event("a", at(6, 30), at(7)), event("b", at(20), at(21, 10))]
        let r = HourRange.standard.expanded(toInclude: events, dayStart: at(0), calendar: utc)
        #expect(r == HourRange(start: 6, end: 22))
    }

    @Test func expansionClipsEventsCrossingMidnight() {
        let events = [event("late", at(23), at(1, day: 29)), event("early", at(22, day: 27), at(1))]
        let r = HourRange.standard.expanded(toInclude: events, dayStart: at(0), calendar: utc)
        #expect(r == HourRange(start: 0, end: 24))
    }
}

struct TimelineGeometryTests {
    let g = TimelineGeometry(dayStart: at(0), range: HourRange(start: 8, end: 20), height: 600, calendar: utc)

    @Test func mapsTimeToYAndBack() {
        #expect(g.y(for: at(8)) == 0)
        #expect(g.y(for: at(14)) == 300)
        #expect(g.y(for: at(20)) == 600)
        #expect(g.date(forY: 300) == at(14))
        #expect(g.y(forHour: 9) == 50)
    }

    @Test func frameClipsToRangeAndEnforcesMinimumHeight() {
        let clipped = g.frame(for: event("x", at(7), at(9)))
        #expect(clipped.top == 0 && clipped.height == 50)
        let tiny = g.frame(for: event("y", at(10), at(10, 5)))
        #expect(tiny.height == 14)
    }

    @Test func partitionsEventsOutsideRange() {
        let early = event("early", at(6), at(7))
        let edge = event("edge", at(7), at(8))
        let inside = event("in", at(9), at(10))
        let straddle = event("straddle", at(19), at(21))
        let late = event("late", at(20), at(21))
        let overnight = event("overnight", at(23), at(1, day: 29))
        let p = g.partition([early, edge, inside, straddle, late, overnight])
        #expect(p.earlier.map(\.id) == ["early", "edge"])
        #expect(p.visible.map(\.id) == ["in", "straddle"])
        #expect(p.later.map(\.id) == ["late", "overnight"])
    }

    @Test func dstDayUsesRealElapsedTime() {
        var zurich = Calendar(identifier: .gregorian)
        zurich.timeZone = TimeZone(identifier: "Europe/Zurich")!
        // 2026-03-29: clocks jump 02:00 -> 03:00, so the day is 23 hours long.
        let day = zurich.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        let g = TimelineGeometry(dayStart: day, range: HourRange(start: 0, end: 24), height: 230, calendar: zurich)
        let threeAM = zurich.date(bySettingHour: 3, minute: 0, second: 0, of: day)!
        #expect(abs(g.y(for: threeAM) - 20) < 0.001) // 2 real hours at 10 pt/hour
        #expect(abs(g.y(forHour: 24) - 230) < 0.001)
    }
}

struct SnapAndDragTests {
    @Test func snapsToNearestQuarterHour() {
        #expect(Snap.nearest(at(9, 7)) == at(9))
        #expect(Snap.nearest(at(9, 8)) == at(9, 15))
        #expect(Snap.nearest(at(9, 53)) == at(10))
    }

    @Test func moveKeepsDurationAndSnaps() {
        let e = event("m", at(9), at(10))
        let moved = EventDrag.apply(.move, to: e, delta: 50 * 60)
        #expect(moved.start == at(9, 45) && moved.end == at(10, 45))
    }

    @Test func resizeNeverGoesBelowFifteenMinutes() {
        let e = event("r", at(9), at(10))
        #expect(EventDrag.apply(.resizeEnd, to: e, delta: -3 * 3600).end == at(9, 15))
        #expect(EventDrag.apply(.resizeStart, to: e, delta: 3 * 3600).start == at(9, 45))
        #expect(EventDrag.apply(.resizeStart, to: e, delta: -20 * 60).start == at(8, 45))
    }

    @Test func newIntervalWorksInEitherDirection() {
        let down = EventDrag.newInterval(from: at(9, 2), to: at(10, 29))
        #expect(down.start == at(9) && down.end == at(10, 30))
        let up = EventDrag.newInterval(from: at(10, 29), to: at(9, 2))
        #expect(up.start == at(9) && up.end == at(10, 30))
        let click = EventDrag.newInterval(from: at(9), to: at(9, 3))
        #expect(click.start == at(9) && click.end == at(9, 15))
    }
}

struct OverlapLayoutTests {
    @Test func separateEventsGetOneColumnEach() {
        let slots = OverlapLayout.columns(for: [event("a", at(9), at(10)), event("b", at(10), at(11))])
        #expect(slots["a"] == ColumnSlot(column: 0, count: 1))
        #expect(slots["b"] == ColumnSlot(column: 0, count: 1))
    }

    @Test func transitiveOverlapsShareColumnCountAndReuseFreeColumns() {
        // a 9-11, b 10-12, c 11-13: a and c don't overlap, so c reuses a's column.
        let slots = OverlapLayout.columns(for: [
            event("c", at(11), at(13)), event("a", at(9), at(11)), event("b", at(10), at(12)),
        ])
        #expect(slots["a"] == ColumnSlot(column: 0, count: 2))
        #expect(slots["b"] == ColumnSlot(column: 1, count: 2))
        #expect(slots["c"] == ColumnSlot(column: 0, count: 2))
    }

    @Test func threeWayOverlapUsesThreeColumns() {
        let slots = OverlapLayout.columns(for: [
            event("a", at(9), at(12)), event("b", at(9, 30), at(10)), event("c", at(9, 45), at(11)),
        ])
        #expect(slots.values.allSatisfy { $0.count == 3 })
        #expect(Set(slots.values.map(\.column)) == [0, 1, 2])
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `./scripts/test.sh`
Expected: the build fails with `cannot find 'HourRange' in scope`.

- [ ] **Step 3: Implement the layout**

`Sources/StickyCalendarCore/TimelineLayout.swift`:
```swift
import Foundation

/// Whole hours of the day shown on the timeline. `end` is exclusive and may be 24.
public struct HourRange: Equatable, Sendable {
    public let start: Int
    public let end: Int

    /// Clamps to 0...23 for `start` and `start+1...24` for `end`.
    public init(start: Int, end: Int) {
        let s = min(max(start, 0), 23)
        self.start = s
        self.end = min(max(end, s + 1), 24)
    }

    public static let standard = HourRange(start: 8, end: 20)

    /// Keeps `end`, pushing it later only if the new start would pass it.
    public func withStart(_ hour: Int) -> HourRange { HourRange(start: hour, end: max(end, hour + 1)) }

    /// Keeps `start`, pulling it earlier only if the new end would pass it.
    public func withEnd(_ hour: Int) -> HourRange { HourRange(start: min(start, hour - 1), end: hour) }

    public func dates(on dayStart: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let s = calendar.date(bySettingHour: start, minute: 0, second: 0, of: dayStart) ?? dayStart
        let e = end == 24
            ? calendar.date(byAdding: .day, value: 1, to: dayStart)!
            : calendar.date(bySettingHour: end, minute: 0, second: 0, of: dayStart)!
        return (s, e)
    }

    /// The smallest range containing `self` and the parts of `events` that fall on this day.
    public func expanded(toInclude events: [EventItem], dayStart: Date, calendar: Calendar) -> HourRange {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        var lo = start
        var hi = end
        for event in events where event.end > dayStart && event.start < dayEnd {
            let s = max(event.start, dayStart)
            let e = min(event.end, dayEnd)
            lo = min(lo, calendar.component(.hour, from: s))
            if e >= dayEnd {
                hi = 24
            } else {
                let parts = calendar.dateComponents([.hour, .minute, .second], from: e)
                let roundUp = (parts.minute ?? 0) > 0 || (parts.second ?? 0) > 0
                hi = max(hi, (parts.hour ?? 0) + (roundUp ? 1 : 0))
            }
        }
        return HourRange(start: lo, end: hi)
    }
}

/// Maps between time and vertical position for one day's visible range.
/// Uses real elapsed time, so a DST day's range is 23 or 25 hours tall without gaps.
public struct TimelineGeometry: Sendable {
    public let dayStart: Date
    public let range: HourRange
    public let rangeStart: Date
    public let rangeEnd: Date
    public let height: Double
    private let calendar: Calendar

    public init(dayStart: Date, range: HourRange, height: Double, calendar: Calendar = .autoupdatingCurrent) {
        self.dayStart = dayStart
        self.range = range
        self.height = height
        self.calendar = calendar
        (rangeStart, rangeEnd) = range.dates(on: dayStart, calendar: calendar)
    }

    public var pointsPerSecond: Double { height / rangeEnd.timeIntervalSince(rangeStart) }

    public func y(for date: Date) -> Double { date.timeIntervalSince(rangeStart) * pointsPerSecond }

    public func date(forY y: Double) -> Date { rangeStart.addingTimeInterval(y / pointsPerSecond) }

    public func y(forHour hour: Int) -> Double {
        if hour >= 24 { return y(for: calendar.date(byAdding: .day, value: 1, to: dayStart)!) }
        return y(for: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) ?? dayStart)
    }

    /// Vertical extent of `event`, clipped to the visible range, never shorter than `minHeight`.
    public func frame(for event: EventItem, minHeight: Double = 14) -> (top: Double, height: Double) {
        let top = y(for: max(event.start, rangeStart))
        let bottom = y(for: min(event.end, rangeEnd))
        return (top, max(bottom - top, minHeight))
    }

    public func partition(_ events: [EventItem]) -> RangePartition {
        var result = RangePartition()
        for event in events {
            if event.end <= rangeStart && event.start < rangeStart {
                result.earlier.append(event)
            } else if event.start >= rangeEnd {
                result.later.append(event)
            } else {
                result.visible.append(event)
            }
        }
        return result
    }
}

public struct RangePartition: Equatable, Sendable {
    public var visible: [EventItem] = []
    public var earlier: [EventItem] = []
    public var later: [EventItem] = []
    public init() {}
}

public enum Snap {
    public static let step: TimeInterval = 15 * 60

    /// Rounds to the nearest quarter hour. Absolute-time rounding is correct in every
    /// time zone because all UTC offsets are multiples of 15 minutes.
    public static func nearest(_ date: Date, step: TimeInterval = step) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / step).rounded() * step)
    }
}

public enum DragKind: Sendable {
    case move, resizeStart, resizeEnd
}

public enum EventDrag {
    public static let minimumDuration = minimumEventDuration

    /// The event after dragging by `delta` seconds, snapped to 15 minutes.
    public static func apply(_ kind: DragKind, to event: EventItem, delta: TimeInterval) -> EventItem {
        var e = event
        switch kind {
        case .move:
            e.start = Snap.nearest(event.start.addingTimeInterval(delta))
            e.end = e.start.addingTimeInterval(event.duration)
        case .resizeStart:
            e.start = min(Snap.nearest(event.start.addingTimeInterval(delta)),
                          event.end.addingTimeInterval(-minimumDuration))
        case .resizeEnd:
            e.end = max(Snap.nearest(event.end.addingTimeInterval(delta)),
                        event.start.addingTimeInterval(minimumDuration))
        }
        return e
    }

    /// Start and end for a new event dragged out between two points in time (either order).
    public static func newInterval(from a: Date, to b: Date) -> (start: Date, end: Date) {
        let s = Snap.nearest(min(a, b))
        let e = max(Snap.nearest(max(a, b)), s.addingTimeInterval(minimumDuration))
        return (s, e)
    }
}

public struct ColumnSlot: Equatable, Sendable {
    public var column: Int
    public var count: Int
    public init(column: Int, count: Int) {
        self.column = column
        self.count = count
    }
}

public enum OverlapLayout {
    /// Calendar.app-style side-by-side layout: events that transitively overlap form a
    /// cluster; each takes the first free column; all share the cluster's column count.
    public static func columns(for events: [EventItem]) -> [String: ColumnSlot] {
        let sorted = events.sorted { ($0.start, $1.end) < ($1.start, $0.end) }
        var result: [String: ColumnSlot] = [:]
        var cluster: [(id: String, column: Int)] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            for entry in cluster {
                result[entry.id] = ColumnSlot(column: entry.column, count: columnEnds.count)
            }
            cluster = []
            columnEnds = []
        }

        for event in sorted {
            if !cluster.isEmpty && event.start >= clusterEnd { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= event.start }) {
                columnEnds[free] = event.end
                cluster.append((event.id, free))
            } else {
                columnEnds.append(event.end)
                cluster.append((event.id, columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, event.end)
        }
        flush()
        return result
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `./scripts/test.sh 2>&1 | grep -E "✘|Test run"`
Expected: `✔ Test run with 19 tests in 5 suites passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/StickyCalendarCore/TimelineLayout.swift Tests/StickyCalendarCoreTests/TimelineLayoutTests.swift
git commit -m "Add timeline layout: geometry, snapping, drag maths, overlap columns

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Persisted settings

**Files:**
- Create: `Sources/StickyCalendarCore/AppSettings.swift`, `Tests/StickyCalendarCoreTests/AppSettingsTests.swift`

**Interfaces:**
- Consumes: `HourRange` (Task 2).
- Produces: `@MainActor @Observable final class AppSettings(defaults: UserDefaults = .standard)`.
  - Read-only properties: `hourRange: HourRange`, `hiddenCalendarIDs: Set<String>`, `opacity: Double`.
  - Setters: `setStartHour(_:)`, `setEndHour(_:)`, `setCalendar(_:visible:)`, `setOpacity(_:)`.
  - `static let opacityRange: ClosedRange<Double>`

- [ ] **Step 1: Write the failing tests**

`Tests/StickyCalendarCoreTests/AppSettingsTests.swift`:
```swift
import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct AppSettingsTests {
    let defaults: UserDefaults

    init() {
        let name = "AppSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    @Test func usesDefaultsWhenNothingStored() {
        let s = AppSettings(defaults: defaults)
        #expect(s.hourRange == HourRange(start: 8, end: 20))
        #expect(s.hiddenCalendarIDs.isEmpty)
        #expect(s.opacity == 0.92)
    }

    @Test func persistsChangesAcrossInstances() {
        let s = AppSettings(defaults: defaults)
        s.setStartHour(7)
        s.setEndHour(22)
        s.setCalendar("holidays", visible: false)
        s.setOpacity(0.7)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.hourRange == HourRange(start: 7, end: 22))
        #expect(reloaded.hiddenCalendarIDs == ["holidays"])
        #expect(reloaded.opacity == 0.7)
    }

    @Test func clampsOpacityAndKeepsRangeValid() {
        let s = AppSettings(defaults: defaults)
        s.setOpacity(0.1)
        #expect(s.opacity == 0.5)
        s.setStartHour(23)
        #expect(s.hourRange == HourRange(start: 23, end: 24))
    }

    @Test func showingACalendarAgainRemovesItFromHidden() {
        let s = AppSettings(defaults: defaults)
        s.setCalendar("home", visible: false)
        s.setCalendar("home", visible: true)
        #expect(s.hiddenCalendarIDs.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `./scripts/test.sh`
Expected: the build fails with `cannot find 'AppSettings' in scope`.

- [ ] **Step 3: Implement the settings**

`Sources/StickyCalendarCore/AppSettings.swift`:
```swift
import Foundation
import Observation

/// User preferences, persisted in UserDefaults on every change.
@MainActor
@Observable
public final class AppSettings {
    private enum Key {
        static let startHour = "startHour"
        static let endHour = "endHour"
        static let hiddenCalendarIDs = "hiddenCalendarIDs"
        static let opacity = "opacity"
    }

    public static let opacityRange: ClosedRange<Double> = 0.5...1.0

    @ObservationIgnored private let defaults: UserDefaults

    public private(set) var hourRange: HourRange
    public private(set) var hiddenCalendarIDs: Set<String>
    public private(set) var opacity: Double

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hourRange = HourRange(
            start: defaults.object(forKey: Key.startHour) as? Int ?? HourRange.standard.start,
            end: defaults.object(forKey: Key.endHour) as? Int ?? HourRange.standard.end
        )
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: Key.hiddenCalendarIDs) ?? [])
        opacity = Self.clampOpacity(defaults.object(forKey: Key.opacity) as? Double ?? 0.92)
    }

    public func setStartHour(_ hour: Int) { store(hourRange.withStart(hour)) }

    public func setEndHour(_ hour: Int) { store(hourRange.withEnd(hour)) }

    public func setCalendar(_ id: String, visible: Bool) {
        if visible { hiddenCalendarIDs.remove(id) } else { hiddenCalendarIDs.insert(id) }
        defaults.set(hiddenCalendarIDs.sorted(), forKey: Key.hiddenCalendarIDs)
    }

    public func setOpacity(_ value: Double) {
        opacity = Self.clampOpacity(value)
        defaults.set(opacity, forKey: Key.opacity)
    }

    private func store(_ range: HourRange) {
        hourRange = range
        defaults.set(range.start, forKey: Key.startHour)
        defaults.set(range.end, forKey: Key.endHour)
    }

    private static func clampOpacity(_ value: Double) -> Double {
        min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `./scripts/test.sh 2>&1 | grep -E "✘|Test run"`
Expected: `✔ Test run with 23 tests in 6 suites passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/StickyCalendarCore/AppSettings.swift Tests/StickyCalendarCoreTests/AppSettingsTests.swift
git commit -m "Add persisted app settings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Event source protocol and calendar store

**Files:**
- Create: `Sources/StickyCalendarCore/EventSource.swift`, `Sources/StickyCalendarCore/CalendarStore.swift`, `Tests/StickyCalendarCoreTests/FakeSource.swift`, `Tests/StickyCalendarCoreTests/CalendarStoreTests.swift`

**Interfaces:**
- Consumes: `EventItem`, `CalendarInfo` (Task 1). `HourRange`, `EventDrag` (Task 2). `AppSettings` (Task 3).
- Produces:
  - `CalendarAccess { notDetermined, granted, denied }`, `EditSpan { thisEvent, futureEvents }`, and `EventSourceError.notFound`, whose message is "The event no longer exists."
  - `@MainActor protocol EventSource`, with `onChange`, `currentAccess()`, `requestAccess() async`, `calendars()`, `defaultCalendarID()`, `events(from:to:)`, `save(_:span:) throws -> EventItem` (creates the event when `isNew`) and `remove(_:span:) throws`.
  - `PendingEdit { original, updated }`
  - `@MainActor @Observable final class CalendarStore(source:settings:calendar: = .autoupdatingCurrent, now: = Date.init)`:
    - state: `access`, `day`, `timedEvents`, `allDayEvents`, `calendars`, `rangeOverride`, `selectedID`, `lastError`, `pendingEdit`, `pendingDelete`, `undoManager`
    - computed: `isViewingToday`, `visibleCalendars`, `calendarInfo(id:)`, `effectiveRange`
    - loading and navigation: `reload()`, `requestAccessIfNeeded() async`, `goToToday()`, `goToDay(offset:)`, `handleClockChange()`, `expandRangeToFitAll()`
    - editing: `makeDraft(start:end:) -> EventItem?`, `create(_:) -> EventItem?`, `requestUpdate(from:to:)`, `confirmEdit(_:span:)`, `cancelPendingEdit()`, `requestDelete(_:)`, `requestDeleteSelected()`, `confirmDelete(_:span:)`, `cancelPendingDelete()`

- [ ] **Step 1: Write the fake source and failing tests**

`Tests/StickyCalendarCoreTests/FakeSource.swift`:
```swift
import Foundation
@testable import StickyCalendarCore

struct FakeError: LocalizedError {
    var errorDescription: String? { "Calendar is read-only" }
}

@MainActor
final class FakeSource: EventSource {
    var onChange: (() -> Void)?
    var access: CalendarAccess = .granted
    var cals = [
        CalendarInfo(id: "work", title: "Work"),
        CalendarInfo(id: "home", title: "Home"),
        CalendarInfo(id: "holidays", title: "Holidays", isWritable: false),
    ]
    var defaultID: String? = "work"
    var stored: [EventItem] = []
    var failNextWrite = false
    private(set) var spans: [EditSpan] = []
    private var nextID = 1

    func currentAccess() -> CalendarAccess { access }

    func requestAccess() async -> CalendarAccess {
        access = .granted
        return access
    }

    func calendars() -> [CalendarInfo] { cals }

    func defaultCalendarID() -> String? { defaultID }

    func events(from start: Date, to end: Date) -> [EventItem] {
        stored.filter { $0.start < end && ($0.end > start || $0.start == start) }
    }

    func save(_ item: EventItem, span: EditSpan) throws -> EventItem {
        try checkFailure()
        spans.append(span)
        var saved = item
        if item.isNew {
            saved.eventIdentifier = "e\(nextID)"
            saved.occurrenceDate = item.start
            nextID += 1
            stored.append(saved)
        } else {
            guard let i = stored.firstIndex(where: { $0.id == item.id }) else {
                throw EventSourceError.notFound
            }
            stored[i] = saved
        }
        return saved
    }

    func remove(_ item: EventItem, span: EditSpan) throws {
        try checkFailure()
        spans.append(span)
        guard let i = stored.firstIndex(where: { $0.id == item.id }) else {
            throw EventSourceError.notFound
        }
        stored.remove(at: i)
    }

    private func checkFailure() throws {
        if failNextWrite {
            failNextWrite = false
            throw FakeError()
        }
    }
}
```

`Tests/StickyCalendarCoreTests/CalendarStoreTests.swift`:
```swift
import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct CalendarStoreTests {
    let source = FakeSource()
    let settings: AppSettings

    init() {
        let name = "CalendarStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = AppSettings(defaults: defaults)
    }

    func makeStore(now: @escaping () -> Date = { at(10) }) -> CalendarStore {
        CalendarStore(source: source, settings: settings, calendar: utc, now: now)
    }

    // MARK: Loading

    @Test func loadsTodaySplittingAllDayAndHidingCalendars() {
        source.stored = [
            event("b", at(11), at(12)),
            event("a", at(9), at(10)),
            event("hol", at(0), at(0, day: 29), calendar: "holidays", allDay: true),
            event("home", at(13), at(14), calendar: "home"),
            event("tomorrow", at(9, day: 29), at(10, day: 29)),
        ]
        settings.setCalendar("home", visible: false)
        let store = makeStore()
        #expect(store.day == at(0))
        #expect(store.timedEvents.map(\.id) == ["a", "b"])
        #expect(store.allDayEvents.map(\.id) == ["hol"])
        #expect(store.visibleCalendars.map(\.id) == ["work", "holidays"])
    }

    @Test func externalChangesTriggerReload() {
        let store = makeStore()
        source.stored = [event("new", at(9), at(10))]
        source.onChange?()
        #expect(store.timedEvents.map(\.id) == ["new"])
    }

    @Test func deniedAccessShowsNothingAndRecoversWhenGranted() {
        source.access = .denied
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        #expect(store.access == .denied)
        #expect(store.timedEvents.isEmpty)
        source.access = .granted
        store.reload()
        #expect(store.access == .granted)
        #expect(store.timedEvents.map(\.id) == ["a"])
    }

    @Test func requestsAccessOnlyWhenUndetermined() async {
        source.access = .notDetermined
        let store = makeStore()
        await store.requestAccessIfNeeded()
        #expect(store.access == .granted)
    }

    // MARK: Navigation

    @Test func navigatesDaysAndBack() {
        source.stored = [event("tomorrow", at(9, day: 29), at(10, day: 29))]
        let store = makeStore()
        store.goToDay(offset: 1)
        #expect(store.day == at(0, day: 29))
        #expect(!store.isViewingToday)
        #expect(store.timedEvents.map(\.id) == ["tomorrow"])
        store.goToToday()
        #expect(store.day == at(0))
        #expect(store.isViewingToday)
    }

    @Test func midnightRolloverFollowsTodayOnlyWhenViewingToday() {
        var now = at(23, 59)
        let store = makeStore(now: { now })
        now = at(0, 1, day: 29)
        store.handleClockChange()
        #expect(store.day == at(0, day: 29))

        store.goToDay(offset: 3) // viewing Oct 2
        now = at(0, 1, day: 30)
        store.handleClockChange()
        #expect(store.day == at(0, day: 32)) // still Oct 2 ("Sep 32" normalizes to Oct 2)
    }

    @Test func expandingRangeIsClearedByNavigation() {
        source.stored = [event("early", at(6), at(7))]
        let store = makeStore()
        store.expandRangeToFitAll()
        #expect(store.effectiveRange == HourRange(start: 6, end: 20))
        store.goToDay(offset: 1)
        #expect(store.effectiveRange == HourRange(start: 8, end: 20))
    }

    // MARK: Drafts and creation

    @Test func draftUsesDefaultCalendarOrFirstVisibleWritable() {
        let store = makeStore()
        #expect(store.makeDraft(start: at(9), end: at(10))?.calendarID == "work")
        settings.setCalendar("work", visible: false)
        #expect(store.makeDraft(start: at(9), end: at(10))?.calendarID == "home")
        settings.setCalendar("home", visible: false)
        #expect(store.makeDraft(start: at(9), end: at(10)) == nil) // only read-only "holidays" left
    }

    @Test func createSavesSelectsAndUndoRedoWork() {
        let store = makeStore()
        var draft = store.makeDraft(start: at(9), end: at(10))!
        draft.title = "Focus"
        let saved = store.create(draft)
        #expect(saved != nil)
        #expect(store.timedEvents.map(\.title) == ["Focus"])
        #expect(store.selectedID == saved?.id)

        store.undoManager.undo()
        #expect(store.timedEvents.isEmpty)
        store.undoManager.redo()
        #expect(store.timedEvents.map(\.title) == ["Focus"])
    }

    @Test func blankTitleDraftIsDiscarded() {
        let store = makeStore()
        var draft = store.makeDraft(start: at(9), end: at(10))!
        draft.title = "   "
        #expect(store.create(draft) == nil)
        #expect(source.stored.isEmpty)
        #expect(!store.undoManager.canUndo)
    }

    // MARK: Updating

    @Test func updateNonRecurringSavesImmediatelyAndUndoes() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        let original = store.timedEvents[0]
        store.requestUpdate(from: original, to: EventDrag.apply(.move, to: original, delta: 3600))
        #expect(store.timedEvents[0].start == at(10))
        #expect(store.pendingEdit == nil)

        store.undoManager.undo()
        #expect(store.timedEvents[0].start == at(9))
        store.undoManager.redo()
        #expect(store.timedEvents[0].start == at(10))
    }

    @Test func recurringUpdateWaitsForSpanChoice() {
        source.stored = [event("r", at(9), at(10), recurring: true)]
        let store = makeStore()
        let original = store.timedEvents[0]
        var renamed = original
        renamed.title = "Renamed"
        store.requestUpdate(from: original, to: renamed)
        #expect(store.pendingEdit?.updated.title == "Renamed")
        #expect(source.stored[0].title == "r")

        store.confirmEdit(store.pendingEdit!, span: .futureEvents)
        #expect(store.pendingEdit == nil)
        #expect(source.stored[0].title == "Renamed")
        #expect(source.spans == [.futureEvents])
    }

    @Test func readOnlyAndUnchangedEditsAreIgnored() {
        source.stored = [event("ro", at(9), at(10), calendar: "holidays", readOnly: true)]
        let store = makeStore()
        let original = store.timedEvents[0]
        store.requestUpdate(from: original, to: EventDrag.apply(.move, to: original, delta: 3600))
        store.requestUpdate(from: original, to: original)
        store.requestDelete(original)
        #expect(source.spans.isEmpty)
        #expect(store.pendingDelete == nil)
    }

    @Test func failedSaveReportsErrorAndKeepsOriginal() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        let original = store.timedEvents[0]
        source.failNextWrite = true
        store.requestUpdate(from: original, to: EventDrag.apply(.move, to: original, delta: 3600))
        #expect(store.lastError == "Calendar is read-only")
        #expect(store.timedEvents[0].start == at(9))
        #expect(!store.undoManager.canUndo)
    }

    @Test func editingAnEventDeletedElsewhereReportsNotFound() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        let original = store.timedEvents[0]
        source.stored = []
        store.requestUpdate(from: original, to: EventDrag.apply(.move, to: original, delta: 3600))
        #expect(store.lastError == "The event no longer exists.")
        #expect(store.timedEvents.isEmpty)
    }

    // MARK: Deleting

    @Test func deleteSelectedAsksThenDeletesAndUndoRestores() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        store.selectedID = "a"
        store.requestDeleteSelected()
        #expect(store.pendingDelete?.id == "a")
        #expect(source.stored.count == 1)

        store.confirmDelete(store.pendingDelete!, span: .thisEvent)
        #expect(store.timedEvents.isEmpty)
        #expect(store.selectedID == nil)

        store.undoManager.undo()
        #expect(store.timedEvents.map(\.title) == ["a"])
        #expect(store.timedEvents[0].start == at(9))
    }

    @Test func recurringDeleteUsesChosenSpanAndIsNotUndoable() {
        source.stored = [event("r", at(9), at(10), recurring: true)]
        let store = makeStore()
        store.requestDelete(store.timedEvents[0])
        store.confirmDelete(store.pendingDelete!, span: .futureEvents)
        #expect(source.spans == [.futureEvents])
        #expect(!store.undoManager.canUndo)
    }

    @Test func cancelClearsPendingStateWithoutWriting() {
        source.stored = [event("a", at(9), at(10), recurring: true)]
        let store = makeStore()
        store.requestDelete(store.timedEvents[0])
        store.cancelPendingDelete()
        var renamed = store.timedEvents[0]
        renamed.title = "x"
        store.requestUpdate(from: store.timedEvents[0], to: renamed)
        store.cancelPendingEdit()
        #expect(store.pendingDelete == nil && store.pendingEdit == nil)
        #expect(source.spans.isEmpty)
    }

    @Test func confirmStillWorksIfDialogClearedPendingStateFirst() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        store.requestDelete(store.timedEvents[0])
        let item = store.pendingDelete!
        store.cancelPendingDelete() // SwiftUI may reset the binding before the button action
        store.confirmDelete(item, span: .thisEvent)
        #expect(source.stored.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `./scripts/test.sh`
Expected: the build fails with `cannot find type 'EventSource' in scope`.

- [ ] **Step 3: Implement the protocol**

`Sources/StickyCalendarCore/EventSource.swift`:
```swift
import Foundation

public enum CalendarAccess: Equatable, Sendable {
    case notDetermined, granted, denied
}

/// Which occurrences of a recurring event an edit applies to.
public enum EditSpan: Sendable {
    case thisEvent, futureEvents
}

public enum EventSourceError: LocalizedError {
    case notFound

    public var errorDescription: String? {
        switch self {
        case .notFound: "The event no longer exists."
        }
    }
}

/// Everything the store needs from a calendar backend. `EventKitSource` is the real one;
/// tests use an in-memory fake.
@MainActor
public protocol EventSource: AnyObject {
    /// Called whenever the underlying calendar database changes (including our own saves).
    var onChange: (() -> Void)? { get set }
    func currentAccess() -> CalendarAccess
    func requestAccess() async -> CalendarAccess
    func calendars() -> [CalendarInfo]
    func defaultCalendarID() -> String?
    /// Events overlapping `[start, end)`, including all-day and multi-day events.
    func events(from start: Date, to end: Date) -> [EventItem]
    /// Creates the event if `item.isNew`, otherwise updates it. Returns the saved state.
    func save(_ item: EventItem, span: EditSpan) throws -> EventItem
    func remove(_ item: EventItem, span: EditSpan) throws
}
```

- [ ] **Step 4: Implement the store**

`Sources/StickyCalendarCore/CalendarStore.swift`:
```swift
import Foundation
import Observation

/// An edit to a recurring event, waiting for the user to pick "this" or "future" events.
public struct PendingEdit: Equatable, Sendable {
    public var original: EventItem
    public var updated: EventItem
}

/// The single owner of calendar state for the UI. All reads and writes go through here.
@MainActor
@Observable
public final class CalendarStore {
    public private(set) var access: CalendarAccess = .notDetermined
    /// Start of the day being shown.
    public private(set) var day: Date
    public private(set) var timedEvents: [EventItem] = []
    public private(set) var allDayEvents: [EventItem] = []
    public private(set) var calendars: [CalendarInfo] = []
    /// Set by "+N earlier/later"; cleared when the day changes.
    public private(set) var rangeOverride: HourRange?
    public var selectedID: String?
    public var lastError: String?
    public var pendingEdit: PendingEdit?
    public var pendingDelete: EventItem?

    @ObservationIgnored public let undoManager = UndoManager()
    @ObservationIgnored private let source: EventSource
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    /// True while the user is "on today"; the view then follows midnight rollover.
    @ObservationIgnored private var followsToday = true

    public init(
        source: EventSource,
        settings: AppSettings,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.settings = settings
        self.calendar = calendar
        self.now = now
        day = calendar.startOfDay(for: now())
        source.onChange = { [weak self] in self?.reload() }
        reload()
    }

    // MARK: Reading

    public var isViewingToday: Bool { calendar.isDate(day, inSameDayAs: now()) }

    public var visibleCalendars: [CalendarInfo] {
        calendars.filter { !settings.hiddenCalendarIDs.contains($0.id) }
    }

    public func calendarInfo(id: String) -> CalendarInfo? { calendars.first { $0.id == id } }

    public var effectiveRange: HourRange { rangeOverride ?? settings.hourRange }

    public func reload() {
        access = source.currentAccess()
        guard access == .granted else {
            calendars = []
            timedEvents = []
            allDayEvents = []
            return
        }
        calendars = source.calendars()
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
        let hidden = settings.hiddenCalendarIDs
        let events = source.events(from: day, to: dayEnd)
            .filter { !hidden.contains($0.calendarID) }
            .sorted { $0.start < $1.start }
        timedEvents = events.filter { !$0.isAllDay }
        allDayEvents = events.filter(\.isAllDay)
        if let id = selectedID, !timedEvents.contains(where: { $0.id == id }) { selectedID = nil }
    }

    public func requestAccessIfNeeded() async {
        if source.currentAccess() == .notDetermined { _ = await source.requestAccess() }
        reload()
    }

    // MARK: Navigation

    public func goToToday() {
        followsToday = true
        setDay(now())
    }

    public func goToDay(offset: Int) {
        let target = calendar.date(byAdding: .day, value: offset, to: day)!
        followsToday = calendar.isDate(target, inSameDayAs: now())
        setDay(target)
    }

    /// Call on midnight, wake from sleep, or time-zone change.
    public func handleClockChange() {
        let today = calendar.startOfDay(for: now())
        if followsToday && day != today { setDay(today) } else { reload() }
    }

    public func expandRangeToFitAll() {
        rangeOverride = effectiveRange.expanded(toInclude: timedEvents, dayStart: day, calendar: calendar)
    }

    private func setDay(_ date: Date) {
        day = calendar.startOfDay(for: date)
        rangeOverride = nil
        selectedID = nil
        reload()
    }

    // MARK: Editing

    /// An unsaved event in the default calendar, or the first visible writable one.
    /// Nil when no visible calendar accepts new events.
    public func makeDraft(start: Date, end: Date) -> EventItem? {
        let writable = visibleCalendars.filter(\.isWritable)
        let preferred = source.defaultCalendarID()
        guard let calendarID = writable.first(where: { $0.id == preferred })?.id ?? writable.first?.id else {
            return nil
        }
        return EventItem(title: "", start: start, end: end, calendarID: calendarID)
    }

    /// Saves a draft. A draft with a blank title is discarded and nil is returned.
    @discardableResult
    public func create(_ draft: EventItem) -> EventItem? {
        var item = draft.normalized()
        guard !item.title.isEmpty else { return nil }
        item.eventIdentifier = ""
        do {
            let saved = try source.save(item, span: .thisEvent)
            undoManager.registerUndo(withTarget: self) { store in
                MainActor.assumeIsolated { store.delete(saved, span: .thisEvent) }
            }
            undoManager.setActionName("New Event")
            reload()
            selectedID = saved.id
            return saved
        } catch {
            fail(error)
            return nil
        }
    }

    /// Applies an edit, or parks it in `pendingEdit` when a recurring event needs a span choice.
    public func requestUpdate(from original: EventItem, to updated: EventItem) {
        let updated = updated.normalized()
        guard !original.isReadOnly, updated != original else { return }
        if original.isRecurring {
            pendingEdit = PendingEdit(original: original, updated: updated)
        } else {
            update(from: original, to: updated, span: .thisEvent)
        }
    }

    /// Takes the edit explicitly: a dialog may clear `pendingEdit` before its button runs.
    public func confirmEdit(_ edit: PendingEdit, span: EditSpan) {
        pendingEdit = nil
        update(from: edit.original, to: edit.updated, span: span)
    }

    public func cancelPendingEdit() { pendingEdit = nil }

    /// Asks for confirmation (via `pendingDelete`) before deleting.
    public func requestDelete(_ item: EventItem) {
        guard !item.isReadOnly else { return }
        pendingDelete = item
    }

    public func requestDeleteSelected() {
        guard let id = selectedID, let item = timedEvents.first(where: { $0.id == id }) else { return }
        requestDelete(item)
    }

    /// Takes the item explicitly: a dialog may clear `pendingDelete` before its button runs.
    public func confirmDelete(_ item: EventItem, span: EditSpan) {
        pendingDelete = nil
        delete(item, span: span)
    }

    public func cancelPendingDelete() { pendingDelete = nil }

    func update(from original: EventItem, to updated: EventItem, span: EditSpan) {
        do {
            let saved = try source.save(updated, span: span)
            undoManager.registerUndo(withTarget: self) { store in
                MainActor.assumeIsolated {
                    store.update(from: saved, to: saved.withContent(of: original), span: span)
                }
            }
            undoManager.setActionName("Edit Event")
            reload()
        } catch {
            fail(error)
        }
    }

    /// Deleting a recurring event is not undoable: EventKit cannot recreate the series.
    func delete(_ item: EventItem, span: EditSpan) {
        do {
            try source.remove(item, span: span)
            if !item.isRecurring {
                undoManager.registerUndo(withTarget: self) { store in
                    MainActor.assumeIsolated { _ = store.create(item) }
                }
                undoManager.setActionName("Delete Event")
            }
            reload()
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        lastError = error.localizedDescription
        reload()
    }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `./scripts/test.sh 2>&1 | grep -E "✘|Test run"`
Expected: `✔ Test run with 42 tests in 7 suites passed`

- [ ] **Step 6: Commit**

```bash
git add Sources/StickyCalendarCore/EventSource.swift Sources/StickyCalendarCore/CalendarStore.swift Tests/StickyCalendarCoreTests/FakeSource.swift Tests/StickyCalendarCoreTests/CalendarStoreTests.swift
git commit -m "Add event source protocol and calendar store with undo

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: EventKit-backed source

EventKit needs a signed app bundle and a user permission prompt, so this task has no unit tests. It is exercised end to end in Tasks 6 and 8.

**Files:**
- Create: `Sources/StickyCalendarCore/EventKitSource.swift`

**Interfaces:**
- Consumes: `EventSource`, `CalendarAccess`, `EditSpan`, `EventSourceError` (Task 4). `EventItem`, `CalendarInfo`, `RGBA` (Task 1).
- Produces: `@MainActor public final class EventKitSource: EventSource`, created with `init()`.

- [ ] **Step 1: Implement**

`Sources/StickyCalendarCore/EventKitSource.swift`:
```swift
import AppKit
import EventKit

/// The real `EventSource`, backed by the system calendar database.
@MainActor
public final class EventKitSource: EventSource {
    public var onChange: (() -> Void)?

    private var ek = EKEventStore()
    private var observer: NSObjectProtocol?
    private var lastAccess: CalendarAccess

    public init() {
        lastAccess = Self.map(EKEventStore.authorizationStatus(for: .event))
        observe()
    }

    public func currentAccess() -> CalendarAccess {
        let access = Self.map(EKEventStore.authorizationStatus(for: .event))
        // A store created before access was granted (e.g. in System Settings) stays empty.
        if access == .granted && lastAccess != .granted { resetStore() }
        lastAccess = access
        return access
    }

    public func requestAccess() async -> CalendarAccess {
        _ = try? await ek.requestFullAccessToEvents()
        return currentAccess()
    }

    public func calendars() -> [CalendarInfo] {
        ek.calendars(for: .event).map(Self.info)
    }

    public func defaultCalendarID() -> String? {
        ek.defaultCalendarForNewEvents?.calendarIdentifier
    }

    public func events(from start: Date, to end: Date) -> [EventItem] {
        let predicate = ek.predicateForEvents(withStart: start, end: end, calendars: nil)
        return ek.events(matching: predicate).map(Self.item)
    }

    public func save(_ item: EventItem, span: EditSpan) throws -> EventItem {
        let event: EKEvent
        if item.isNew {
            event = EKEvent(eventStore: ek)
        } else {
            guard let found = find(item) else { throw EventSourceError.notFound }
            event = found
        }
        event.title = item.title
        event.startDate = item.start
        event.endDate = item.end
        event.location = item.location
        event.notes = item.notes
        if let calendar = ek.calendar(withIdentifier: item.calendarID) {
            event.calendar = calendar
        } else if event.calendar == nil {
            event.calendar = ek.defaultCalendarForNewEvents
        }
        try ek.save(event, span: span.ek, commit: true)
        return Self.item(event)
    }

    public func remove(_ item: EventItem, span: EditSpan) throws {
        guard let event = find(item) else { throw EventSourceError.notFound }
        try ek.remove(event, span: span.ek, commit: true)
    }

    // MARK: Private

    private func resetStore() {
        ek = EKEventStore()
        observe()
    }

    private func observe() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: ek, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    /// `event(withIdentifier:)` returns the *first* occurrence of a recurring event,
    /// so occurrences are looked up by identifier + occurrence date around that date.
    private func find(_ item: EventItem) -> EKEvent? {
        guard item.isRecurring else { return ek.event(withIdentifier: item.eventIdentifier) }
        let day: TimeInterval = 24 * 60 * 60
        let predicate = ek.predicateForEvents(
            withStart: item.occurrenceDate.addingTimeInterval(-day),
            end: item.occurrenceDate.addingTimeInterval(day),
            calendars: nil
        )
        return ek.events(matching: predicate).first {
            $0.eventIdentifier == item.eventIdentifier && $0.occurrenceDate == item.occurrenceDate
        }
    }

    private static func map(_ status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private static func info(_ calendar: EKCalendar) -> CalendarInfo {
        let color = calendar.color.usingColorSpace(.sRGB)
        return CalendarInfo(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            color: color.map {
                RGBA(red: $0.redComponent, green: $0.greenComponent, blue: $0.blueComponent)
            } ?? .fallback,
            isWritable: calendar.allowsContentModifications
        )
    }

    private static func item(_ event: EKEvent) -> EventItem {
        EventItem(
            eventIdentifier: event.eventIdentifier ?? "",
            externalIdentifier: event.calendarItemExternalIdentifier,
            occurrenceDate: event.occurrenceDate ?? event.startDate,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            location: event.location,
            notes: event.notes,
            isRecurring: event.hasRecurrenceRules || event.isDetached,
            isReadOnly: !(event.calendar?.allowsContentModifications ?? false)
        )
    }
}

private extension EditSpan {
    var ek: EKSpan {
        switch self {
        case .thisEvent: .thisEvent
        case .futureEvents: .futureEvents
        }
    }
}
```

Behaviours to preserve:
- Recurring occurrences are found by `eventIdentifier` plus `occurrenceDate`. `event(withIdentifier:)` would return the first occurrence of the series.
- `currentAccess()` recreates the `EKEventStore` when access switches to granted, because a store created before the grant stays empty.

- [ ] **Step 2: Build with zero warnings**

Run: `swift build 2>&1 | grep -E "warning:|error:" ; swift build 2>&1 | tail -1`
Expected: no warning or error lines, then `Build complete!`

- [ ] **Step 3: Confirm the tests still pass**

Run: `./scripts/test.sh 2>&1 | grep -E "✘|Test run"`
Expected: `✔ Test run with 42 tests in 7 suites passed`

- [ ] **Step 4: Commit**

```bash
git add Sources/StickyCalendarCore/EventKitSource.swift
git commit -m "Add EventKit-backed event source

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: App shell, packaging, settings window, and a first on-screen list

Deliverable: a menu-bar app whose floating sticky shows the date header and a plain list of today's events read from Calendar. Settings work. The app builds as a signed `.app`.

**Files:**
- Create: `Resources/Info.plist`, `scripts/build-app.sh`, `Sources/StickyCalendar/AppDelegate.swift`, `Sources/StickyCalendar/StatusItemController.swift`, `Sources/StickyCalendar/StickyPanel.swift`, `Sources/StickyCalendar/Views/Support.swift`, `Sources/StickyCalendar/Views/HeaderView.swift`, `Sources/StickyCalendar/Views/StatusViews.swift`, `Sources/StickyCalendar/Views/StickyContentView.swift`, `Sources/StickyCalendar/Views/SettingsView.swift`
- Modify: `Sources/StickyCalendar/StickyCalendarApp.swift` (replace the stub)

**Interfaces:**
- Consumes: everything from Core.
- Produces, for Task 7:
  - `StickyContentView(store:settings:)`
  - `HeaderView(store:)`, `AccessDeniedView()`, `ErrorBanner(store:)`
  - `VisualEffectBackground()`, `Color(rgba:)`
  - `SystemLinks.openInCalendar(_:)`, `SystemLinks.openPrivacySettings()`

- [ ] **Step 1: Bundle metadata and build script**

`Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.ievlevpn.StickyCalendar</string>
    <key>CFBundleName</key>
    <string>StickyCalendar</string>
    <key>CFBundleDisplayName</key>
    <string>Sticky Calendar</string>
    <key>CFBundleExecutable</key>
    <string>StickyCalendar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Sticky Calendar shows your events on a floating timeline and lets you edit them.</string>
</dict>
</plist>
```

`scripts/build-app.sh`:
```bash
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
```

Run: `chmod +x scripts/build-app.sh`

- [ ] **Step 2: Entry point, app delegate, status item**

`Sources/StickyCalendar/StickyCalendarApp.swift` (replaces the stub):
```swift
import AppKit

@main
@MainActor
enum StickyCalendarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate // NSApplication holds its delegate weakly
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
```

`Sources/StickyCalendar/AppDelegate.swift`:
```swift
import AppKit
import StickyCalendarCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let source = EventKitSource()
    private lazy var store = CalendarStore(source: source, settings: settings)
    private var panel: StickyPanel?
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()

        let panel = StickyPanel(store: store, settings: settings)
        self.panel = panel
        statusItem = StatusItemController(
            isPanelVisible: { [weak panel] in panel?.isVisible ?? false },
            onToggle: { [weak self] in self?.togglePanel() },
            onSettings: { [weak self] in self?.showSettings() }
        )
        panel.orderFrontRegardless()

        observeClock()
        Task { await store.requestAccessIfNeeded() }
    }

    private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(store: store, settings: settings)
            ))
            window.title = "Sticky Calendar Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func observeClock() {
        let onClockChange: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.store.handleClockChange() }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: onClockChange))
        observers.append(center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: onClockChange))
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: onClockChange
        ))
    }

    /// Accessory apps show no menu bar, but key equivalents still route through the
    /// main menu — without an Edit menu, ⌘C/⌘V/⌘Z would not work in text fields.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Sticky Calendar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)

        return main
    }
}
```

`Sources/StickyCalendar/StatusItemController.swift`:
```swift
import AppKit

/// The menu-bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggleItem = NSMenuItem(title: "Hide Sticky", action: #selector(toggle), keyEquivalent: "")
    private let isPanelVisible: () -> Bool
    private let onToggle: () -> Void
    private let onSettings: () -> Void

    init(isPanelVisible: @escaping () -> Bool, onToggle: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.isPanelVisible = isPanelVisible
        self.onToggle = onToggle
        self.onSettings = onSettings
        super.init()

        item.button?.image = NSImage(systemSymbolName: "calendar.day.timeline.left", accessibilityDescription: "Sticky Calendar")

        let menu = NSMenu()
        menu.delegate = self
        toggleItem.target = self
        menu.addItem(toggleItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sticky Calendar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = isPanelVisible() ? "Hide Sticky" : "Show Sticky"
    }

    @objc private func toggle() { onToggle() }
    @objc private func openSettings() { onSettings() }
}
```

- [ ] **Step 3: The floating panel**

`Sources/StickyCalendar/StickyPanel.swift`:
```swift
import AppKit
import StickyCalendarCore
import SwiftUI

/// The floating sticky window: above other windows, on every Space and over full-screen
/// apps, never activates the app when clicked, remembers its frame.
@MainActor
final class StickyPanel: NSPanel, NSWindowDelegate {
    private static let autosaveName = "StickyPanel"
    private let store: CalendarStore
    private var keyMonitor: Any?

    init(store: CalendarStore, settings: AppSettings) {
        self.store = store
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 520),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false // dragging on the timeline edits events
        backgroundColor = .clear
        isOpaque = false
        minSize = NSSize(width: 220, height: 300)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }

        let hosting = NSHostingView(rootView: StickyContentView(store: store, settings: settings))
        hosting.sizingOptions = [] // let the user resize freely
        contentView = hosting
        delegate = self

        if !setFrameUsingName(Self.autosaveName) { placeTopRight() }
        setFrameAutosaveName(Self.autosaveName)
        installKeyMonitor()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { store.undoManager }

    /// Picks up changes made while we were in the background (e.g. access granted in Settings).
    func windowDidBecomeKey(_ notification: Notification) { store.reload() }

    private func placeTopRight() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 20, y: visible.maxY - frame.height - 20))
    }

    /// ⌫ deletes the selected event, ⌘Z / ⇧⌘Z undo and redo — unless a text field is editing.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.charactersIgnoringModifiers?.lowercased()
            let window = event.window.map(ObjectIdentifier.init)
            let handled = MainActor.assumeIsolated {
                self?.handleKey(keyCode: keyCode, flags: flags, key: key, window: window) ?? false
            }
            return handled ? nil : event
        }
    }

    private func handleKey(keyCode: UInt16, flags: NSEvent.ModifierFlags, key: String?, window: ObjectIdentifier?) -> Bool {
        guard window == ObjectIdentifier(self), !(firstResponder is NSTextView) else { return false }
        switch (keyCode, flags, key) {
        case (51, [], _), (117, [], _), (117, [.function], _): // delete, forward delete
            store.requestDeleteSelected()
        case (_, [.command], "z"):
            store.undoManager.undo()
        case (_, [.command, .shift], "z"):
            store.undoManager.redo()
        default:
            return false
        }
        return true
    }
}
```

- [ ] **Step 4: Shared view support, header, status views**

`Sources/StickyCalendar/Views/Support.swift`:
```swift
import AppKit
import StickyCalendarCore
import SwiftUI

extension Color {
    init(rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

/// Translucent window material that follows light/dark mode.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

@MainActor
enum SystemLinks {
    /// Shows the event in Calendar.app; falls back to just opening Calendar.app.
    static func openInCalendar(_ item: EventItem) {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        if let external = item.externalIdentifier,
           let encoded = external.addingPercentEncoding(withAllowedCharacters: allowed),
           let url = URL(string: "ical://ekevent/\(encoded)?method=show&options=more"),
           NSWorkspace.shared.open(url) {
            return
        }
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Calendar.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    static func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }
}
```

`Sources/StickyCalendar/Views/HeaderView.swift`:
```swift
import StickyCalendarCore
import SwiftUI

struct HeaderView: View {
    let store: CalendarStore

    var body: some View {
        HStack(spacing: 8) {
            Text(store.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if !store.isViewingToday {
                Button("Today") { store.goToToday() }
                    .controlSize(.small)
            }
            Button { store.goToDay(offset: -1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .help("Previous day")
            Button { store.goToDay(offset: 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .help("Next day")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }
}
```

`Sources/StickyCalendar/Views/StatusViews.swift`:
```swift
import StickyCalendarCore
import SwiftUI

struct AccessDeniedView: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Sticky Calendar needs full access to your calendars to show and edit today's events.")
                .font(.callout)
                .multilineTextAlignment(.center)
            Button("Open Privacy Settings") { SystemLinks.openPrivacySettings() }
            Spacer()
        }
        .padding(20)
    }
}

struct ErrorBanner: View {
    let store: CalendarStore

    var body: some View {
        if let message = store.lastError {
            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                .padding(10)
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(4))
                    if store.lastError == message { store.lastError = nil }
                }
        }
    }
}
```

- [ ] **Step 5: First version of the root view, and settings**

`Sources/StickyCalendar/Views/StickyContentView.swift` (Task 7 replaces it):
```swift
import StickyCalendarCore
import SwiftUI

/// Root of the sticky window. First version: header plus a plain list of today's
/// timed events, to prove the window and EventKit plumbing end to end.
struct StickyContentView: View {
    let store: CalendarStore
    let settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(store: store)
            switch store.access {
            case .granted:
                List(store.timedEvents) { item in
                    Text("\(item.start.formatted(date: .omitted, time: .shortened))  \(item.title)")
                }
                .scrollContentBackground(.hidden)
            case .notDetermined:
                Spacer()
                Text("Waiting for Calendar access…").foregroundStyle(.secondary)
                Spacer()
            case .denied:
                AccessDeniedView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground().opacity(settings.opacity))
        .overlay(alignment: .bottom) { ErrorBanner(store: store) }
        .ignoresSafeArea()
    }
}
```

`Sources/StickyCalendar/Views/SettingsView.swift`:
```swift
import ServiceManagement
import StickyCalendarCore
import SwiftUI

struct SettingsView: View {
    let store: CalendarStore
    let settings: AppSettings

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Visible hours") {
                Picker("From", selection: Binding(get: { settings.hourRange.start }, set: settings.setStartHour)) {
                    ForEach(0..<24, id: \.self) { Text(Self.hourLabel($0)).tag($0) }
                }
                Picker("To", selection: Binding(get: { settings.hourRange.end }, set: settings.setEndHour)) {
                    ForEach(1...24, id: \.self) { Text(Self.hourLabel($0)).tag($0) }
                }
            }

            Section("Calendars") {
                if store.calendars.isEmpty {
                    Text("No calendars available.").foregroundStyle(.secondary)
                }
                ForEach(store.calendars) { calendar in
                    Toggle(isOn: Binding(
                        get: { !settings.hiddenCalendarIDs.contains(calendar.id) },
                        set: { visible in
                            settings.setCalendar(calendar.id, visible: visible)
                            store.reload()
                        }
                    )) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(rgba: calendar.color)).frame(width: 9, height: 9)
                            Text(calendar.title)
                        }
                    }
                }
            }

            Section("Appearance") {
                Slider(value: Binding(get: { settings.opacity }, set: settings.setOpacity), in: AppSettings.opacityRange) {
                    Text("Opacity")
                }
            }

            Section {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 480)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private static func hourLabel(_ hour: Int) -> String { String(format: "%02d:00", hour) }
}
```

- [ ] **Step 6: Build with zero warnings, then package**

Run: `swift build 2>&1 | grep -E "warning:|error:"; ./scripts/build-app.sh 2>&1 | tail -1`
Expected: no warning or error lines, then `Built build/StickyCalendar.app`

Run: `codesign -dv build/StickyCalendar.app 2>&1 | grep -E "Identifier|Signature"`
Expected: `Identifier=com.ievlevpn.StickyCalendar` and `Signature=adhoc`

- [ ] **Step 7: Manual check (ask the user to do the clicking)**

Run: `open build/StickyCalendar.app`

Then check each of these:
1. macOS asks for Calendar access. Grant **Full Access**.
2. The sticky appears near the top-right. It has no Dock icon, and the menu bar shows a calendar icon.
3. The header shows today's date, and the list shows today's timed events with their start times.
4. ‹ and › change the day, and "Today" appears once you're off today and brings you back.
5. The menu-bar menu's Hide Sticky / Show Sticky works, and its title updates.
6. The sticky stays above other apps, follows you to another Space, and shows over a full-screen app.
7. Settings…: turning a calendar off removes its events from the list, and the opacity slider changes the background.
8. Quit and reopen: the sticky comes back at the same position and size.
9. Denial path: run `tccutil reset Calendar com.ievlevpn.StickyCalendar`, reopen and deny access. The access-denied view and its button appear, and the button opens Privacy settings. Grant access there, click the sticky, and the events appear.

- [ ] **Step 8: Commit**

```bash
git add Resources scripts/build-app.sh Sources/StickyCalendar
git commit -m "Add menu-bar shell, floating panel, settings, and app packaging

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Interactive timeline, editor popover, and dialogs

Deliverable: the list is replaced by the timeline. It has an hour grid, a past-time wash, a now-line, overlap columns, "+N earlier/later" pills, an all-day strip, drag-to-create, drag-to-move, edge resizing, a double-click popover editor, ⌫ delete with confirmation, recurring-event span dialogs, and undo/redo.

**Files:**
- Create: `Sources/StickyCalendar/Views/AllDayStrip.swift`, `Sources/StickyCalendar/Views/EventEditPopover.swift`, `Sources/StickyCalendar/Views/DayTimelineView.swift`
- Modify: `Sources/StickyCalendar/Views/StickyContentView.swift` (full replacement)

**Interfaces:**
- Consumes: the `CalendarStore` editing API (Task 4), `TimelineGeometry`, `OverlapLayout`, `EventDrag` (Task 2), and `SystemLinks`, `Color(rgba:)`, `HeaderView`, `ErrorBanner`, `AccessDeniedView` (Task 6).
- Produces: `DayTimelineView(store:)`, `EventEditPopover(item:calendars:onFinish:onDelete:onOpenInCalendar:)`, `AllDayStrip(store:)`, `HourGrid`, `EventBlockView`.

- [ ] **Step 1: All-day strip**

`Sources/StickyCalendar/Views/AllDayStrip.swift`:
```swift
import StickyCalendarCore
import SwiftUI

struct AllDayStrip: View {
    let store: CalendarStore

    var body: some View {
        if !store.allDayEvents.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.allDayEvents) { item in
                        let color = Color(rgba: store.calendarInfo(id: item.calendarID)?.color ?? .fallback)
                        Text(item.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(color.opacity(0.3)))
                            .onTapGesture(count: 2) { SystemLinks.openInCalendar(item) }
                            .help("Double-click to open in Calendar")
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 4)
        }
    }
}
```

- [ ] **Step 2: Editor popover**

`Sources/StickyCalendar/Views/EventEditPopover.swift`:
```swift
import StickyCalendarCore
import SwiftUI

/// Quick editor for one event. Commits on close; Esc cancels.
struct EventEditPopover: View {
    let calendars: [CalendarInfo]
    /// Called exactly once when the popover goes away: the edited item, or nil if cancelled.
    let onFinish: (EventItem?) -> Void
    let onDelete: (() -> Void)?
    let onOpenInCalendar: (() -> Void)?

    @State private var item: EventItem
    @State private var cancelled = false
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        item: EventItem,
        calendars: [CalendarInfo],
        onFinish: @escaping (EventItem?) -> Void,
        onDelete: (() -> Void)? = nil,
        onOpenInCalendar: (() -> Void)? = nil
    ) {
        _item = State(initialValue: item)
        self.calendars = calendars
        self.onFinish = onFinish
        self.onDelete = onDelete
        self.onOpenInCalendar = onOpenInCalendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                TextField("New Event", text: $item.title)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .focused($titleFocused)
                    .onSubmit { dismiss() }
                HStack(spacing: 6) {
                    DatePicker("Start", selection: $item.start, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("–")
                    DatePicker("End", selection: $item.end, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                Picker("Calendar", selection: $item.calendarID) {
                    ForEach(calendars) { calendar in
                        Text(calendar.title).tag(calendar.id)
                    }
                }
                TextField("Location", text: optionalText($item.location))
                TextField("Notes", text: optionalText($item.notes), axis: .vertical)
                    .lineLimit(2...5)
            }
            .disabled(item.isReadOnly)

            HStack {
                if let onOpenInCalendar {
                    Button("Open in Calendar") {
                        dismiss()
                        onOpenInCalendar()
                    }
                }
                Spacer()
                if let onDelete, !item.isReadOnly {
                    Button("Delete", role: .destructive) {
                        cancelled = true
                        dismiss()
                        onDelete()
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 270)
        .onAppear { titleFocused = item.isNew }
        .onExitCommand {
            cancelled = true
            dismiss()
        }
        .onDisappear { onFinish(cancelled ? nil : item) }
    }

    private func optionalText(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
```

Contract: `onFinish` is called exactly once, from `onDisappear`. It receives the edited item, or `nil` after Esc or Delete. The caller decides whether that means create, update or nothing.

- [ ] **Step 3: Timeline**

`Sources/StickyCalendar/Views/DayTimelineView.swift`:
```swift
import AppKit
import StickyCalendarCore
import SwiftUI

/// The day's timeline: hour grid, past-time wash, event blocks, now-line, and all
/// direct-manipulation gestures (create, move, resize, select, open editor).
struct DayTimelineView: View {
    let store: CalendarStore

    /// The event being moved or resized, with its live (snapped) times.
    @State private var dragPreview: EventItem?
    /// A new event being dragged out or edited before its first save.
    @State private var draft: EventItem?
    @State private var isDraftEditorOpen = false
    /// The existing event whose editor popover is open.
    @State private var editingID: String?

    private static let space = "timeline"
    private let gutter: CGFloat = 42
    private let trailingInset: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let geo = TimelineGeometry(dayStart: store.day, range: store.effectiveRange, height: proxy.size.height)
            let parts = geo.partition(store.timedEvents)
            let slots = OverlapLayout.columns(for: parts.visible)
            let width = max(proxy.size.width - gutter - trailingInset, 20)

            SwiftUI.TimelineView(.everyMinute) { context in
                ZStack(alignment: .topLeading) {
                    HourGrid(geometry: geo, gutter: gutter)
                    if store.isViewingToday { pastWash(geo, now: context.date, width: width) }
                    creationSurface(geo, width: width)
                    ForEach(parts.visible) { item in
                        block(item, slot: slots[item.id] ?? ColumnSlot(column: 0, count: 1),
                              geo: geo, width: width, now: context.date)
                    }
                    if let draft { draftBlock(draft, geo: geo, width: width) }
                    if store.isViewingToday { nowLine(geo, now: context.date, width: width) }
                }
                .coordinateSpace(name: Self.space)
            }
            .overlay(alignment: .top) { pill(count: parts.earlier.count, label: "earlier").offset(y: -6) }
            .overlay(alignment: .bottom) { pill(count: parts.later.count, label: "later").offset(y: 6) }
            .overlay {
                if store.visibleCalendars.isEmpty {
                    Text("No calendars selected.\nChoose some in Settings.")
                        .multilineTextAlignment(.center)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // MARK: Layers

    private func pastWash(_ geo: TimelineGeometry, now: Date, width: CGFloat) -> some View {
        let y = min(max(CGFloat(geo.y(for: now)), 0), CGFloat(geo.height))
        return Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: width, height: y)
            .offset(x: gutter)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func nowLine(_ geo: TimelineGeometry, now: Date, width: CGFloat) -> some View {
        let y = CGFloat(geo.y(for: now))
        if y >= 0 && y <= CGFloat(geo.height) {
            HStack(spacing: 0) {
                Circle().fill(Color.red).frame(width: 7, height: 7)
                Rectangle().fill(Color.red).frame(height: 1.5)
            }
            .frame(width: width + 4)
            .offset(x: gutter - 4, y: y - 3.5)
            .allowsHitTesting(false)
        }
    }

    /// Empty timeline area: click deselects, drag creates a new event.
    private func creationSurface(_ geo: TimelineGeometry, width: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: width, height: CGFloat(geo.height))
            .offset(x: gutter)
            .onTapGesture { store.selectedID = nil }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        guard !isDraftEditorOpen else { return }
                        let (start, end) = EventDrag.newInterval(
                            from: geo.date(forY: Double(value.startLocation.y)),
                            to: geo.date(forY: Double(value.location.y))
                        )
                        if var current = draft {
                            current.start = start
                            current.end = end
                            draft = current
                        } else if let fresh = store.makeDraft(start: start, end: end) {
                            store.selectedID = nil
                            draft = fresh
                        } else {
                            store.lastError = "No visible calendar accepts new events."
                        }
                    }
                    .onEnded { _ in
                        if draft != nil { isDraftEditorOpen = true }
                    }
            )
    }

    private func block(_ item: EventItem, slot: ColumnSlot, geo: TimelineGeometry, width: CGFloat, now: Date) -> some View {
        let shown = dragPreview.flatMap { $0.id == item.id ? $0 : nil }
            ?? store.pendingEdit.flatMap { $0.original.id == item.id ? $0.updated : nil }
            ?? item
        let frame = geo.frame(for: shown)
        let columnWidth = width / CGFloat(slot.count)
        let color = Color(rgba: store.calendarInfo(id: item.calendarID)?.color ?? .fallback)

        return EventBlockView(
            item: shown,
            color: color,
            isSelected: store.selectedID == item.id,
            isPast: now >= shown.end,
            height: CGFloat(frame.height)
        )
        .frame(width: max(columnWidth - 2, 4), height: CGFloat(frame.height))
        .overlay(alignment: .top) { resizeHandle(item, .resizeStart, geo: geo) }
        .overlay(alignment: .bottom) { resizeHandle(item, .resizeEnd, geo: geo) }
        .gesture(dragGesture(item, .move, geo: geo))
        .onTapGesture(count: 2) { editingID = item.id }
        .onTapGesture { store.selectedID = item.id }
        .popover(
            isPresented: Binding(get: { editingID == item.id }, set: { if !$0 { editingID = nil } }),
            arrowEdge: .leading
        ) {
            EventEditPopover(
                item: item,
                calendars: editorCalendars(for: item),
                onFinish: { result in
                    if let result { store.requestUpdate(from: item, to: result) }
                },
                onDelete: { store.requestDelete(item) },
                onOpenInCalendar: { SystemLinks.openInCalendar(item) }
            )
        }
        .offset(x: gutter + CGFloat(slot.column) * columnWidth, y: CGFloat(frame.top))
    }

    private func draftBlock(_ item: EventItem, geo: TimelineGeometry, width: CGFloat) -> some View {
        let frame = geo.frame(for: item)
        let color = Color(rgba: store.calendarInfo(id: item.calendarID)?.color ?? .fallback)
        return EventBlockView(item: item, color: color, isSelected: true, isPast: false, height: CGFloat(frame.height))
            .frame(width: width, height: CGFloat(frame.height))
            .popover(
                isPresented: Binding(get: { isDraftEditorOpen }, set: { if !$0 { isDraftEditorOpen = false } }),
                arrowEdge: .leading
            ) {
                EventEditPopover(
                    item: item,
                    calendars: editorCalendars(for: item),
                    onFinish: { result in
                        draft = nil
                        if let result { store.create(result) }
                    }
                )
            }
            .offset(x: gutter, y: CGFloat(frame.top))
    }

    @ViewBuilder
    private func resizeHandle(_ item: EventItem, _ kind: DragKind, geo: TimelineGeometry) -> some View {
        if !item.isReadOnly {
            Color.clear
                .frame(height: 6)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                }
                .gesture(dragGesture(item, kind, geo: geo))
        }
    }

    private func dragGesture(_ item: EventItem, _ kind: DragKind, geo: TimelineGeometry) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard !item.isReadOnly else { return }
                store.selectedID = item.id
                let delta = Double(value.translation.height) / geo.pointsPerSecond
                dragPreview = EventDrag.apply(kind, to: item, delta: delta)
            }
            .onEnded { _ in
                guard let preview = dragPreview else { return }
                dragPreview = nil
                store.requestUpdate(from: item, to: preview)
            }
    }

    @ViewBuilder
    private func pill(count: Int, label: String) -> some View {
        if count > 0 {
            Button { store.expandRangeToFitAll() } label: {
                Text("+\(count) \(label)")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
            .buttonStyle(.plain)
            .help("Show all of today's events")
        }
    }

    /// Writable calendars, plus the event's own calendar so the picker can show it.
    private func editorCalendars(for item: EventItem) -> [CalendarInfo] {
        store.calendars.filter { $0.isWritable || $0.id == item.calendarID }
    }
}

struct HourGrid: View {
    let geometry: TimelineGeometry
    let gutter: CGFloat

    var body: some View {
        Canvas { context, size in
            let range = geometry.range
            for hour in range.start...range.end {
                let y = CGFloat(geometry.y(forHour: hour))
                var line = Path()
                line.move(to: CGPoint(x: gutter, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.secondary.opacity(0.35)), lineWidth: 0.5)

                let label = Text(String(format: "%02d:00", hour))
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                context.draw(context.resolve(label), at: CGPoint(x: gutter - 6, y: y), anchor: .trailing)

                if hour < range.end {
                    let mid = (y + CGFloat(geometry.y(forHour: hour + 1))) / 2
                    var half = Path()
                    half.move(to: CGPoint(x: gutter, y: mid))
                    half.addLine(to: CGPoint(x: size.width, y: mid))
                    context.stroke(half, with: .color(.secondary.opacity(0.15)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct EventBlockView: View {
    let item: EventItem
    let color: Color
    let isSelected: Bool
    let isPast: Bool
    let height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        VStack(alignment: .leading, spacing: 1) {
            Text(item.title.isEmpty ? "New Event" : item.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(height > 34 ? 2 : 1)
            if height > 28 {
                Text("\(item.start.formatted(date: .omitted, time: .shortened)) – \(item.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if height > 46, let location = item.location, !location.isEmpty {
                Text(location)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .padding(.vertical, height > 20 ? 3 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(color.opacity(isSelected ? 0.45 : 0.25)))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(color, lineWidth: isSelected ? 1.5 : 0))
        .opacity(isPast ? 0.5 : 1)
    }
}
```

Points to preserve:
- Every drag uses the named coordinate space `"timeline"`. The block moves while it's being dragged, so a local coordinate space would make the translation jitter.
- A block shows `dragPreview` while it's being dragged. While a repeating event waits in the span dialog, it shows `store.pendingEdit.updated`, so it doesn't jump back.
- Column slots come from the stored events, not the preview, so neighbouring events don't reflow mid-drag.

- [ ] **Step 4: Root view with timeline and dialogs**

`Sources/StickyCalendar/Views/StickyContentView.swift` (full replacement):
```swift
import StickyCalendarCore
import SwiftUI

/// Root of the sticky window: header, all-day strip, timeline, plus dialogs and error banner.
struct StickyContentView: View {
    let store: CalendarStore
    let settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(store: store)
            switch store.access {
            case .granted:
                AllDayStrip(store: store)
                DayTimelineView(store: store)
            case .notDetermined:
                Spacer()
                Text("Waiting for Calendar access…").foregroundStyle(.secondary)
                Spacer()
            case .denied:
                AccessDeniedView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground().opacity(settings.opacity))
        .overlay(alignment: .bottom) { ErrorBanner(store: store) }
        .ignoresSafeArea()
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { store.pendingDelete != nil }, set: { if !$0 { store.cancelPendingDelete() } }),
            titleVisibility: .visible,
            presenting: store.pendingDelete
        ) { item in
            if item.isRecurring {
                Button("Delete This Event Only", role: .destructive) { store.confirmDelete(item, span: .thisEvent) }
                Button("Delete All Future Events", role: .destructive) { store.confirmDelete(item, span: .futureEvents) }
            } else {
                Button("Delete", role: .destructive) { store.confirmDelete(item, span: .thisEvent) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            if item.isRecurring { Text("Deleting a repeating event can't be undone.") }
        }
        .confirmationDialog(
            "This is a repeating event.",
            isPresented: Binding(get: { store.pendingEdit != nil }, set: { if !$0 { store.cancelPendingEdit() } }),
            titleVisibility: .visible,
            presenting: store.pendingEdit
        ) { edit in
            Button("Change This Event Only") { store.confirmEdit(edit, span: .thisEvent) }
            Button("Change All Future Events") { store.confirmEdit(edit, span: .futureEvents) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var deleteTitle: String {
        let title = store.pendingDelete?.title ?? ""
        return title.isEmpty ? "Delete this event?" : "Delete “\(title)”?"
    }
}
```

The dialogs use `presenting:` and pass the item to `confirmDelete`/`confirmEdit` explicitly. They must never read `store.pendingDelete` inside a button action (see Review Focus).

- [ ] **Step 5: Build with zero warnings, run the tests, package**

Run: `swift build 2>&1 | grep -E "warning:|error:"; ./scripts/test.sh 2>&1 | grep -E "✘|Test run"; ./scripts/build-app.sh 2>&1 | tail -1`
Expected: no warning or error lines, `✔ Test run with 42 tests in 7 suites passed`, `Built build/StickyCalendar.app`

- [ ] **Step 6: Manual check**

Run: `open build/StickyCalendar.app` (quit the running copy first from its menu).

Check:
1. The timeline shows 08:00–20:00 with events at the right heights, and overlapping events sit side by side.
2. The now-line is red and on the current time, and the time above it is washed grey.
3. Drag on an empty area. A block follows your drag, snapping to 15 minutes. On release a popover opens with the title focused. Type a title and press Return, and the event is created (it also appears in Calendar.app). Try again but leave the title empty and press Esc, and nothing is created.
4. Drag an event body and it moves in 15-minute steps. Drag its top or bottom edge and it resizes, with a resize cursor on hover.
5. Double-click an event. Change the title and location, then click outside, and it's saved. Double-click again and press Esc, and nothing changes. "Open in Calendar" shows the event in Calendar.app.
6. Select an event, press ⌫, then Delete, and it's gone. ⌘Z brings it back and ⇧⌘Z deletes it again.
7. On a repeating event, move it and choose "This Event Only". Only that occurrence moves. ⌘Z restores it.
8. An event on a read-only calendar (e.g. a subscribed holiday calendar) can't be dragged, and its popover fields are disabled.
9. Create an event at 06:00 in Calendar.app. A "+1 earlier" pill appears within about a second, and clicking it stretches the range to 06:00.
10. All-day events appear as chips under the header, and double-clicking one opens Calendar.

- [ ] **Step 7: Commit**

```bash
git add Sources/StickyCalendar/Views
git commit -m "Add interactive timeline with drag editing, popover editor, and dialogs

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: End-to-end verification, launch at login, install

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README**

`README.md`:
````markdown
# Sticky Calendar

A tiny menu-bar app that shows the day's calendar as a floating, always-on-top timeline.
Drag to create, move and resize events; double-click to edit; ⌫ to delete; ⌘Z to undo.

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
````

- [ ] **Step 2: Install and enable launch at login**

Run: `./scripts/build-app.sh --install && open ~/Applications/StickyCalendar.app`
Then in Settings…, turn on "Launch at login". Expected: the toggle stays on and no error text appears. Log out and back in (or restart), and the sticky appears.

- [ ] **Step 3: Clock checks**

1. Leave the sticky on today across midnight, or change the time zone in System Settings to make the date roll over. The view follows to the new day.
2. Navigate to tomorrow, then sleep and wake the Mac. It stays on the day you chose.

- [ ] **Step 4: Final automated checks**

Run: `swift build 2>&1 | grep -E "warning:|error:"; ./scripts/test.sh 2>&1 | grep -E "✘|Test run"; du -sh build/StickyCalendar.app`
Expected: no warning or error lines, 42 tests passed, and an app size of about 1 MB.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "Add README

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
