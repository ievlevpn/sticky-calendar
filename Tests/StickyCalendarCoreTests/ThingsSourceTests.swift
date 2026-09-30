import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
final class FakeThings: ThingsScripting {
    var running = true
    var launches = 0
    var snapshot = ThingsSnapshot()
    var failure: ThingsFailure?
    var calls: [String] = []

    func isRunning() -> Bool { running }
    func launch() async { launches += 1; running = true }
    func snapshot(completedSince: Date) async throws -> ThingsSnapshot {
        if let failure { throw failure }
        return snapshot
    }
    func setStatus(id: String, completed: Bool) async throws { calls.append("status \(id) \(completed)") }
    func setName(id: String, name: String) async throws { calls.append("name \(id) \(name)") }
    func setNotes(id: String, notes: String) async throws { calls.append("notes \(id) \(notes)") }
    func schedule(id: String, on day: Date?) async throws { calls.append("schedule \(id) \(day.map { "\($0)" } ?? "anytime")") }
    func create(name: String, notes: String?, in container: ThingsContainer, on day: Date?) async throws -> String {
        calls.append("create \(name) \(container) \(day.map { "\($0)" } ?? "-")")
        return "new1"
    }
    func delete(id: String) async throws { calls.append("delete \(id)") }
}

@MainActor
struct ThingsSourceTests {
    let things = FakeThings()
    let source: ThingsSource

    init() {
        source = ThingsSource(things: things, calendar: utc, now: { at(12) })
        things.snapshot = ThingsSnapshot(
            open: [
                .init(id: "a", name: "Water plants", when: at(0, day: 26)),           // past When → today
                .init(id: "b", name: "Report", when: at(0, day: 30), deadline: at(0, day: 29)),
                .init(id: "c", name: "Someday idea"),
                .init(id: "d", name: "Call Sam", when: at(0)),                       // no project, not Inbox
            ],
            done: [.init(id: "e", name: "Shop", status: "completed", when: at(0), completed: at(9))],
            inbox: ["c"],
            lists: [.init(id: "p1", name: "Work", kind: "project", toDoIDs: ["b"]),
                    .init(id: "ar1", name: "Home", kind: "area", toDoIDs: ["a", "e"])]
        )
    }

    @Test func mapsWhenDeadlinesAndLists() async throws {
        let items = try await source.reminders(completedSince: at(0))
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        #expect(byID["a"]?.due == at(0) && byID["a"]?.dueHasTime == false && byID["a"]?.listID == "ar1")
        #expect(byID["b"]?.due == at(0, day: 30) && byID["b"]?.deadline == at(0, day: 29) && byID["b"]?.listID == "p1")
        #expect(byID["c"]?.due == nil && byID["c"]?.listID == ThingsSource.inboxID)
        #expect(byID["d"]?.listID == ThingsSource.otherID)
        #expect(byID["e"]?.isCompleted == true && byID["e"]?.completionDate == at(9))
        #expect(source.lists().map(\.title) == ["Inbox", "Work", "Home", "Other"])
        #expect(!source.supportsTime && !source.supportsPriority)
    }

    @Test func cancelledToDosStayOut() async throws {
        things.snapshot.done.append(.init(id: "x", name: "Dropped", status: "canceled", when: at(0), completed: at(10)))
        let items = try await source.reminders(completedSince: at(0))
        #expect(!items.contains { $0.id == "x" })
    }

    @Test func writesOnlyWhatChanged() async throws {
        var item = try await source.reminders(completedSince: at(0)).first { $0.id == "b" }!
        item.title = "Quarterly report"
        item.isCompleted = true
        _ = try await source.save(item)
        #expect(things.calls == ["name b Quarterly report", "status b true"])
    }

    @Test func reschedulingAndUnscheduling() async throws {
        var item = try await source.reminders(completedSince: at(0)).first { $0.id == "b" }!
        item.due = at(0, day: 31)
        _ = try await source.save(item)
        item.due = nil
        _ = try await source.save(item)
        #expect(things.calls == ["schedule b \(at(0, day: 31))", "schedule b anytime"])
    }

    @Test func createsInTheRightPlace() async throws {
        _ = try await source.reminders(completedSince: at(0))
        let saved = try await source.save(ReminderItem(title: "New", listID: "p1", due: at(0)))
        #expect(saved.id == "new1")
        _ = try await source.save(ReminderItem(title: "Loose", listID: ThingsSource.inboxID))
        #expect(things.calls == ["create New project(\"p1\") \(at(0))", "create Loose inbox -"])
    }

    @Test func deletes() async throws {
        let item = try await source.reminders(completedSince: at(0)).first { $0.id == "a" }!
        try await source.remove(item)
        #expect(things.calls == ["delete a"])
    }

    @Test func notAllowedIsDenied() async {
        things.failure = .notAllowed
        await #expect(throws: ReminderSourceError.self) { try await source.reminders(completedSince: at(0)) }
        #expect(source.currentAccess() == .denied)
    }

    @Test func launchesOnlyOnFirstLoadOrRefresh() async throws {
        things.running = false
        _ = try await source.reminders(completedSince: at(0))
        #expect(things.launches == 1)
        things.running = false                         // quit by the user
        await #expect(throws: ReminderSourceError("Things is closed. ⌘R opens it.")) {
            try await source.reminders(completedSince: at(0))
        }
        source.refreshIfNeeded()                       // ⌘R
        _ = try await source.reminders(completedSince: at(0))
        #expect(things.launches == 2)
    }

    @Test func aTimeoutSaysSo() async {
        things.failure = .timedOut
        await #expect(throws: ReminderSourceError("Things didn't answer.")) { try await source.reminders(completedSince: at(0)) }
    }

    @Test func linksOpenThings() {
        #expect(source.link(for: ReminderItem(id: "a", title: "x", listID: "l"))?.absoluteString == "things:///show?id=a")
    }
}
