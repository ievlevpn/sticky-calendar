# Release & Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put Sticky Calendar in a private GitHub repo where each version tag produces a signed, universal DMG release. The app tells users when a newer release exists, and a Homebrew cask is ready to publish once the repo goes public.

**Architecture:** An `UpdateChecker` in the tested core reads GitHub's "latest release" endpoint through an injectable fetcher and compares semantic versions; the app shell only shows its result in the menu, Settings and alerts, and never installs anything. Shell scripts build, sign (a stable self-signed certificate) and package the app; GitHub Actions runs them on tags. The Homebrew step is present but gated on a secret.

**Tech Stack:** Swift 5 mode / SwiftPM, Swift Testing, bash, `codesign`, `hdiutil`, `lipo`, `security`, OpenSSL, GitHub Actions (`macos-15`), `gh` CLI, Homebrew cask DSL.

**Spec:** `docs/superpowers/specs/2026-09-29-release-and-updates-design.md`

## Global Constraints

- Repository `ievlevpn/sticky-calendar`, **private**. Nothing is published publicly by this plan.
- No third-party dependencies (no Sparkle).
- Bundle id `com.ievlevpn.StickyCalendar`; minimum macOS 14.
- Signing identity name, exactly: `Sticky Calendar Self-Signed`, and it signs by SHA-1 hash (a self-signed certificate is "not trusted", so `codesign` can't find it by name).
- Version: tag `vX.Y.Z` → `CFBundleShortVersionString` `X.Y.Z`; `CFBundleVersion` = `git rev-list --count HEAD`; local default `0.0.0-dev`.
- DMG name `StickyCalendar-X.Y.Z.dmg`, volume name `Sticky Calendar`.
- Cask name `sticky-calendar`; tap `ievlevpn/homebrew-tap`; upgrade command `brew upgrade --cask sticky-calendar`.
- The update check never shows an error for "not found", rate limits or network failures.
- Run tests only via `./scripts/test.sh`; `swift build` must have zero warnings.
- **Never change the user's keychain search list.** `security create-keychain` may add keychains to it; any throwaway keychain must be removed with `security delete-keychain`. Only `ci-import-cert.sh` (fresh CI runner) sets the list.
- Outward-facing actions (repo creation, push, secrets, tags) and adding the certificate to the login keychain need the user's explicit go-ahead at the step that does them.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

- **The repo is private, so GitHub answers 404 for the latest release.** The app must stay silent: no alert on automatic checks, and "Not checked yet" / "Couldn't check for updates." in Settings. Pinned by `failuresAreUnknownNotErrors` and `describesEachOutcome` (Task 1).
- **Relaunch after a failed check:** it must not claim "Couldn't check" when this session hasn't checked. Pinned by `relaunchAfterAFailedCheckIsNotReportedAsFailure` (Task 1).
- **Version ordering:** `1.10.0` must be newer than `1.9.0` (not alphabetical), and a pre-release is never offered as an update. Pinned by `comparesNumericallyNotAlphabetically` and `prereleaseLatestIsNotOffered` (Task 1).
- **CI can't find the certificate** (missing or wrong secret): the release must fail rather than ship an ad-hoc-signed DMG, which would reset every user's Calendar permission. Pinned by the `REQUIRE_SIGNING=1` failure check in Task 3 Step 4 and `verify-dmg.sh`'s authority check.
- **The cask template gets a bad checksum or version:** rendering must refuse it. Pinned by the bad-sha check in Task 5 Step 2.

## File Structure

```
Sources/StickyCalendarCore/UpdateChecker.swift     SemanticVersion, ReleaseInfo, UpdateStatus, ReleaseFetcher,
                                                   GitHubReleaseFetcher, ReleaseParser, UpdateChecker, InstallMethod
Tests/StickyCalendarCoreTests/UpdateCheckerTests.swift
Sources/StickyCalendar/UpdateActions.swift         alerts, "Get Update" behaviour
Sources/StickyCalendar/StatusItemController.swift  (modify) Check for Updates…, Update Available item
Sources/StickyCalendar/AppDelegate.swift           (modify) checker, hourly schedule, AppVersion
Sources/StickyCalendar/Views/SettingsView.swift    (modify) Updates section
scripts/lib/signing.sh                             shared: identity name, signing_hash
scripts/build-app.sh                               (replace) --version --universal --sign --require-sign --install
scripts/build-dmg.sh                               universal signed DMG + .sha256
scripts/verify-dmg.sh                              asserts DMG contents/version/archs/signature
scripts/create-signing-cert.sh                     one-time certificate creation + secrets export
scripts/ci-import-cert.sh                          CI: temporary keychain from secrets
packaging/homebrew/sticky-calendar.rb.template     cask
scripts/update-cask.sh                             renders the cask
.github/workflows/ci.yml, release.yml
RELEASING.md, README.md                            (README modified)
```

---

### Task 1: Update checker core

**Files:**
- Create: `Sources/StickyCalendarCore/UpdateChecker.swift`, `Tests/StickyCalendarCoreTests/UpdateCheckerTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `SemanticVersion(_:)` (failable), with `.isPrerelease`, `.description`, `Comparable`.
  - `ReleaseInfo { version, pageURL }` and `UpdateStatus { unknown, upToDate, available(ReleaseInfo) }`.
  - `protocol ReleaseFetcher: Sendable { func fetchLatestRelease() async throws -> (statusCode: Int, body: Data) }`.
  - `GitHubReleaseFetcher(repository:)`, with `static let repository = "ievlevpn/sticky-calendar"`.
  - `ReleaseParser.parse(statusCode:body:) -> ReleaseInfo?`
  - `@MainActor @Observable UpdateChecker(currentVersion:fetcher:defaults:now:)` has:
    - state: `status`, `automaticChecksEnabled`, `lastCheck`, `lastCheckFailed`, `currentVersion`, `isDevelopmentBuild`, `summary`
    - actions: `setAutomaticChecks(_:)`, `checkIfDue() async`, `checkNow() async -> UpdateStatus`
  - `InstallMethod { homebrew, direct }`, with `detect(fileExists:)`, `caskName` and `upgradeCommand`.

- [ ] **Step 1: Write the failing tests**

`Tests/StickyCalendarCoreTests/UpdateCheckerTests.swift`:
```swift
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
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `./scripts/test.sh`
Expected: the build fails with `cannot find 'SemanticVersion' in scope` (and similar).

- [ ] **Step 3: Implement**

`Sources/StickyCalendarCore/UpdateChecker.swift`:
```swift
import Foundation
import Observation

/// `MAJOR.MINOR.PATCH[-prerelease]`, with an optional leading `v`. Missing parts count as 0.
public struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let pieces = text.split(separator: "-", maxSplits: 1).map(String.init)
        guard let core = pieces.first, !core.isEmpty else { return nil }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(numbers.count), numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        major = numbers[0]!
        minor = numbers.count > 1 ? numbers[1]! : 0
        patch = numbers.count > 2 ? numbers[2]! : 0
        prerelease = pieces.count > 1 ? pieces[1] : nil
    }

    public var isPrerelease: Bool { prerelease != nil }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "")
    }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) {
            return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }
        switch (a.prerelease, b.prerelease) {
        case (nil, nil), (nil, _): return false // a release is never older than its pre-release
        case (_, nil): return true
        case let (x?, y?): return x < y
        }
    }
}

public struct ReleaseInfo: Equatable, Sendable {
    public let version: SemanticVersion
    public let pageURL: URL
}

public enum UpdateStatus: Equatable, Sendable {
    /// Never checked, or the check failed (offline, private repo, rate limit, bad reply).
    case unknown
    case upToDate
    case available(ReleaseInfo)
}

/// Fetches the raw "latest release" reply. Injected so tests never touch the network.
public protocol ReleaseFetcher: Sendable {
    func fetchLatestRelease() async throws -> (statusCode: Int, body: Data)
}

public struct GitHubReleaseFetcher: ReleaseFetcher {
    public static let repository = "ievlevpn/sticky-calendar"
    public let url: URL

    public init(repository: String = GitHubReleaseFetcher.repository) {
        url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    public func fetchLatestRelease() async throws -> (statusCode: Int, body: Data) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

public enum ReleaseParser {
    private struct Payload: Decodable {
        let tag_name: String
        let html_url: URL
    }

    /// The release described by a GitHub "latest release" reply, or nil for anything else.
    public static func parse(statusCode: Int, body: Data) -> ReleaseInfo? {
        guard statusCode == 200,
              let payload = try? JSONDecoder().decode(Payload.self, from: body),
              let version = SemanticVersion(payload.tag_name) else { return nil }
        return ReleaseInfo(version: version, pageURL: payload.html_url)
    }
}

/// Tells whether a newer release exists on GitHub. Never downloads or installs anything.
@MainActor
@Observable
public final class UpdateChecker {
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    private enum Key {
        static let automaticChecks = "automaticUpdateChecks"
        static let lastCheck = "lastUpdateCheck"
    }

    public private(set) var status: UpdateStatus = .unknown
    public private(set) var automaticChecksEnabled: Bool
    public private(set) var lastCheck: Date?
    /// Whether this session's most recent check failed (as opposed to not having run).
    public private(set) var lastCheckFailed = false
    public let currentVersion: String

    @ObservationIgnored private let fetcher: ReleaseFetcher
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date

    public init(
        currentVersion: String,
        fetcher: ReleaseFetcher = GitHubReleaseFetcher(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.currentVersion = currentVersion
        self.fetcher = fetcher
        self.defaults = defaults
        self.now = now
        automaticChecksEnabled = defaults.object(forKey: Key.automaticChecks) as? Bool ?? true
        lastCheck = defaults.object(forKey: Key.lastCheck) as? Date
    }

    /// Local builds (`0.0.0-dev`, or anything unparseable) never report updates.
    public var isDevelopmentBuild: Bool {
        guard let version = SemanticVersion(currentVersion) else { return true }
        return version.isPrerelease
    }

    /// One line for Settings.
    public var summary: String {
        if isDevelopmentBuild { return "Development build — update checks are off." }
        switch status {
        case .available(let info): return "Version \(info.version) is available."
        case .upToDate: return "Sticky Calendar is up to date."
        case .unknown: return lastCheckFailed ? "Couldn't check for updates." : "Not checked yet."
        }
    }

    public func setAutomaticChecks(_ enabled: Bool) {
        automaticChecksEnabled = enabled
        defaults.set(enabled, forKey: Key.automaticChecks)
    }

    /// Checks if automatic checks are on and the last one was at least a day ago.
    public func checkIfDue() async {
        guard automaticChecksEnabled else { return }
        if let lastCheck, now().timeIntervalSince(lastCheck) < Self.checkInterval { return }
        await checkNow()
    }

    /// Checks regardless of the schedule and returns the outcome.
    @discardableResult
    public func checkNow() async -> UpdateStatus {
        guard !isDevelopmentBuild, let current = SemanticVersion(currentVersion) else {
            status = .unknown
            return status
        }
        lastCheck = now()
        defaults.set(lastCheck, forKey: Key.lastCheck)
        guard let reply = try? await fetcher.fetchLatestRelease(),
              let latest = ReleaseParser.parse(statusCode: reply.statusCode, body: reply.body) else {
            status = .unknown
            lastCheckFailed = true
            return status
        }
        lastCheckFailed = false
        status = !latest.version.isPrerelease && current < latest.version ? .available(latest) : .upToDate
        return status
    }
}

/// How this copy of the app was installed, which decides how to update it.
public enum InstallMethod: Equatable, Sendable {
    case homebrew, direct

    public static let caskName = "sticky-calendar"
    public static let upgradeCommand = "brew upgrade --cask \(caskName)"

    public static func detect(fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> InstallMethod {
        let caskrooms = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
        return caskrooms.contains { fileExists("\($0)/\(caskName)") } ? .homebrew : .direct
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `./scripts/test.sh 2>&1 | grep -E "✘|Test run"; swift build 2>&1 | grep -E "warning:|error:"`
Expected: `✔ Test run with 75 tests in 13 suites passed`, and no warning or error lines.

- [ ] **Step 5: Commit**

```bash
git add Sources/StickyCalendarCore/UpdateChecker.swift Tests/StickyCalendarCoreTests/UpdateCheckerTests.swift
git commit -m "Add update checker: GitHub latest release, semantic versions, daily throttle

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Update UI in the app

**Files:**
- Create: `Sources/StickyCalendar/UpdateActions.swift`
- Modify (full replacements below): `Sources/StickyCalendar/StatusItemController.swift`, `Sources/StickyCalendar/AppDelegate.swift`, `Sources/StickyCalendar/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `UpdateChecker`, `ReleaseInfo`, `InstallMethod` (Task 1).
- Produces:
  - `UpdateActions.checkFromMenu(_:)` and `UpdateActions.getUpdate(_:)`
  - `AppVersion.short` and `AppVersion.build`
  - `StatusItemController(isPanelVisible:onToggle:onSettings:updateChecker:)`
  - `SettingsView(store:settings:updateChecker:)`

- [ ] **Step 1: Actions and alerts**

`Sources/StickyCalendar/UpdateActions.swift`:
```swift
import AppKit
import StickyCalendarCore

/// What the menu and Settings do with update results. Never installs anything itself:
/// Homebrew installs are told to run `brew upgrade`, others get the release page.
@MainActor
enum UpdateActions {
    /// "Check for Updates…" from the menu: always reports the outcome in an alert.
    static func checkFromMenu(_ checker: UpdateChecker) {
        Task {
            let status = await checker.checkNow()
            let alert = NSAlert()
            switch status {
            case .available(let info):
                alert.messageText = "Sticky Calendar \(info.version) is available"
                alert.informativeText = "You have version \(checker.currentVersion)."
                alert.addButton(withTitle: "Get Update")
                alert.addButton(withTitle: "Later")
                if run(alert) == .alertFirstButtonReturn { getUpdate(info) }
                return
            case .upToDate:
                alert.messageText = "You're up to date"
                alert.informativeText = "Sticky Calendar \(checker.currentVersion) is the latest version."
            case .unknown:
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = checker.isDevelopmentBuild
                    ? "This is a development build; update checks are off."
                    : "Please try again later."
            }
            run(alert)
        }
    }

    static func getUpdate(_ info: ReleaseInfo) {
        guard InstallMethod.detect() == .homebrew else {
            NSWorkspace.shared.open(info.pageURL)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(InstallMethod.upgradeCommand, forType: .string)
        let alert = NSAlert()
        alert.messageText = "Update command copied"
        alert.informativeText = "Sticky Calendar was installed with Homebrew. Paste the copied command into Terminal to update:\n\n\(InstallMethod.upgradeCommand)"
        run(alert)
    }

    @discardableResult
    private static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        return alert.runModal()
    }
}
```

- [ ] **Step 2: Menu**

`Sources/StickyCalendar/StatusItemController.swift` (full file):
```swift
import AppKit
import StickyCalendarCore

/// The menu-bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggleItem = NSMenuItem(title: "Hide Sticky", action: #selector(toggle), keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "", action: #selector(getUpdate), keyEquivalent: "")
    private let isPanelVisible: () -> Bool
    private let onToggle: () -> Void
    private let onSettings: () -> Void
    private let updateChecker: UpdateChecker

    init(
        isPanelVisible: @escaping () -> Bool,
        onToggle: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        updateChecker: UpdateChecker
    ) {
        self.isPanelVisible = isPanelVisible
        self.onToggle = onToggle
        self.onSettings = onSettings
        self.updateChecker = updateChecker
        super.init()

        item.button?.image = NSImage(systemSymbolName: "calendar.day.timeline.left", accessibilityDescription: "Sticky Calendar")

        let menu = NSMenu()
        menu.delegate = self
        updateItem.target = self
        updateItem.isHidden = true
        menu.addItem(updateItem)
        toggleItem.target = self
        menu.addItem(toggleItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let checkItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sticky Calendar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = isPanelVisible() ? "Hide Sticky" : "Show Sticky"
        if case .available(let info) = updateChecker.status {
            updateItem.title = "Update Available: v\(info.version)…"
            updateItem.isHidden = false
        } else {
            updateItem.isHidden = true
        }
    }

    @objc private func toggle() { onToggle() }
    @objc private func openSettings() { onSettings() }
    @objc private func checkForUpdates() { UpdateActions.checkFromMenu(updateChecker) }

    @objc private func getUpdate() {
        if case .available(let info) = updateChecker.status { UpdateActions.getUpdate(info) }
    }
}
```

- [ ] **Step 3: App delegate (checker, hourly schedule, version)**

`Sources/StickyCalendar/AppDelegate.swift` (full file):
```swift
import AppKit
import StickyCalendarCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let source = EventKitSource()
    private lazy var store = CalendarStore(source: source, settings: settings)
    private let updateChecker = UpdateChecker(currentVersion: AppVersion.short)
    private var updateTimer: Timer?
    private var panel: StickyPanel?
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()

        let panel = StickyPanel(store: store, settings: settings)
        self.panel = panel
        statusItem = StatusItemController(
            isPanelVisible: { [weak panel] in panel?.isVisible ?? false },
            onToggle: { [weak self] in self?.togglePanel() },
            onSettings: { [weak self] in self?.showSettings() },
            updateChecker: updateChecker
        )
        panel.orderFrontRegardless()

        observeClock()
        Task { await store.requestAccessIfNeeded() }
        scheduleUpdateChecks()
    }

    /// Checks at launch, then hourly asks whether a (daily) check is due.
    private func scheduleUpdateChecks() {
        let checker = updateChecker
        Task { await checker.checkIfDue() }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            Task { @MainActor in await checker.checkIfDue() }
        }
    }

    private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(store: store, settings: settings, updateChecker: updateChecker)
            ))
            window.title = "Sticky Calendar Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func observeClock() {
        let onClockChange: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.store.handleClockChange() }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: onClockChange))
        observers.append(center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: onClockChange))
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: onClockChange
        ))
    }

    /// Accessory apps show no menu bar, but key equivalents still route through the
    /// main menu — without an Edit menu, ⌘C/⌘V/⌘Z would not work in text fields.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Sticky Calendar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)

        return main
    }
}

enum AppVersion {
    static let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0-dev"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
}
```

- [ ] **Step 4: Settings**

`Sources/StickyCalendar/Views/SettingsView.swift` (full file):
```swift
import ServiceManagement
import StickyCalendarCore
import SwiftUI

struct SettingsView: View {
    let store: CalendarStore
    let settings: AppSettings
    let updateChecker: UpdateChecker

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Calendars") {
                if store.calendars.isEmpty {
                    Text("No calendars available.").foregroundStyle(.secondary)
                }
                ForEach(store.calendars) { calendar in
                    Toggle(isOn: Binding(
                        get: { !settings.hiddenCalendarIDs.contains(calendar.id) },
                        set: { visible in
                            settings.setCalendar(calendar.id, visible: visible)
                            store.reload()
                        }
                    )) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(rgba: calendar.color)).frame(width: 9, height: 9)
                            Text(calendar.title)
                        }
                    }
                }
            }

            Section("Appearance") {
                Slider(value: Binding(get: { settings.opacity }, set: settings.setOpacity), in: AppSettings.opacityRange) {
                    Text("Opacity")
                }
            }

            Section("Updates") {
                LabeledContent("Version", value: "\(AppVersion.short) (build \(AppVersion.build))")
                Text(updateChecker.summary).foregroundStyle(.secondary)
                if case .available(let info) = updateChecker.status {
                    Button("Get Version \(info.version.description)…") { UpdateActions.getUpdate(info) }
                }
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updateChecker.automaticChecksEnabled },
                    set: updateChecker.setAutomaticChecks
                ))
                Button("Check Now") { Task { await updateChecker.checkNow() } }
                    .disabled(updateChecker.isDevelopmentBuild)
            }

            Section {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 600)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

}
```

- [ ] **Step 5: Build, test, launch**

Run: `swift build 2>&1 | grep -E "warning:|error:"; ./scripts/test.sh 2>&1 | grep -E "✘|Test run"; pkill -f "StickyCalendar.app/Contents/MacOS/StickyCalendar"; ./scripts/build-app.sh 2>&1 | tail -1 && open build/StickyCalendar.app`
Expected: no warning or error lines, then `✔ Test run with 75 tests in 13 suites passed` and `Built build/StickyCalendar.app (version 0.0.0-dev, build N)`.

Check (Accessibility tree or ask the user):
- the menu has **Check for Updates…**;
- choosing it on this dev build shows "Couldn't check for updates" / "This is a development build…";
- the Settings **Updates** section shows "Version 0.0.0-dev (build N)" and "Development build — update checks are off.", with **Check Now** disabled.

- [ ] **Step 6: Commit**

```bash
git add Sources/StickyCalendar
git commit -m "Show update status in the menu and Settings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Build, DMG and verification scripts

**Files:**
- Create: `scripts/lib/signing.sh`, `scripts/build-dmg.sh`, `scripts/verify-dmg.sh`
- Modify: `scripts/build-app.sh` (full replacement)

**Interfaces:**
- Produces:
  - `signing_hash NAME [KEYCHAIN]` and `DEFAULT_SIGNING_IDENTITY`
  - `build-app.sh [--version] [--universal] [--sign] [--require-sign] [--install]`
  - `build-dmg.sh X.Y.Z`, which reads `SIGN_IDENTITY` and `REQUIRE_SIGNING`
  - `verify-dmg.sh DMG X.Y.Z`, which reads `REQUIRE_SIGNING`

- [ ] **Step 1: Shared signing helper**

`scripts/lib/signing.sh`:
```bash
# Shared by the build scripts. Source it; don't run it.

# Name of the self-signed certificate every release is signed with.
DEFAULT_SIGNING_IDENTITY="Sticky Calendar Self-Signed"

# Prints the SHA-1 of the named code-signing identity, or nothing. Looks in KEYCHAIN if
# given, else in the keychain search list (where codesign looks). A self-signed
# certificate isn't "trusted", so codesign won't find it by name; signing by hash works.
signing_hash() { # NAME [KEYCHAIN]
    security find-identity -p codesigning ${2:+"$2"} 2>/dev/null \
        | awk -v name="\"$1\"" 'index($0, name) { print $2; exit }'
}
```

- [ ] **Step 2: App build script**

`scripts/build-app.sh` (full file):
```bash
#!/bin/bash
# Builds build/StickyCalendar.app.
#   --version X.Y.Z   marketing version (default 0.0.0-dev: a local build that never
#                     reports updates)
#   --universal       Apple Silicon + Intel (default: this Mac's architecture only)
#   --sign NAME       code-signing identity (default "Sticky Calendar Self-Signed");
#                     without it, falls back to ad-hoc signing unless --require-sign
#   --require-sign    fail instead of falling back to ad-hoc signing (releases)
#   --install         also copy the app to ~/Applications
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/signing.sh

VERSION="0.0.0-dev"
UNIVERSAL=0
IDENTITY="$DEFAULT_SIGNING_IDENTITY"
REQUIRE_SIGN=0
INSTALL=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --universal) UNIVERSAL=1; shift ;;
        --sign) IDENTITY="$2"; shift 2 ;;
        --require-sign) REQUIRE_SIGN=1; shift ;;
        --install) INSTALL=1; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

HASH="$(signing_hash "$IDENTITY")"
if [[ -z "$HASH" && $REQUIRE_SIGN == 1 ]]; then
    echo "error: signing identity \"$IDENTITY\" not found in the keychain" >&2
    exit 1
fi

# Without Xcode, SwiftPM can't build several architectures at once: build each and merge.
binary_for() {
    swift build -c release --product StickyCalendar --triple "$1" >&2
    echo "$(swift build -c release --triple "$1" --show-bin-path)/StickyCalendar"
}

APP=build/StickyCalendar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ $UNIVERSAL == 1 ]]; then
    lipo -create "$(binary_for arm64-apple-macosx14.0)" "$(binary_for x86_64-apple-macosx14.0)" \
        -output "$APP/Contents/MacOS/StickyCalendar"
else
    swift build -c release --product StickyCalendar
    cp "$(swift build -c release --show-bin-path)/StickyCalendar" "$APP/Contents/MacOS/StickyCalendar"
fi

cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

if [[ -n "$HASH" ]]; then
    codesign --force --timestamp=none --sign "$HASH" "$APP"
else
    echo "warning: signing identity \"$IDENTITY\" not found; signing ad-hoc." >&2
    echo "         macOS will ask for Calendar access again after every rebuild." >&2
    codesign --force --sign - "$APP"
fi

if [[ $INSTALL == 1 ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/StickyCalendar.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "Installed to ~/Applications/StickyCalendar.app"
fi
echo "Built $APP (version $VERSION, build $BUILD_NUMBER)"
```

- [ ] **Step 3: DMG and verification scripts**

`scripts/build-dmg.sh`:
```bash
#!/bin/bash
# Builds build/StickyCalendar-X.Y.Z.dmg: universal, signed, with an Applications link.
# Set REQUIRE_SIGNING=1 (CI does) to fail rather than ship an ad-hoc-signed build.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/signing.sh

VERSION="${1:?usage: build-dmg.sh X.Y.Z}"
IDENTITY="${SIGN_IDENTITY:-$DEFAULT_SIGNING_IDENTITY}"
REQUIRE=()
[[ "${REQUIRE_SIGNING:-0}" == 1 ]] && REQUIRE=(--require-sign)

./scripts/build-app.sh --version "$VERSION" --universal --sign "$IDENTITY" ${REQUIRE[@]+"${REQUIRE[@]}"}

DMG="build/StickyCalendar-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R build/StickyCalendar.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Sticky Calendar" -srcfolder "$STAGE" -format UDZO -fs HFS+ -ov "$DMG" >/dev/null

HASH="$(signing_hash "$IDENTITY")"
[[ -n "$HASH" ]] && codesign --force --timestamp=none --sign "$HASH" "$DMG"
shasum -a 256 "$DMG" | awk '{ print $1 }' > "$DMG.sha256"
echo "Built $DMG ($(du -h "$DMG" | cut -f1), sha256 $(cat "$DMG.sha256"))"
```

`scripts/verify-dmg.sh`:
```bash
#!/bin/bash
# Checks a release DMG: contents, version, architectures, and (with REQUIRE_SIGNING=1)
# that it is signed with the self-signed release certificate. Exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/signing.sh

DMG="${1:?usage: verify-dmg.sh DMG X.Y.Z}"
VERSION="${2:?usage: verify-dmg.sh DMG X.Y.Z}"
fail() { echo "FAIL: $*" >&2; exit 1; }

MOUNT="$(mktemp -d)"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" >/dev/null
trap 'hdiutil detach "$MOUNT" -quiet; rmdir "$MOUNT"' EXIT

APP="$MOUNT/StickyCalendar.app"
[[ -d "$APP" ]] || fail "StickyCalendar.app missing"
[[ "$(readlink "$MOUNT/Applications")" == /Applications ]] || fail "Applications link missing"
PLIST="$APP/Contents/Info.plist"
[[ "$(plutil -extract CFBundleShortVersionString raw "$PLIST")" == "$VERSION" ]] || fail "version is not $VERSION"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/StickyCalendar")"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || fail "not universal: $ARCHS"
codesign --verify --strict "$APP" || fail "app signature invalid"
if [[ "${REQUIRE_SIGNING:-0}" == 1 ]]; then
    codesign -dvv "$APP" 2>&1 | grep -q "Authority=$DEFAULT_SIGNING_IDENTITY" \
        || fail "app not signed with $DEFAULT_SIGNING_IDENTITY"
fi
echo "OK: $DMG (version $VERSION, $ARCHS)"
```

Run: `chmod +x scripts/*.sh`

- [ ] **Step 4: Check the scripts**

Run: `./scripts/build-dmg.sh 1.2.3 2>&1 | tail -1 && ./scripts/verify-dmg.sh build/StickyCalendar-1.2.3.dmg 1.2.3`
Expected: `Built build/StickyCalendar-1.2.3.dmg (…, sha256 …)` then `OK: build/StickyCalendar-1.2.3.dmg (version 1.2.3, x86_64 arm64)`. It's signed ad-hoc if the certificate doesn't exist yet, with a warning.

Run: `./scripts/verify-dmg.sh build/StickyCalendar-1.2.3.dmg 9.9.9; echo "exit=$?"`
Expected: `FAIL: version is not 9.9.9` and `exit=1`.

Run (only while the certificate is **not** yet in the keychain): `REQUIRE_SIGNING=1 ./scripts/build-dmg.sh 1.2.3 >/dev/null; echo "exit=$?"`
Expected: `error: signing identity "Sticky Calendar Self-Signed" not found in the keychain` and `exit=1`.

Run: `./scripts/build-app.sh 2>&1 | tail -1`
Expected: `Built build/StickyCalendar.app (version 0.0.0-dev, build N)` (the local default is unchanged).

- [ ] **Step 5: Commit**

```bash
git add scripts
git commit -m "Build universal, versioned, signed apps and release DMGs

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Signing certificate

**Files:**
- Create: `scripts/create-signing-cert.sh`, `scripts/ci-import-cert.sh`

- [ ] **Step 1: Scripts**

`scripts/create-signing-cert.sh`:
```bash
#!/bin/bash
# One-time setup. Creates the self-signed code-signing certificate, imports it into your
# login keychain, and writes into OUTDIR (keep it private, never commit it):
#   signing-cert.p12          the certificate and its private key
#   signing-cert.p12.base64   value for the SIGNING_CERT_P12 GitHub secret
#   signing-cert.password     value for the SIGNING_CERT_PASSWORD GitHub secret
set -euo pipefail
source "$(dirname "$0")/lib/signing.sh"
OUT="${1:?usage: create-signing-cert.sh OUTDIR}"
NAME="$DEFAULT_SIGNING_IDENTITY"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if [[ -n "$(signing_hash "$NAME" "$KEYCHAIN")" ]]; then
    echo "\"$NAME\" is already in your keychain; not creating another." >&2
    exit 1
fi

mkdir -p "$OUT"
chmod 700 "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null

PASSWORD="$(openssl rand -base64 24)"
# macOS's `security` can't read OpenSSL 3's default PKCS#12 encryption; LibreSSL has no -legacy.
LEGACY=()
openssl version | grep -q LibreSSL || LEGACY=(-legacy)
openssl pkcs12 -export ${LEGACY[@]+"${LEGACY[@]}"} -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$OUT/signing-cert.p12" -passout "pass:$PASSWORD"

security import "$OUT/signing-cert.p12" -k "$KEYCHAIN" \
    -P "$PASSWORD" -T /usr/bin/codesign
base64 -i "$OUT/signing-cert.p12" > "$OUT/signing-cert.p12.base64"
printf '%s' "$PASSWORD" > "$OUT/signing-cert.password"
chmod 600 "$OUT"/signing-cert.*

echo "Created \"$NAME\" and imported it into $KEYCHAIN."
echo "The first build that uses it may ask to use the key: choose \"Always Allow\"."
echo "GitHub secrets are in $OUT (see RELEASING.md)."
```

`scripts/ci-import-cert.sh`:
```bash
#!/bin/bash
# CI only (fresh runner). Imports the signing certificate from the SIGNING_CERT_P12 (base64)
# and SIGNING_CERT_PASSWORD secrets into a temporary keychain codesign can use unattended.
set -euo pipefail
: "${SIGNING_CERT_P12:?secret SIGNING_CERT_P12 is not set}"
: "${SIGNING_CERT_PASSWORD:?secret SIGNING_CERT_PASSWORD is not set}"
: "${RUNNER_TEMP:?not running on GitHub Actions}"

KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 24)"
printf '%s' "$SIGNING_CERT_P12" | base64 --decode > "$RUNNER_TEMP/signing-cert.p12"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$RUNNER_TEMP/signing-cert.p12" -k "$KEYCHAIN" -P "$SIGNING_CERT_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# codesign only finds identities in keychains on the search list.
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
rm "$RUNNER_TEMP/signing-cert.p12"
security find-identity -p codesigning "$KEYCHAIN"
```

Run: `chmod +x scripts/*.sh`

- [ ] **Step 2: Test against a throwaway keychain (never the login keychain)**

```bash
D=$(mktemp -d); KC=$D/t.keychain-db
security create-keychain -p pw "$KC"; security unlock-keychain -p pw "$KC"
KEYCHAIN="$KC" ./scripts/create-signing-cert.sh "$D/s1" | head -1
KEYCHAIN="$KC" ./scripts/create-signing-cert.sh "$D/s2"; echo "exit=$?"
base64 --decode -i "$D/s1/signing-cert.p12.base64" | cmp - "$D/s1/signing-cert.p12" && echo roundtrip-ok
security delete-keychain "$KC"; rm -rf "$D"; security list-keychains -d user
```
Expected:
- the first run prints `Created "Sticky Calendar Self-Signed" and imported it into …/t.keychain-db.`;
- the second run prints `… is already in your keychain; not creating another.` and `exit=1`;
- then `roundtrip-ok`;
- the search list is back to exactly the user's login keychain.

- [ ] **Step 3: Commit**

```bash
git add scripts/create-signing-cert.sh scripts/ci-import-cert.sh
git commit -m "Add self-signed certificate setup for local and CI signing

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: Create the real certificate (ASK THE USER FIRST: it adds an identity to their login keychain)**

Run: `./scripts/create-signing-cert.sh ~/.sticky-calendar-signing`
Then: `./scripts/build-app.sh 2>&1 | tail -1 && codesign -dvv build/StickyCalendar.app 2>&1 | grep Authority && codesign -d -r- build/StickyCalendar.app 2>&1 | tail -1`
Expected: `Authority=Sticky Calendar Self-Signed`, and a designated requirement containing `certificate leaf = H"…"`. The user may see a one-time keychain prompt; they should choose **Always Allow**.

Then: `open build/StickyCalendar.app`. Once the user grants Calendar access, rebuild (`./scripts/build-app.sh`), relaunch, and confirm macOS does **not** ask again.

---

### Task 5: Homebrew cask (prepared, inactive)

**Files:**
- Create: `packaging/homebrew/sticky-calendar.rb.template`, `scripts/update-cask.sh`

- [ ] **Step 1: Template and renderer**

`packaging/homebrew/sticky-calendar.rb.template`:
```ruby
cask "sticky-calendar" do
  version "{{VERSION}}"
  sha256 "{{SHA256}}"

  url "https://github.com/ievlevpn/sticky-calendar/releases/download/v#{version}/StickyCalendar-#{version}.dmg"
  name "Sticky Calendar"
  desc "Floating, always-on-top timeline of the day's calendar"
  homepage "https://github.com/ievlevpn/sticky-calendar"

  depends_on macos: ">= :sonoma"

  app "StickyCalendar.app"

  zap trash: "~/Library/Preferences/com.ievlevpn.StickyCalendar.plist"

  caveats <<~EOS
    Sticky Calendar is not notarized by Apple. The first time you open it, macOS will
    block it: go to System Settings → Privacy & Security and click "Open Anyway".
  EOS
end
```

`scripts/update-cask.sh`:
```bash
#!/bin/bash
# Renders the Homebrew cask for a release into OUTFILE (e.g. a tap checkout's
# Casks/sticky-calendar.rb).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: update-cask.sh X.Y.Z SHA256 OUTFILE}"
SHA256="${2:?usage: update-cask.sh X.Y.Z SHA256 OUTFILE}"
OUT="${3:?usage: update-cask.sh X.Y.Z SHA256 OUTFILE}"
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || { echo "error: not a sha256: $SHA256" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
sed -e "s/{{VERSION}}/$VERSION/" -e "s/{{SHA256}}/$SHA256/" packaging/homebrew/sticky-calendar.rb.template > "$OUT"
echo "Wrote $OUT for $VERSION"
```

Run: `chmod +x scripts/update-cask.sh`

- [ ] **Step 2: Check rendering**

Run: `./scripts/update-cask.sh 1.2.3 "$(cat build/StickyCalendar-1.2.3.dmg.sha256)" build/tap/Casks/sticky-calendar.rb && ruby -c build/tap/Casks/sticky-calendar.rb && grep -E '^  (version|sha256)' build/tap/Casks/sticky-calendar.rb`
Expected: `Wrote … for 1.2.3`, `Syntax OK`, then `version "1.2.3"` and the DMG's sha256.

Run: `./scripts/update-cask.sh 1.2.3 nothex build/x.rb; echo "exit=$?"`
Expected: `error: not a sha256: nothex` and `exit=1`.

- [ ] **Step 3: Commit**

```bash
git add packaging scripts/update-cask.sh
git commit -m "Add Homebrew cask template and renderer

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Workflows and documentation

**Files:**
- Create: `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `RELEASING.md`
- Modify: `README.md` (full replacement)

- [ ] **Step 1: Workflows**

`.github/workflows/ci.yml`:
```yaml
name: CI

on:
  push:
    branches: ["**"]
  pull_request:

jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Test
        run: ./scripts/test.sh
      - name: Build app
        run: ./scripts/build-app.sh
```

`.github/workflows/release.yml`:
```yaml
name: Release

on:
  push:
    tags: ["v*"]

permissions:
  contents: write

jobs:
  release:
    runs-on: macos-15
    env:
      TAP_TOKEN: ${{ secrets.TAP_TOKEN }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0 # the build number is the commit count

      - name: Version from tag
        run: echo "VERSION=${GITHUB_REF_NAME#v}" >> "$GITHUB_ENV"

      - name: Test
        run: ./scripts/test.sh

      - name: Import signing certificate
        env:
          SIGNING_CERT_P12: ${{ secrets.SIGNING_CERT_P12 }}
          SIGNING_CERT_PASSWORD: ${{ secrets.SIGNING_CERT_PASSWORD }}
        run: ./scripts/ci-import-cert.sh

      - name: Build DMG
        env:
          REQUIRE_SIGNING: "1"
        run: ./scripts/build-dmg.sh "$VERSION"

      - name: Verify DMG
        env:
          REQUIRE_SIGNING: "1"
        run: ./scripts/verify-dmg.sh "build/StickyCalendar-$VERSION.dmg" "$VERSION"

      - name: Create GitHub release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "$GITHUB_REF_NAME" "build/StickyCalendar-$VERSION.dmg" \
            --title "Sticky Calendar $VERSION" --generate-notes

      # Inactive until the repo is public and the TAP_TOKEN secret exists (see RELEASING.md).
      - name: Update Homebrew cask
        if: env.TAP_TOKEN != ''
        run: |
          git clone "https://x-access-token:${TAP_TOKEN}@github.com/ievlevpn/homebrew-tap.git" "$RUNNER_TEMP/tap"
          ./scripts/update-cask.sh "$VERSION" "$(cat "build/StickyCalendar-$VERSION.dmg.sha256")" \
            "$RUNNER_TEMP/tap/Casks/sticky-calendar.rb"
          cd "$RUNNER_TEMP/tap"
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add Casks/sticky-calendar.rb
          git commit -m "sticky-calendar $VERSION"
          git push
```

Run: `ruby -ryaml -e 'ARGV.each { |f| YAML.load_file(f); puts "#{f}: ok" }' .github/workflows/*.yml 2>/dev/null`
Expected: both files `ok`.

- [ ] **Step 2: Docs**

`RELEASING.md`:
````markdown
# Releasing Sticky Calendar

Releases are built by GitHub Actions when a version tag is pushed. The repository is
private for now: releases exist, but nobody else can download them, the app's update
check stays silent, and the Homebrew cask is not published. See "Going public" below.

## Cutting a release

    git tag v1.2.3
    git push origin v1.2.3

The `Release` workflow tests, builds a universal DMG signed with the self-signed
certificate, verifies it, and creates the GitHub release `v1.2.3` with
`StickyCalendar-1.2.3.dmg` attached. The build number is the commit count.

To build the same DMG locally: `./scripts/build-dmg.sh 1.2.3` (then
`./scripts/verify-dmg.sh build/StickyCalendar-1.2.3.dmg 1.2.3`).

## One-time setup: signing certificate

Every build is signed with one self-signed certificate, "Sticky Calendar Self-Signed", so
the app keeps its Calendar permission across updates. (There is no Apple Developer ID;
see "First launch" below.)

1. Create it and import it into your login keychain:

       ./scripts/create-signing-cert.sh ~/.sticky-calendar-signing

   The first build that uses it may ask to use the key — choose **Always Allow**.
2. Give it to GitHub Actions:

       gh secret set SIGNING_CERT_P12 < ~/.sticky-calendar-signing/signing-cert.p12.base64
       gh secret set SIGNING_CERT_PASSWORD < ~/.sticky-calendar-signing/signing-cert.password

3. Back up `~/.sticky-calendar-signing` somewhere private (e.g. a password manager).
   Losing it means the next release is signed differently and every user is asked for
   Calendar access again.

## Going public

1. Make `ievlevpn/sticky-calendar` public. From then on the app's daily update check
   finds new releases.
2. Create a public repo `ievlevpn/homebrew-tap` with an empty `Casks/` directory.
3. Create a fine-grained personal access token with **Contents: read and write** on
   `ievlevpn/homebrew-tap` only, and save it as the `TAP_TOKEN` secret of
   `ievlevpn/sticky-calendar`.
4. Publish the cask for the current release (later releases do it automatically):

       gh release download vX.Y.Z --pattern '*.dmg'
       ./scripts/update-cask.sh X.Y.Z "$(shasum -a 256 StickyCalendar-X.Y.Z.dmg | cut -d' ' -f1)" \
           ../homebrew-tap/Casks/sticky-calendar.rb

   then commit and push the tap.

## First launch (no Apple notarization)

The app is not notarized, so macOS blocks the first launch of a downloaded copy. Open
System Settings → Privacy & Security and click **Open Anyway** once. Updates installed
over it (DMG or `brew upgrade`) keep working and keep their Calendar access.
````

`README.md` (full file):
````markdown
# Sticky Calendar

A tiny menu-bar app that shows the day's calendar as a floating, always-on-top timeline.
Scroll through the day (48 pt per hour — a taller window shows more hours); the red
ruler marks the current time and the clock button jumps back to it.
Drag to create, move and resize events; double-click to edit; ⌫ to delete; ⌘Z to undo;
⌃S (or the pin button) toggles whether the sticky stays on top of other windows.

## Install

- **DMG:** download `StickyCalendar-X.Y.Z.dmg` from
  [Releases](https://github.com/ievlevpn/sticky-calendar/releases), open it and drag the app
  to Applications.
- **Homebrew:** `brew install --cask ievlevpn/tap/sticky-calendar`

The app isn't notarized by Apple: the first time, open System Settings → Privacy & Security
and click **Open Anyway**.

## Updating

The app checks for new releases once a day (Settings → Updates) and shows
**Update Available** in its menu. It never installs anything by itself: Homebrew users run
`brew upgrade --cask sticky-calendar` (the menu item copies the command), others download
the new DMG. See [RELEASING.md](RELEASING.md) for how releases are made.

## Build

Requires macOS 14+ and the Swift toolchain (Command Line Tools are enough).

    ./scripts/test.sh               # unit tests
    ./scripts/build-app.sh          # → build/StickyCalendar.app
    ./scripts/build-app.sh --install  # also copies to ~/Applications
    ./scripts/build-dmg.sh 1.2.3    # release DMG (universal, signed)

Always launch the bundle (`open build/StickyCalendar.app`), not the bare binary —
Calendar permission belongs to the signed app.

## Notes

- Builds are signed with the self-signed "Sticky Calendar Self-Signed" certificate when it's
  in your keychain (see RELEASING.md); otherwise ad-hoc, and macOS asks for Calendar access
  again after each rebuild.
- Invitations, attendees, repeat rules and alerts are edited in Calendar.app
  (popover → Open in Calendar).
````

- [ ] **Step 3: Commit**

```bash
git add .github RELEASING.md README.md
git commit -m "Add CI and release workflows and release documentation

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Private repository, secrets, first release (outward-facing: ASK THE USER FIRST)

- [ ] **Step 1: Confirm with the user.** The branch `sticky-calendar` holds all the work. Ask whether to merge it into `master` first (recommended: fast-forward, so `master` is the default branch on GitHub). Then confirm that creating the **private** repo, pushing, and uploading the two signing secrets is OK.

- [ ] **Step 2: Create and push**

```bash
git checkout master && git merge --ff-only sticky-calendar
gh repo create ievlevpn/sticky-calendar --private --source . --remote origin --push
git push origin sticky-calendar
gh repo view ievlevpn/sticky-calendar --json visibility,defaultBranchRef
```
Expected: `"visibility":"PRIVATE"`, default branch `master`.

- [ ] **Step 3: Secrets**

```bash
gh secret set SIGNING_CERT_P12 < ~/.sticky-calendar-signing/signing-cert.p12.base64
gh secret set SIGNING_CERT_PASSWORD < ~/.sticky-calendar-signing/signing-cert.password
gh secret list
```
Expected: both secrets listed.

- [ ] **Step 4: CI passes on the push**

Run: `gh run list --workflow CI --limit 1` and `gh run watch <id> --exit-status`
Expected: success. On failure, read `gh run view <id> --log-failed` and fix with a test-first commit. A likely cause is a Swift language difference on the runner's Xcode.

- [ ] **Step 5: First release**

```bash
git tag v0.1.0 && git push origin v0.1.0
gh run watch "$(gh run list --workflow Release --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status
gh release view v0.1.0 --json assets -q '.assets[].name'
```
Expected: `StickyCalendar-0.1.0.dmg`.

- [ ] **Step 6: Install and update test (with the user)**

1. Download it: `gh release download v0.1.0 --pattern '*.dmg' --dir build/`, then run `./scripts/verify-dmg.sh build/StickyCalendar-0.1.0.dmg 0.1.0` with `REQUIRE_SIGNING=1`.
2. The user installs it from the DMG into /Applications, clicks "Open Anyway" if prompted, and grants Calendar access.
3. Tag `v0.1.1` (any small commit, e.g. a README typo) and wait for the release.
4. The user installs 0.1.1 over it. Expected: no Calendar prompt. Settings shows "Version 0.1.1 (build N)" and "Not checked yet." or "Couldn't check for updates.", because the repo is private.
