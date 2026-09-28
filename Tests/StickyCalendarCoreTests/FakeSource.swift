import Foundation
@testable import StickyCalendarCore

struct FakeError: LocalizedError {
    var errorDescription: String? { "Calendar is read-only" }
}

@MainActor
final class FakeSource: EventSource {
    var onChange: (() -> Void)?
    var access: CalendarAccess = .granted
    var cals = [
        CalendarInfo(id: "work", title: "Work"),
        CalendarInfo(id: "home", title: "Home"),
        CalendarInfo(id: "holidays", title: "Holidays", isWritable: false),
    ]
    var defaultID: String? = "work"
    var stored: [EventItem] = []
    var failNextWrite = false
    private(set) var spans: [EditSpan] = []
    private var nextID = 1

    func currentAccess() -> CalendarAccess { access }

    func requestAccess() async -> CalendarAccess {
        access = .granted
        return access
    }

    func calendars() -> [CalendarInfo] { cals }

    func defaultCalendarID() -> String? { defaultID }

    func events(from start: Date, to end: Date) -> [EventItem] {
        stored.filter { $0.start < end && ($0.end > start || $0.start == start) }
    }

    func save(_ item: EventItem, span: EditSpan) throws -> EventItem {
        try checkFailure()
        spans.append(span)
        var saved = item
        if item.isNew {
            saved.eventIdentifier = "e\(nextID)"
            saved.occurrenceDate = item.start
            nextID += 1
            stored.append(saved)
        } else {
            guard let i = stored.firstIndex(where: { $0.id == item.id }) else {
                throw EventSourceError.notFound
            }
            stored[i] = saved
        }
        return saved
    }

    func remove(_ item: EventItem, span: EditSpan) throws {
        try checkFailure()
        spans.append(span)
        guard let i = stored.firstIndex(where: { $0.id == item.id }) else {
            throw EventSourceError.notFound
        }
        stored.remove(at: i)
    }

    private func checkFailure() throws {
        if failNextWrite {
            failNextWrite = false
            throw FakeError()
        }
    }
}
