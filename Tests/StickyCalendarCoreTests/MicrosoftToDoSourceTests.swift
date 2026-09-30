import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct MicrosoftToDoSourceTests {
    nonisolated static func graph(_ call: StubHTTP.Call) -> (status: Int, json: Any) {
        switch (call.method, call.path) {
        case ("POST", "/common/oauth2/v2.0/token"):
            return (200, ["access_token": "A", "refresh_token": "R2", "expires_in": 3600])
        case ("GET", "/v1.0/me/todo/lists"):
            return (200, ["value": [
                ["id": "L1", "displayName": "Tasks", "wellknownListName": "defaultList"],
                ["id": "L2", "displayName": "Flagged email", "wellknownListName": "flaggedEmails"],
            ]])
        case ("GET", "/v1.0/me/todo/lists/L1/tasks"):
            // A next-page link carries the query in its skip token, as Graph's do.
            if call.query["$skiptoken"] == "p2" {
                return (200, ["value": [
                    ["id": "t2", "title": "Gym", "status": "inProgress", "importance": "normal",
                     "dueDateTime": ["dateTime": "2026-10-02T00:00:00.0000000", "timeZone": "UTC"],
                     "isReminderOn": true,
                     "reminderDateTime": ["dateTime": "2026-10-01T07:00:00.0000000", "timeZone": "UTC"],
                     "recurrence": ["pattern": ["type": "daily", "interval": 1]]],
                ]])
            }
            if (call.query["$filter"] ?? "").hasPrefix("status ne") {
                return (200, ["value": [
                    ["id": "t1", "title": "Pay rent", "status": "notStarted", "importance": "high",
                     "body": ["content": "by transfer", "contentType": "text"],
                     "dueDateTime": ["dateTime": "2026-09-30T00:00:00.0000000", "timeZone": "UTC"],
                     "isReminderOn": true,
                     "reminderDateTime": ["dateTime": "2026-09-30T17:00:00.0000000", "timeZone": "UTC"]],
                ], "@odata.nextLink": "https://graph.microsoft.com/v1.0/me/todo/lists/L1/tasks?$skiptoken=p2"])
            }
            return (200, ["value": [
                ["id": "t3", "title": "Shop", "status": "completed", "importance": "low",
                 "completedDateTime": ["dateTime": "2026-09-28T08:00:00.0000000", "timeZone": "UTC"]],
            ]])
        case ("GET", "/v1.0/me/todo/lists/L2/tasks"):
            return (200, ["value": []])
        case ("PATCH", _), ("POST", _):
            var row: [String: Any] = ["id": call.path.split(separator: "/").last.map(String.init) ?? "t9", "status": "notStarted", "importance": "normal"]
            for (key, value) in call.body { row[key] = value }
            if row["title"] == nil { row["title"] = "Pay rent" }
            return (200, row)
        default:
            return (200, [:])
        }
    }

    private func source(calendar: Calendar = utc, _ handler: @escaping StubHTTP.Handler = graph) -> (MicrosoftToDoSource, () -> [StubHTTP.Call]) {
        let (session, log) = StubHTTP.session(handler)
        let auth = MicrosoftSession(clientID: "cid", refreshToken: "R1", session: session, now: { at(12) }, keep: { _ in })
        return (MicrosoftToDoSource(auth: auth, session: session, calendar: calendar), log)
    }

    @Test func readsListsTasksAndPages() async throws {
        let (source, _) = source()
        let items = try await source.reminders(completedSince: at(0))
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        #expect(source.lists().map(\.title) == ["Tasks", "Flagged email"])
        #expect(source.lists().map(\.isWritable) == [true, false])
        #expect(source.defaultListID() == "L1")
        #expect(byID["t1"]?.due == at(17, day: 30) && byID["t1"]?.dueHasTime == true)      // reminder on the due day
        #expect(byID["t1"]?.priority == .high && byID["t1"]?.notes == "by transfer")
        #expect(byID["t2"]?.due == at(0, day: 32) && byID["t2"]?.dueHasTime == false)      // 2 Oct; reminder on another day
        #expect(byID["t2"]?.isRepeating == true && byID["t2"]?.isCompleted == false)       // inProgress is open
        #expect(byID["t3"]?.isCompleted == true && byID["t3"]?.completionDate == at(8))
    }

    @Test func dueDaysStayTheSameDayInAnyTimeZone() async throws {
        for zone in ["Europe/Moscow", "America/Los_Angeles"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            let (source, _) = source(calendar: calendar)
            let t2 = try await source.reminders(completedSince: at(0)).first { $0.id == "t2" }!
            #expect(calendar.dateComponents([.year, .month, .day], from: t2.due!) == DateComponents(year: 2026, month: 10, day: 2))
            let t1 = try await source.reminders(completedSince: at(0)).first { $0.id == "t1" }!
            #expect(t1.due == at(17, day: 30))                                               // an instant: 17:00 UTC
        }
    }

    @Test func sendsOnlyWhatChanged() async throws {
        let (source, log) = source()
        var t1 = try await source.reminders(completedSince: at(0)).first { $0.id == "t1" }!
        t1.title = "Pay the rent"
        t1.isCompleted = true
        _ = try await source.save(t1)
        let patch = log().last!
        #expect(patch.method == "PATCH" && patch.path == "/v1.0/me/todo/lists/L1/tasks/t1")
        #expect(Set(patch.body.keys) == ["title", "status"] && patch.body["status"] as? String == "completed")
    }

    @Test func aTimeGoesToTheReminderAndADayAloneSwitchesItOff() async throws {
        let (source, log) = source()
        var t1 = try await source.reminders(completedSince: at(0)).first { $0.id == "t1" }!
        t1.due = at(0, day: 29)
        t1.dueHasTime = false
        _ = try await source.save(t1)
        #expect(Set(log().last!.body.keys) == ["dueDateTime", "isReminderOn"])
        #expect("\(log().last!.body["isReminderOn"]!)" == "0" || "\(log().last!.body["isReminderOn"]!)" == "false")
    }

    @Test func importanceBothWays() async throws {
        let (source, log) = source()
        var t1 = try await source.reminders(completedSince: at(0)).first { $0.id == "t1" }!
        t1.priority = .medium
        _ = try await source.save(t1)
        #expect(log().last!.body["importance"] as? String == "high")
    }

    @Test func aRefusedSignInIsDenied() async {
        let (source, _) = source { call in
            call.path.hasSuffix("/token") ? (400, ["error": "invalid_grant"]) : (401, [:])
        }
        do {
            _ = try await source.reminders(completedSince: at(0))
            Issue.record("Expected a sign-in error")
        } catch {
            #expect(error as? ReminderSourceError == ReminderSourceError("Microsoft To Do signed you out. Sign in again."))
        }
        #expect(source.currentAccess() == .denied)
    }

    @Test func fallsBackWhenTheFilterIsRejected() async throws {
        let (source, _) = source { call in
            if call.query["$filter"] != nil { return (400, ["error": ["code": "BadRequest"]]) }
            return Self.graph(StubHTTP.Call(method: call.method, path: call.path, query: call.query.merging(["$filter": "status ne x"]) { a, _ in a },
                                            body: call.body, headers: call.headers))
        }
        let items = try await source.reminders(completedSince: at(0))
        #expect(items.contains { $0.id == "t1" })
    }
}
