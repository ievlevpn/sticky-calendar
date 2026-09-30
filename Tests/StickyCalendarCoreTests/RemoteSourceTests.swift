import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct TodoistSourceTests {
    private static func handler(_ call: StubHTTP.Call) -> (status: Int, json: Any) {
        switch (call.method, call.path) {
        case ("GET", "/api/v1/projects"):
            return (200, ["results": [
                ["id": "p1", "name": "Inbox", "color": "grey", "inbox_project": true],
                ["id": "p2", "name": "Work", "color": "red"],
            ], "next_cursor": NSNull()])
        case ("GET", "/api/v1/tasks"):
            // Two pages, to check the cursor is followed.
            if call.query["cursor"] == nil {
                return (200, ["results": [
                    ["id": "t1", "content": "Buy milk", "project_id": "p1", "checked": false, "priority": 4,
                     "description": "oat, not dairy",
                     "due": ["date": "2026-09-28", "string": "today", "is_recurring": false]],
                ], "next_cursor": "c2"])
            }
            return (200, ["results": [
                ["id": "t2", "content": "Standup", "project_id": "p2", "checked": false,
                 "due": ["date": "2026-09-28T09:30:00Z", "string": "today 9:30", "is_recurring": true]],
                ["id": "t3", "content": "Someday", "project_id": "p2", "checked": false, "due": NSNull()],
            ], "next_cursor": NSNull()])
        case ("GET", "/api/v1/tasks/completed/by_completion_date"):
            return (200, ["items": [
                ["id": "t4", "content": "Invoice", "project_id": "p2", "checked": true, "completed_at": "2026-09-28T08:00:00Z"],
                // A repeating task's earlier completion: it's still open (t2), so left out.
                ["id": "t2", "content": "Standup", "project_id": "p2", "checked": true, "completed_at": "2026-09-27T09:40:00Z"],
            ], "next_cursor": NSNull()])
        case ("POST", "/api/v1/tasks"):
            return (200, ["id": "t9", "content": call.body["content"] ?? "", "project_id": call.body["project_id"] ?? "",
                          "checked": false, "due": ["date": call.body["due_date"] ?? "", "string": "", "is_recurring": false]])
        default:
            return (200, [:])
        }
    }

    @Test func readsProjectsAndEveryPageOfTasks() async throws {
        let (session, _) = StubHTTP.session(Self.handler)
        let source = TodoistSource(token: "t", session: session, calendar: utc)
        let items = try await source.reminders(completedSince: at(0))
        #expect(items.map(\.title) == ["Buy milk", "Standup", "Someday", "Invoice"])
        #expect(items[0].due == at(0) && !items[0].dueHasTime)
        #expect(items[1].due == at(9, 30) && items[1].dueHasTime)
        #expect(items[2].due == nil)
        #expect(items[3].isCompleted && items[3].completionDate == at(8))
        #expect(items.map(\.isRepeating) == [false, true, false, false])
        #expect(source.lists().map(\.title) == ["Inbox", "Work"])
        #expect(source.defaultListID() == "p1")
        #expect(source.currentAccess() == .granted)
    }

    @Test func completedTasksUseTheDefaultPageSize() async throws {
        let (session, log) = StubHTTP.session(Self.handler)
        _ = try await TodoistSource(token: "t", session: session, calendar: utc).reminders(completedSince: at(0))
        let completed = log().filter { $0.path.hasSuffix("/by_completion_date") }
        #expect(completed.count == 1 && completed[0].query["limit"] == nil)
    }

    @Test func readsPriorityAndDescription() async throws {
        let (session, log) = StubHTTP.session(Self.handler)
        let source = TodoistSource(token: "t", session: session, calendar: utc)
        var milk = try await source.reminders(completedSince: at(0))[0]
        #expect(milk.priority == .high && milk.notes == "oat, not dairy")
        milk.priority = .low
        milk.notes = "any milk"
        _ = try await source.save(milk)
        let update = try #require(log().last { $0.method == "POST" })
        #expect(update.body["priority"] as? String == "2" && update.body["description"] as? String == "any milk")
    }

    @Test func sendsOnlyWhatChanged() async throws {
        let (session, log) = StubHTTP.session(Self.handler)
        let source = TodoistSource(token: "t", session: session, calendar: utc)
        var milk = try await source.reminders(completedSince: at(0))[0]
        milk.isCompleted = true
        _ = try await source.save(milk)
        milk.title = "Buy oat milk"
        milk.isCompleted = false
        _ = try await source.save(milk)
        let writes = log().filter { $0.method != "GET" }.map { "\($0.method) \($0.path) \($0.body.keys.sorted())" }
        #expect(writes == [
            "POST /api/v1/tasks/t1/close []",
            "POST /api/v1/tasks/t1 [\"content\"]",
            "POST /api/v1/tasks/t1/reopen []",
        ])
    }

    @Test func createsWithADueDateOrTime() async throws {
        let (session, log) = StubHTTP.session(Self.handler)
        let source = TodoistSource(token: "t", session: session, calendar: utc)
        let saved = try await source.save(ReminderItem(title: "Pay rent", listID: "p1", due: at(0), dueHasTime: false))
        _ = try await source.save(ReminderItem(title: "Call Sam", listID: "p2", due: at(10), dueHasTime: true))
        let bodies = log().filter { $0.method == "POST" }.map(\.body)
        #expect(bodies[0]["due_date"] as? String == "2026-09-28" && bodies[0]["project_id"] as? String == "p1")
        #expect(bodies[1]["due_datetime"] as? String == "2026-09-28T10:00:00Z")
        #expect(saved.id == "t9")
    }

    @Test func aRejectedTokenIsReported() async {
        let (session, _) = StubHTTP.session { _ in (401, [:]) }
        let source = TodoistSource(token: "bad", session: session, calendar: utc)
        await #expect(throws: ReminderSourceError.self) { try await source.reminders(completedSince: at(0)) }
        #expect(source.currentAccess() == .denied)
        #expect(TodoistSource(token: "", calendar: utc).currentAccess() == .notDetermined)
    }
}

@MainActor
struct TickTickSourceTests {
    private static func handler(_ call: StubHTTP.Call) -> (status: Int, json: Any) {
        switch (call.method, call.path) {
        case ("GET", "/open/v1/project"):
            return (200, [["id": "w1", "name": "Work", "color": "#F18181"], ["id": "old", "name": "Old", "closed": true]])
        case ("GET", "/open/v1/project/inbox/data"):
            return (200, ["tasks": [
                // All-day: midnight in the task's own zone, sent as UTC.
                ["id": "a", "projectId": "inbox123", "title": "Buy milk", "status": 0, "isAllDay": true,
                 "dueDate": "2026-09-27T22:00:00.000+0000", "timeZone": "Europe/Berlin"],
            ]])
        case ("GET", "/open/v1/project/w1/data"):
            return (200, ["tasks": [
                ["id": "b", "projectId": "w1", "title": "Standup", "status": 0, "isAllDay": false,
                 "priority": 3, "content": "room 4", "repeatFlag": "RRULE:FREQ=DAILY;INTERVAL=1",
                 "dueDate": "2026-09-28T09:30:00.000+0000", "timeZone": "UTC"],
            ]])
        default:
            return (200, [:])
        }
    }

    @Test func readsTheInboxAndOpenProjects() async throws {
        let (session, log) = StubHTTP.session(Self.handler)
        let source = TickTickSource(token: "t", session: session, calendar: utc)
        let items = try await source.reminders(completedSince: at(0))
        #expect(items.map(\.title) == ["Buy milk", "Standup"])
        #expect(items[0].due == at(0) && !items[0].dueHasTime)     // 28 Sep, whatever the zone
        #expect(items[1].due == at(9, 30) && items[1].dueHasTime)
        #expect(items[1].priority == .medium && items[1].notes == "room 4")
        #expect(items.map(\.isRepeating) == [false, true])
        #expect(source.lists().map(\.title) == ["Inbox", "Work"])   // the closed project is left out
        #expect(source.defaultListID() == "inbox123")
        #expect(!log().contains { $0.path.contains("/old/") })
    }

    @Test func completesThroughItsEndpointAndReopensByStatus() async throws {
        let (session, log) = StubHTTP.session(Self.handler)
        let source = TickTickSource(token: "t", session: session, calendar: utc)
        var standup = try await source.reminders(completedSince: at(0))[1]
        standup.isCompleted = true
        _ = try await source.save(standup)
        standup.isCompleted = false
        _ = try await source.save(standup)
        let writes = log().filter { $0.method != "GET" }
        #expect(writes.map(\.path) == ["/open/v1/project/w1/task/b/complete", "/open/v1/task/b"])
        #expect(writes[1].body["status"] as? String == "0")
    }
}
