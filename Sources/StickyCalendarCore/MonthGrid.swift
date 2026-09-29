import Foundation

/// The days a month picker shows: whole weeks, starting on the calendar's first weekday,
/// from the week holding the 1st to the week holding the last day.
public enum MonthGrid {
    public static func days(of month: Date, calendar: Calendar) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let last = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let trail = (calendar.firstWeekday + 6 - calendar.component(.weekday, from: last)) % 7
        let start = calendar.date(byAdding: .day, value: -lead, to: first)!
        let count = lead + calendar.range(of: .day, in: .month, for: month)!.count + trail
        return (0..<count).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    /// Weekday initials in the grid's order ("M", "T", "W"…).
    public static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }
}
