import Foundation
import Testing
@testable import StickyCalendarCore

struct SemanticVersionTests {
    @Test func parsesWithOrWithoutPrefixAndMissingParts() {
        #expect(SemanticVersion("v1.2.3")?.description == "1.2.3")
        #expect(SemanticVersion("1.2")?.description == "1.2.0")
        #expect(SemanticVersion("V2")?.description == "2.0.0")
        #expect(SemanticVersion("1.3.0-beta.1")?.prerelease == "beta.1")
    }

    @Test func rejectsGarbage() {
        #expect(SemanticVersion("") == nil)
        #expect(SemanticVersion("latest") == nil)
        #expect(SemanticVersion("1..2") == nil)
        #expect(SemanticVersion("1.2.3.4") == nil)
        #expect(SemanticVersion("1.-2") == nil)
    }

    @Test func comparesNumericallyNotAlphabetically() {
        #expect(SemanticVersion("1.9.0")! < SemanticVersion("1.10.0")!)
        #expect(SemanticVersion("1.2")! == SemanticVersion("1.2.0")!)
        #expect(!(SemanticVersion("2.0.0")! < SemanticVersion("1.99.99")!))
    }

    @Test func releaseIsNewerThanItsPrerelease() {
        #expect(SemanticVersion("1.3.0-beta")! < SemanticVersion("1.3.0")!)
        #expect(!(SemanticVersion("1.3.0")! < SemanticVersion("1.3.0-beta")!))
    }
}

struct ReleaseParserTests {
    let page = "https://github.com/ievlevpn/sticky-calendar/releases/tag/v1.4.0"

    func body(_ json: String) -> Data { Data(json.utf8) }

    @Test func parsesGitHubLatestRelease() {
        let info = ReleaseParser.parse(statusCode: 200, body: body(#"{"tag_name":"v1.4.0","html_url":"\#(page)","name":"x"}"#))
        #expect(info?.version.description == "1.4.0")
        #expect(info?.pageURL.absoluteString == page)
    }

    @Test func anythingElseIsNil() {
        #expect(ReleaseParser.parse(statusCode: 404, body: body(#"{"message":"Not Found"}"#)) == nil)
        #expect(ReleaseParser.parse(statusCode: 403, body: body(#"{"message":"rate limit"}"#)) == nil)
        #expect(ReleaseParser.parse(statusCode: 200, body: body("<html>")) == nil)
        #expect(ReleaseParser.parse(statusCode: 200, body: body(#"{"tag_name":"nightly","html_url":"\#(page)"}"#)) == nil)
    }
}

final class FakeFetcher: ReleaseFetcher, @unchecked Sendable {
    var reply: Result<(Int, Data), Error>
    private(set) var calls = 0

    init(tag: String) {
        reply = .success((200, Data(#"{"tag_name":"\#(tag)","html_url":"https://github.com/ievlevpn/sticky-calendar/releases/tag/\#(tag)"}"#.utf8)))
    }

    init(status: Int) { reply = .success((status, Data("{}".utf8))) }

    init(error: Error) { reply = .failure(error) }

    func fetchLatestRelease() async throws -> (statusCode: Int, body: Data) {
        calls += 1
        let (status, body) = try reply.get()
        return (status, body)
    }
}

@MainActor
struct UpdateCheckerTests {
    let defaults: UserDefaults
    var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() {
        let name = "UpdateCheckerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    func checker(_ version: String, _ fetcher: FakeFetcher, now: @escaping () -> Date) -> UpdateChecker {
        UpdateChecker(currentVersion: version, fetcher: fetcher, defaults: defaults, now: now)
    }

    @Test func reportsNewerRelease() async {
        let c = checker("1.2.0", FakeFetcher(tag: "v1.3.0"), now: { clock })
        let status = await c.checkNow()
        guard case .available(let info) = status else { Issue.record("expected available, got \(status)"); return }
        #expect(info.version.description == "1.3.0")
        #expect(c.status == status)
    }

    @Test func sameOrOlderIsUpToDate() async {
        #expect(await checker("1.3.0", FakeFetcher(tag: "v1.3.0"), now: { clock }).checkNow() == .upToDate)
        #expect(await checker("1.4.0", FakeFetcher(tag: "v1.3.0"), now: { clock }).checkNow() == .upToDate)
    }

    @Test func prereleaseLatestIsNotOffered() async {
        #expect(await checker("1.2.0", FakeFetcher(tag: "v1.3.0-beta"), now: { clock }).checkNow() == .upToDate)
    }

    @Test func failuresAreUnknownNotErrors() async {
        #expect(await checker("1.2.0", FakeFetcher(status: 404), now: { clock }).checkNow() == .unknown)
        #expect(await checker("1.2.0", FakeFetcher(status: 403), now: { clock }).checkNow() == .unknown)
        #expect(await checker("1.2.0", FakeFetcher(error: URLError(.notConnectedToInternet)), now: { clock }).checkNow() == .unknown)
    }

    @Test func developmentBuildsNeverCheck() async {
        let fetcher = FakeFetcher(tag: "v9.0.0")
        let c = checker("0.0.0-dev", fetcher, now: { clock })
        #expect(c.isDevelopmentBuild)
        #expect(await c.checkNow() == .unknown)
        #expect(fetcher.calls == 0)
    }

    @Test func automaticChecksRunAtMostDaily() async {
        var now = clock
        let fetcher = FakeFetcher(tag: "v1.3.0")
        let c = checker("1.2.0", fetcher, now: { now })
        await c.checkIfDue()
        now += 60 * 60
        await c.checkIfDue()
        #expect(fetcher.calls == 1)
        now += 24 * 60 * 60
        await c.checkIfDue()
        #expect(fetcher.calls == 2)
    }

    @Test func manualCheckIgnoresSchedule() async {
        let fetcher = FakeFetcher(tag: "v1.3.0")
        let c = checker("1.2.0", fetcher, now: { clock })
        await c.checkIfDue()
        await c.checkNow()
        #expect(fetcher.calls == 2)
    }

    @Test func failedAttemptsAlsoWaitADay() async {
        let fetcher = FakeFetcher(status: 404)
        let c = checker("1.2.0", fetcher, now: { clock })
        await c.checkIfDue()
        await c.checkIfDue()
        #expect(fetcher.calls == 1)
    }

    @Test func disabledAutomaticChecksPersistAndSkip() async {
        let fetcher = FakeFetcher(tag: "v1.3.0")
        let c = checker("1.2.0", fetcher, now: { clock })
        #expect(c.automaticChecksEnabled)
        c.setAutomaticChecks(false)
        await c.checkIfDue()
        #expect(fetcher.calls == 0)
        #expect(!checker("1.2.0", fetcher, now: { clock }).automaticChecksEnabled)
    }

    @Test func lastCheckSurvivesRelaunch() async {
        let fetcher = FakeFetcher(tag: "v1.3.0")
        await checker("1.2.0", fetcher, now: { clock }).checkIfDue()
        await checker("1.2.0", fetcher, now: { clock + 60 }).checkIfDue()
        #expect(fetcher.calls == 1)
    }
}

@MainActor
struct UpdateSummaryTests {
    let defaults: UserDefaults

    init() {
        let name = "UpdateSummaryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    func checker(_ version: String, _ fetcher: FakeFetcher) -> UpdateChecker {
        UpdateChecker(currentVersion: version, fetcher: fetcher, defaults: defaults)
    }

    @Test func describesEachOutcome() async {
        let fresh = checker("1.2.0", FakeFetcher(tag: "v1.3.0"))
        #expect(fresh.summary == "Not checked yet.")
        await fresh.checkNow()
        #expect(fresh.summary == "Version 1.3.0 is available.")

        let current = checker("1.3.0", FakeFetcher(tag: "v1.3.0"))
        await current.checkNow()
        #expect(current.summary == "Sticky Calendar is up to date.")

        let offline = checker("1.2.0", FakeFetcher(status: 404))
        await offline.checkNow()
        #expect(offline.summary == "Couldn't check for updates.")

        #expect(checker("0.0.0-dev", FakeFetcher(tag: "v1.3.0")).summary == "Development build — update checks are off.")
    }

    @Test func relaunchAfterAFailedCheckIsNotReportedAsFailure() async {
        await checker("1.2.0", FakeFetcher(status: 404)).checkNow()
        #expect(checker("1.2.0", FakeFetcher(status: 404)).summary == "Not checked yet.")
    }
}

struct InstallMethodTests {
    @Test func detectsHomebrewCaskroomOnEitherPrefix() {
        #expect(InstallMethod.detect { $0 == "/opt/homebrew/Caskroom/sticky-calendar" } == .homebrew)
        #expect(InstallMethod.detect { $0 == "/usr/local/Caskroom/sticky-calendar" } == .homebrew)
        #expect(InstallMethod.detect { _ in false } == .direct)
    }
}
