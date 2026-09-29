import Foundation
import Testing
@testable import StickyCalendarCore

struct CalendarScriptTests {
    @Test func showsTheGivenDayInDayView() {
        let script = CalendarScript.showDay(at(15, 30, day: 30), calendar: utc)
        #expect(script.contains("tell application \"Calendar\""))
        #expect(script.contains("switch view to day view"))
        #expect(script.contains("set year of d to 2026"))
        #expect(script.contains("set month of d to 9"))
        #expect(script.contains("set day of d to 30"))
        #expect(script.contains("view calendar at d"))
    }

    @Test func setsDayToOneBeforeChangingMonthSoItCannotOverflow() {
        // Today may be the 31st; setting month to September first would roll over to October.
        let script = CalendarScript.showDay(at(9, day: 30), calendar: utc)
        let lines = script.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let dayOne = lines.firstIndex(of: "set day of d to 1")
        let month = lines.firstIndex(of: "set month of d to 9")
        let day = lines.firstIndex(of: "set day of d to 30")
        #expect(dayOne != nil && month != nil && day != nil)
        #expect(dayOne! < month! && month! < day!)
    }

    @Test func usesTheCalendarsNotionOfTheDate() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 2026-09-30 20:00 UTC is already Oct 1 in Tokyo.
        let script = CalendarScript.showDay(at(20, day: 30), calendar: tokyo)
        #expect(script.contains("set month of d to 10"))
        let lines = script.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.filter { $0 == "set day of d to 1" }.count == 2) // overflow guard + the real day
    }

    @Test func usesGregorianYearsWhateverTheSystemCalendar() {
        // AppleScript dates are Gregorian; a Buddhist system calendar says 2569 for 2026.
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "UTC")!
        let script = CalendarScript.showDay(at(12, day: 30), calendar: buddhist)
        #expect(script.contains("set year of d to 2026"))
        #expect(script.contains("set month of d to 9"))
        #expect(script.contains("set day of d to 30"))
    }
}
