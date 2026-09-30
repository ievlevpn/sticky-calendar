import Foundation
import Testing
@testable import StickyCalendarCore

struct OsaScriptRunnerTests {
    @Test func argumentsArriveUnchanged() async throws {
        let tricky = "He said \"hi\" \\ back\nЗанятие на пианино 🎹 </script> ${x} `y`"
        let out = try await OsaScriptRunner().run("JSON.stringify({echo: args.text})", args: ["text": tricky])
        let echoed = try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: String]
        #expect(echoed?["echo"] == tricky)
    }

    @Test func scriptErrorsCarryTheirNumber() async {
        await #expect(throws: OsaScriptRunner.Failure.notAllowed) {
            try await OsaScriptRunner().run("const e = new Error('no'); e.errorNumber = -1743; throw e")
        }
    }

    @Test func aHungScriptStopsAtTheLimit() async {
        let started = Date()
        await #expect(throws: OsaScriptRunner.Failure.timedOut) {
            try await OsaScriptRunner(timeout: .seconds(1)).run("delay(30)")
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func cancellingStopsTheScript() async {
        let started = Date()
        let task = Task { try await OsaScriptRunner(timeout: .seconds(30)).run("delay(30)") }
        try? await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func largeOutputDoesNotDeadlock() async throws {
        let out = try await OsaScriptRunner().run("'x'.repeat(300000)")
        #expect(out.count == 300000)
    }

    @Test func decodesASnapshot() throws {
        let json = """
        {"open":[{"id":"a","name":"Water plants","notes":"","status":"open","when":"2026-09-27T22:00:00.000Z","deadline":null,"completed":null}],
         "done":[],"inbox":["a"],"lists":[{"id":"p","name":"Home","kind":"project","toDoIDs":[]}]}
        """
        let snapshot = try ThingsSnapshot.decode(json)
        #expect(snapshot.open.first?.when == Date(timeIntervalSince1970: 1_790_546_400))
        #expect(snapshot.lists.first?.kind == "project" && snapshot.inbox == ["a"])
    }
}
