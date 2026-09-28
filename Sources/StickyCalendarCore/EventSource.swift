import Foundation

public enum CalendarAccess: Equatable, Sendable {
    case notDetermined, granted, denied
}

/// Which occurrences of a recurring event an edit applies to.
public enum EditSpan: Sendable {
    case thisEvent, futureEvents
}

public enum EventSourceError: LocalizedError {
    case notFound

    public var errorDescription: String? {
        switch self {
        case .notFound: "The event no longer exists."
        }
    }
}

/// Everything the store needs from a calendar backend. `EventKitSource` is the real one;
/// tests use an in-memory fake.
@MainActor
public protocol EventSource: AnyObject {
    /// Called whenever the underlying calendar database changes (including our own saves).
    var onChange: (() -> Void)? { get set }
    func currentAccess() -> CalendarAccess
    func requestAccess() async -> CalendarAccess
    func calendars() -> [CalendarInfo]
    func defaultCalendarID() -> String?
    /// Events overlapping `[start, end)`, including all-day and multi-day events.
    func events(from start: Date, to end: Date) -> [EventItem]
    /// Creates the event if `item.isNew`, otherwise updates it. Returns the saved state.
    func save(_ item: EventItem, span: EditSpan) throws -> EventItem
    func remove(_ item: EventItem, span: EditSpan) throws
}
