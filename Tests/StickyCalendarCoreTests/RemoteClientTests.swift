import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct RemoteClientTests {
    final class Tokens {
        var asked: [Bool] = []
        func token(renew: Bool) -> String { asked.append(renew); return renew ? "fresh" : "stale" }
    }

    @Test func a401RenewsTheTokenAndRetriesOnce() async throws {
        let (session, log) = StubHTTP.session { call in
            call.headers["Authorization"] == "Bearer fresh" ? (200, ["ok": true]) : (401, [:])
        }
        let tokens = Tokens()
        let client = RemoteClient(base: URL(string: "https://example.test/v1/")!, token: "", session: session,
                                  service: "Test", tokenProvider: { renew in tokens.token(renew: renew) })
        let result = try await client.get("things") as? [String: Any]
        #expect(result?["ok"] as? Bool == true)
        #expect(tokens.asked == [false, true] && log().count == 2)
    }

    @Test func aSecond401IsUnauthorized() async {
        let (session, _) = StubHTTP.session { _ in (401, [:]) }
        let client = RemoteClient(base: URL(string: "https://example.test/v1/")!, token: "", session: session,
                                  service: "Test", tokenProvider: { _ in "t" })
        await #expect(throws: RemoteClient.Failure.self) { try await client.get("things") }
    }

    final class Flag: @unchecked Sendable { var value = true }

    @Test func a429WaitsOnceThenRetries() async throws {
        let first = Flag()
        let (session, log) = StubHTTP.session { _ in
            defer { first.value = false }
            return first.value ? (429, [:]) : (200, ["ok": true])
        }
        let client = RemoteClient(base: URL(string: "https://example.test/v1/")!, token: "t", session: session, service: "Test")
        _ = try await client.get("things")
        #expect(log().count == 2)
    }

    @Test func followsAbsoluteNextLinks() async throws {
        let (session, log) = StubHTTP.session { _ in (200, ["value": []]) }
        let client = RemoteClient(base: URL(string: "https://example.test/v1/")!, token: "t", session: session, service: "Test")
        _ = try await client.get(url: URL(string: "https://example.test/v1/things?$skiptoken=abc")!)
        #expect(log().first?.path == "/v1/things" && log().first?.query["$skiptoken"] == "abc")
    }

    @Test func a404SaysTheReminderIsGone() async {
        let (session, _) = StubHTTP.session { _ in (404, [:]) }
        let client = RemoteClient(base: URL(string: "https://example.test/v1/")!, token: "t", session: session, service: "Test")
        await #expect(throws: ReminderSourceError("That reminder no longer exists in Test.")) {
            try await client.send("DELETE", "things/1", body: nil)
        }
    }
}
