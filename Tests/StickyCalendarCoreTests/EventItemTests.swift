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
