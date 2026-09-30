import Foundation
@testable import StickyCalendarCore

@MainActor
final class FakeReminderSource: ReminderSource {
    var onChange: (() -> Void)?
    var access: CalendarAccess = .granted
    var storedLists = [
        ReminderListInfo(id: "home", title: "Home"),
        ReminderListInfo(id: "work", title: "Work"),
        ReminderListInfo(id: "shared", title: "Shared", isWritable: false),
    ]
    var defaultID: String? = "home"
    var stored: [ReminderItem] = []
    var failNextSave = false
    var canEditNotes = true
    /// Repeat daily, as Todoist's do: completing one moves it to the next day, still open.
    var repeatingIDs: Set<String> = []
    /// Lag like Todoist: this many reads after the next change still see what was there before it.
    var staleReads = 0
    private var stale: [ReminderItem]?
    private var nextID = 1

    func currentAccess() -> CalendarAccess { access }
    func requestAccess() async -> CalendarAccess { access = .granted; return access }
    func lists() -> [ReminderListInfo] { storedLists }
    func defaultListID() -> String? { defaultID }

    func reminders(completedSince: Date) async -> [ReminderItem] {
        var shown = stored
        if let stale, staleReads > 0 {
            shown = stale
            staleReads -= 1
            if staleReads == 0 { self.stale = nil }
        }
        return shown.filter { !$0.isCompleted || ($0.completionDate ?? .distantPast) >= completedSince }
    }

    func save(_ item: ReminderItem) throws -> ReminderItem {
        if failNextSave {
            failNextSave = false
            throw ReminderSourceError("Couldn't save")
        }
        if staleReads > 0, stale == nil { stale = stored }
        var saved = item
        if item.isNew {
            saved.id = "r\(nextID)"
            nextID += 1
            stored.append(saved)
        } else {
            guard let i = stored.firstIndex(where: { $0.id == item.id }) else { throw EventSourceError.notFound }
            // Like TodoistSource: answers with what it sent, whatever the server made of it.
            if repeatingIDs.contains(item.id), item.isCompleted, !stored[i].isCompleted {
                stored[i].due = stored[i].due.map { $0.addingTimeInterval(86400) }
                return saved
            }
            stored[i] = saved
        }
        return saved
    }

    func link(for item: ReminderItem) -> URL? { URL(string: "fake://\(item.id)") }

    func remove(_ item: ReminderItem) throws {
        if staleReads > 0, stale == nil { stale = stored }
        guard let i = stored.firstIndex(where: { $0.id == item.id }) else { throw EventSourceError.notFound }
        stored.remove(at: i)
    }
}
