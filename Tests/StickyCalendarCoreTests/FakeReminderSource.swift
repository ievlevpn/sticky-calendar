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
    var supportsTime = true
    var supportsPriority = true
    /// Repeat daily, as Todoist's do: completing one moves it to the next day, still open.
    var repeatingIDs: Set<String> = []
    /// Pause the next read between its open and its completed reminders (Todoist reads them
    /// in separate requests), or the next save after storing, before it answers.
    var pauseNextRead = false
    var pauseNextSave = false
    private(set) var pausedRead: CheckedContinuation<Void, Never>?
    private(set) var pausedSave: CheckedContinuation<Void, Never>?

    func resumeRead() { pausedRead?.resume(); pausedRead = nil }
    func resumeSave() { pausedSave?.resume(); pausedSave = nil }
    private var nextID = 1

    func currentAccess() -> CalendarAccess { access }
    func requestAccess() async -> CalendarAccess { access = .granted; return access }
    func lists() -> [ReminderListInfo] { storedLists }
    func defaultListID() -> String? { defaultID }

    func reminders(completedSince: Date) async -> [ReminderItem] {
        if pauseNextRead {
            pauseNextRead = false
            let open = stored.filter { !$0.isCompleted }
            await withCheckedContinuation { pausedRead = $0 }
            return open + stored.filter { $0.isCompleted && ($0.completionDate ?? .distantPast) >= completedSince }
        }
        return stored.filter { !$0.isCompleted || ($0.completionDate ?? .distantPast) >= completedSince }
    }

    func save(_ item: ReminderItem) async throws -> ReminderItem {
        let saved = try store(item)
        if pauseNextSave {
            pauseNextSave = false
            await withCheckedContinuation { pausedSave = $0 }
        }
        return saved
    }

    private func store(_ item: ReminderItem) throws -> ReminderItem {
        if failNextSave {
            failNextSave = false
            throw ReminderSourceError("Couldn't save")
        }
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
        guard let i = stored.firstIndex(where: { $0.id == item.id }) else { throw EventSourceError.notFound }
        stored.remove(at: i)
    }
}
