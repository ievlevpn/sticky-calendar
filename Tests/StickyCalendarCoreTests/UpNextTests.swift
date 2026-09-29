import Foundation
import Testing
@testable import StickyCalendarCore

struct UpNextTests {
    @Test func prefersWhatIsOnNowThenWhatStartsNext() {
        let events = [event("a", at(9), at(10)), event("b", at(10, 30), at(12)), event("c", at(13), at(14))]
        #expect(UpNext.pick(from: events, now: at(11)) == UpNext(item: events[1], isOngoing: true))
        #expect(UpNext.pick(from: events, now: at(12, 15)) == UpNext(item: events[2], isOngoing: false))
        #expect(UpNext.pick(from: events, now: at(15)) == nil)
    }

    @Test func ofSeveralOngoingTheFirstToEndWins() {
        let events = [event("long", at(9), at(17)), event("short", at(10), at(11))]
        #expect(UpNext.pick(from: events, now: at(10, 30))?.item.eventIdentifier == "short")
    }

    @Test func ignoresAllDayEvents() {
        #expect(UpNext.pick(from: [event("x", at(0), at(0, day: 29), allDay: true)], now: at(10)) == nil)
    }

    @Test func progressFillsFromStartToEnd() {
        let meeting = UpNext(item: event("m", at(10), at(11)), isOngoing: true)
        #expect(meeting.progress(at: at(9, 50)) == 0)
        #expect(meeting.progress(at: at(10)) == 0)
        #expect(meeting.progress(at: at(10, 15)) == 0.25)
        #expect(meeting.progress(at: at(11, 30)) == 1)
        #expect(UpNext(item: event("z", at(10), at(10)), isOngoing: false).progress(at: at(9)) == 0)
    }
}
