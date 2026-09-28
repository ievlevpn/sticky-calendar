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
