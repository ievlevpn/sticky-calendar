import Foundation
import Testing
@testable import StickyCalendarCore

struct TimelineGeometryTests {
    let g = TimelineGeometry(dayStart: at(0), pointsPerHour: 50, calendar: utc)

    @Test func coversTheWholeDayAtAFixedScale() {
        #expect(g.height == 1200)
        #expect(g.y(for: at(0)) == 0)
        #expect(g.y(for: at(14)) == 700)
        #expect(g.date(forY: 700) == at(14))
        #expect(g.y(forHour: 9) == 450)
        #expect(g.y(forHour: 24) == 1200)
    }

    @Test func scaleDoesNotDependOnWindowSize() {
        let dense = TimelineGeometry(dayStart: at(0), pointsPerHour: 48, calendar: utc)
        #expect(dense.y(for: at(1)) == 48)
        #expect(dense.height == 48 * 24)
    }

    @Test func frameClipsEventsCrossingMidnightToTheDay() {
        let late = g.frame(for: event("late", at(23), at(1, day: 29)))
        #expect(late.top == 1150 && late.height == 50)
        let early = g.frame(for: event("early", at(22, day: 27), at(1)))
        #expect(early.top == 0 && early.height == 50)
        let tiny = g.frame(for: event("tiny", at(10), at(10, 5)))
        #expect(tiny.height == 14)
    }

    @Test func dstDayUsesRealElapsedTime() {
        var zurich = Calendar(identifier: .gregorian)
        zurich.timeZone = TimeZone(identifier: "Europe/Zurich")!
        // 2026-03-29: clocks jump 02:00 -> 03:00, so the day is 23 hours long.
        let day = zurich.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        let g = TimelineGeometry(dayStart: day, pointsPerHour: 10, calendar: zurich)
        let threeAM = zurich.date(bySettingHour: 3, minute: 0, second: 0, of: day)!
        #expect(abs(g.y(for: threeAM) - 20) < 0.001) // 2 real hours at 10 pt/hour
        #expect(abs(g.height - 230) < 0.001)
        #expect(abs(g.y(forHour: 24) - 230) < 0.001)
    }

    @Test func tellsWhetherATimeIsInTheScrolledViewport() {
        // Viewport shows 08:00–18:00 (y 400...900).
        #expect(g.isVisible(at(12), scrollOffset: 400, viewportHeight: 500))
        #expect(!g.isVisible(at(7), scrollOffset: 400, viewportHeight: 500))
        #expect(!g.isVisible(at(19), scrollOffset: 400, viewportHeight: 500))
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
