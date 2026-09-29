import AppKit
import EventKit

/// The real `ReminderSource`, backed by the system reminders database. Reminders access is
/// separate from calendar access and asked for the first time the reminders view opens.
@MainActor
public final class ReminderKitSource: ReminderSource {
    public var onChange: (() -> Void)?

    private var ek = EKEventStore()
    private var observer: NSObjectProtocol?
    private var lastAccess: CalendarAccess
    private let calendar = Calendar.autoupdatingCurrent

    public init() {
        lastAccess = Self.map(EKEventStore.authorizationStatus(for: .reminder))
        observe()
    }

    public func currentAccess() -> CalendarAccess {
        let access = Self.map(EKEventStore.authorizationStatus(for: .reminder))
        // A store created before access was granted (e.g. in System Settings) stays empty.
        if access == .granted && lastAccess != .granted { resetStore() }
        lastAccess = access
        return access
    }

    public func requestAccess() async -> CalendarAccess {
        _ = try? await ek.requestFullAccessToReminders()
        return currentAccess()
    }

    public func lists() -> [ReminderListInfo] {
        ek.calendars(for: .reminder).map(Self.info)
    }

    public func defaultListID() -> String? {
        ek.defaultCalendarForNewReminders()?.calendarIdentifier
    }

    public func reminders(completedSince: Date) async -> [ReminderItem] {
        let incomplete = ek.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let completed = ek.predicateForCompletedReminders(withCompletionDateStarting: completedSince, ending: nil, calendars: nil)
        async let open = fetch(incomplete)
        async let done = fetch(completed)
        return await open + done
    }

    public func save(_ item: ReminderItem) throws -> ReminderItem {
        let reminder: EKReminder
        if item.isNew {
            reminder = EKReminder(eventStore: ek)
        } else {
            guard let found = ek.calendarItem(withIdentifier: item.id) as? EKReminder else { throw EventSourceError.notFound }
            reminder = found
        }
        if let list = ek.calendar(withIdentifier: item.listID) { reminder.calendar = list }
        reminder.title = item.title
        // Only touch the due date when it changed, so re-saving never shifts it.
        let current = Self.due(of: reminder, calendar: calendar)
        if item.isNew || current.date != item.due || current.hasTime != item.dueHasTime {
            reminder.dueDateComponents = item.due.map { date in
                var parts = calendar.dateComponents(
                    item.dueHasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: date
                )
                parts.calendar = calendar
                if item.dueHasTime { parts.timeZone = calendar.timeZone }
                return parts
            }
            // Like Reminders.app: a new reminder with a time alerts at that time.
            if item.isNew, item.dueHasTime, let due = item.due {
                reminder.addAlarm(EKAlarm(absoluteDate: due))
            }
        }
        if reminder.isCompleted != item.isCompleted { reminder.isCompleted = item.isCompleted }
        try ek.save(reminder, commit: true)
        return Self.item(reminder, calendar: calendar)
    }

    public func remove(_ item: ReminderItem) throws {
        guard let reminder = ek.calendarItem(withIdentifier: item.id) as? EKReminder else { throw EventSourceError.notFound }
        try ek.remove(reminder, commit: true)
    }

    // MARK: Private

    /// EventKit calls back on a background queue; the reminders are turned into values there.
    private func fetch(_ predicate: NSPredicate) async -> [ReminderItem] {
        let calendar = calendar
        return await withCheckedContinuation { continuation in
            ek.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map { Self.item($0, calendar: calendar) })
            }
        }
    }

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

    private static func map(_ status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private static func info(_ list: EKCalendar) -> ReminderListInfo {
        let color = list.color.usingColorSpace(.sRGB)
        return ReminderListInfo(
            id: list.calendarIdentifier,
            title: list.title,
            color: color.map { RGBA(red: $0.redComponent, green: $0.greenComponent, blue: $0.blueComponent) } ?? .fallback,
            isWritable: list.allowsContentModifications
        )
    }

    private nonisolated static func due(of reminder: EKReminder, calendar: Calendar) -> (date: Date?, hasTime: Bool) {
        guard var parts = reminder.dueDateComponents else { return (nil, false) }
        if parts.calendar == nil { parts.calendar = calendar }
        return (parts.date ?? calendar.date(from: parts), parts.hour != nil)
    }

    private nonisolated static func item(_ reminder: EKReminder, calendar: Calendar) -> ReminderItem {
        let due = due(of: reminder, calendar: calendar)
        return ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            listID: reminder.calendar?.calendarIdentifier ?? "",
            due: due.date,
            dueHasTime: due.hasTime,
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate
        )
    }
}
