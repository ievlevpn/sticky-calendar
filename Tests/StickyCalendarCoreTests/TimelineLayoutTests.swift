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
