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
    private var nextID = 1

    func currentAccess() -> CalendarAccess { access }
    func requestAccess() async -> CalendarAccess { access = .granted; return access }
    func lists() -> [ReminderListInfo] { storedLists }
    func defaultListID() -> String? { defaultID }

    func reminders(completedSince: Date) async -> [ReminderItem] {
        stored.filter { !$0.isCompleted || ($0.completionDate ?? .distantPast) >= completedSince }
    }

    func save(_ item: ReminderItem) throws -> ReminderItem {
        var saved = item
        if item.isNew {
            saved.id = "r\(nextID)"
            nextID += 1
            stored.append(saved)
        } else {
            guard let i = stored.firstIndex(where: { $0.id == item.id }) else { throw EventSourceError.notFound }
            stored[i] = saved
        }
        return saved
    }

    func remove(_ item: ReminderItem) throws {
        guard let i = stored.firstIndex(where: { $0.id == item.id }) else { throw EventSourceError.notFound }
        stored.remove(at: i)
    }
}
