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
