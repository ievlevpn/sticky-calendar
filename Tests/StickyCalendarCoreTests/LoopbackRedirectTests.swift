import Foundation
import Testing
@testable import StickyCalendarCore

struct LoopbackRedirectTests {
    private func get(_ url: URL) async -> (Int, String) {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else { return (0, "") }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self))
    }

    @Test func returnsTheCodeAndThanksTheBrowser() async throws {
        let redirect = LoopbackRedirect(state: "s1")
        let base = try await redirect.start()
        #expect(base.absoluteString.hasPrefix("http://localhost:"))
        let code = Task { try await redirect.code() }
        let (status, page) = await get(URL(string: "\(base)/?code=abc&state=s1")!)
        #expect(status == 200 && page.contains("Signed in to Sticky Calendar"))
        #expect(try await code.value == "abc")
    }

    @Test func ignoresStrayRequestsAndWrongStates() async throws {
        let redirect = LoopbackRedirect(state: "s1")
        let base = try await redirect.start()
        let code = Task { try await redirect.code() }
        #expect(await get(URL(string: "\(base)/favicon.ico")!).0 == 404)
        #expect(await get(URL(string: "\(base)/?code=evil&state=other")!).0 == 400)
        let port = base.port!
        _ = await get(URL(string: "http://127.0.0.1:\(port)/?code=good&state=s1")!)
        #expect(try await code.value == "good")
    }

    @Test func worksOverIPv6Loopback() async throws {
        let redirect = LoopbackRedirect(state: "s1")
        let base = try await redirect.start()
        let code = Task { try await redirect.code() }
        let status = await get(URL(string: "http://[::1]:\(base.port!)/?code=v6&state=s1")!).0
        #expect(status == 200)
        #expect(try await code.value == "v6")
    }

    @Test func anErrorFromMicrosoftEndsIt() async throws {
        let redirect = LoopbackRedirect(state: "s1")
        let base = try await redirect.start()
        let code = Task { try await redirect.code() }
        _ = await get(URL(string: "\(base)/?error=access_denied&error_description=The%20user%20declined&state=s1")!)
        await #expect(throws: LoopbackRedirect.Failure.denied("The user declined")) { try await code.value }
    }

    @Test func givesUpAfterItsTimeLimit() async throws {
        let redirect = LoopbackRedirect(state: "s1", timeout: .milliseconds(300))
        _ = try await redirect.start()
        await #expect(throws: LoopbackRedirect.Failure.timedOut) { try await redirect.code() }
    }

    @Test func cancelEndsTheWait() async throws {
        let redirect = LoopbackRedirect(state: "s1")
        _ = try await redirect.start()
        let code = Task { try await redirect.code() }
        redirect.cancel()
        await #expect(throws: LoopbackRedirect.Failure.cancelled) { try await code.value }
    }

    @Test func stopsListeningOnceFinished() async throws {
        let redirect = LoopbackRedirect(state: "s1")
        let base = try await redirect.start()
        redirect.cancel()
        #expect(await get(URL(string: "\(base)/?code=late&state=s1")!).0 == 0)
    }
}
