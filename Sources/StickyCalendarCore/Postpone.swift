import Foundation

/// Quick ways to push a reminder back. Hours count from now (so an overdue reminder lands in
/// the future) and give it a time; days keep its time, or keep it date-only.
public enum Postpone: CaseIterable, Sendable {
    case oneHour, threeHours, tomorrow, nextWeek

    public struct Due: Equatable, Sendable {
        public let date: Date
        public let hasTime: Bool
    }

    public var title: String {
        switch self {
        case .oneHour: "In 1 Hour"
        case .threeHours: "In 3 Hours"
        case .tomorrow: "Tomorrow"
        case .nextWeek: "Next Week"
        }
    }

    /// Short, for the editor's buttons.
    public var shortTitle: String {
        switch self {
        case .oneHour: "+1 h"
        case .threeHours: "+3 h"
        case .tomorrow: "Tomorrow"
        case .nextWeek: "Next week"
        }
    }

    /// "+1 h" and "+3 h": they need a source whose due dates have times.
    public var isHours: Bool { self == .oneHour || self == .threeHours }

    /// The new due date for a reminder due at `due` (nil: none), timed or not.
    public func due(from due: Date?, hasTime: Bool, now: Date, calendar: Calendar) -> Due {
        switch self {
        case .oneHour, .threeHours:
            let minute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
            let hours = self == .oneHour ? 1 : 3
            return Due(date: calendar.date(byAdding: .hour, value: hours, to: minute)!, hasTime: true)
        case .tomorrow, .nextWeek:
            let today = calendar.startOfDay(for: now)
            let day = calendar.date(byAdding: .day, value: self == .tomorrow ? 1 : 7, to: today)!
            guard hasTime, let due else { return Due(date: day, hasTime: false) }
            let time = calendar.dateComponents([.hour, .minute], from: due)
            let date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
            return Due(date: date, hasTime: true)
        }
    }
}
