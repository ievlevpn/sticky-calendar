# Microsoft To Do and Things Sources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Microsoft To Do (Microsoft Graph, browser sign-in) and Things 3 (JavaScript for Automation) as reminder sources, next to Apple Reminders, Todoist, TickTick and Obsidian.

**Architecture:** Each service is a `ReminderSource` in `StickyCalendarCore`, so the existing `ReminderStore` (Today/Lists, undo/redo, repeats, postpone, the refresh-race rule) works unchanged. Things is reached through a small `ThingsScripting` protocol whose real implementation runs JXA with `/usr/bin/osascript`; Microsoft through `RemoteClient` (shared with Todoist/TickTick), with tokens from a `MicrosoftSession` that signs in via OAuth 2 + PKCE and a one-shot loopback listener (`LoopbackRedirect`). The app target adds chooser rows, setup screens, editor capability switches, a deadline label and 30-second polling for Things.

**Tech Stack:** Swift 5.10 package, macOS 14, SwiftUI/AppKit, Foundation `URLSession`, Network (`NWListener`), CryptoKit (SHA-256), `/usr/bin/osascript -l JavaScript`, Swift Testing (`import Testing`, `#expect`).

**Spec:** `docs/superpowers/specs/2026-09-30-microsoft-todo-and-things-design.md`

## Global Constraints

- No new package dependencies (Package.swift keeps only the vendored SwiftMath target).
- Platform floor macOS 14 (`platforms: [.macOS(.v14)]`).
- No client secret in the app; Microsoft uses a public client with PKCE (S256).
- Microsoft scopes exactly `Tasks.ReadWrite offline_access`; authority `https://login.microsoftonline.com/common/oauth2/v2.0/`.
- Tokens only in the keychain via `ReminderTokens` (account `microsoftToDo`); never in UserDefaults, never logged.
- Things bundle id `com.culturedcode.ThingsMac`; open a to-do with `things:///show?id=<id>`.
- The Microsoft chooser row is shown only when `MicrosoftAuth.clientID` is non-empty.
- Things is labelled "(beta)" in the chooser.
- Run tests with `./scripts/test.sh` (it adds the Swift Testing paths for Command Line Tools); a single suite with `./scripts/test.sh --filter <SuiteName>`.
- Code style: match the surrounding code — `///` doc comments in plain sentences, no emojis in code, SwiftUI views small and private helpers named for what they show.
- Commit messages end with the line `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>` after a blank line.

## Review Focus

1. **Concurrent token renewal (Microsoft).** Up to four lists are fetched at once; when the access token has expired, all four ask for a token together. Microsoft replaces the refresh token on every use, so four parallel renewals would race and the losers would get `invalid_grant` — signing the user out. Expected: exactly one renewal, shared by all callers. Test in Task 5.
2. **Stray requests to the loopback listener.** Browsers also ask for `/favicon.ico`, and a web page could hit the port with a wrong `state`. Expected: those get a 404/400 and the listener keeps waiting for the real redirect. Test in Task 6.
3. **Text passed into JXA.** Titles and notes with quotes, backslashes, newlines, Cyrillic and emoji must reach Things unchanged and must not break or inject into the script. Test in Task 3 (arguments go in as a JSON literal).
4. **A slow or hung Things.** With hundreds of to-dos a read may take seconds; a hung Things must not freeze the UI or pile up reads. Expected: runs off the main thread, stops after the time limit with "Things didn't answer". Test in Task 3 (timeout) — polling skips a round while a read is running (Task 4).
5. **Time zones in To Do dates.** `dueDateTime` carries a day that must be read as that calendar day wherever the user is; `reminderDateTime` is an instant in its own time zone. Expected: a task due "2026-09-30" shows on the 30th in Europe/Moscow and America/Los_Angeles alike; a reminder at 17:00 UTC shows at 20:00 in Moscow. Test in Task 7.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/StickyCalendarCore/Reminders.swift` (modify) | `ReminderItem.deadline`; `ReminderSource.supportsTime/supportsPriority`; `ReminderProvider` cases, names, `chooserCases`; `ReminderSources.make` |
| `Sources/StickyCalendarCore/ReminderStore.swift` (modify) | Never send a time or importance to a source without them |
| `Sources/StickyCalendarCore/Postpone.swift` (modify) | `isHours` |
| `Sources/StickyCalendarCore/RemoteReminders.swift` (modify) | `RemoteClient`: token provider + retry after 401, absolute-URL GET, one wait on 429, 404 message |
| `Sources/StickyCalendarCore/OsaScriptRunner.swift` (create) | Run JXA via osascript: args as JSON, time limit, error codes |
| `Sources/StickyCalendarCore/ThingsScripting.swift` (create) | `ThingsScripting` protocol, `ThingsSnapshot`, `ThingsFailure`, `ThingsContainer`, real `JXAThings` with the scripts |
| `Sources/StickyCalendarCore/ThingsSource.swift` (create) | `ReminderSource` for Things: mapping, lists, launching rule, writes |
| `Sources/StickyCalendarCore/MicrosoftAuth.swift` (create) | `PKCE`, `MicrosoftAuth` (client id, authorize URL), `MicrosoftSession` (exchange, renew, keychain) |
| `Sources/StickyCalendarCore/LoopbackRedirect.swift` (create) | One-shot local HTTP listener for the OAuth redirect |
| `Sources/StickyCalendarCore/MicrosoftToDoSource.swift` (create) | `ReminderSource` for To Do via Graph |
| `Sources/StickyCalendar/Views/ReminderSourceChooser.swift` (modify) | Rows and setup for Things and Microsoft |
| `Sources/StickyCalendar/Views/ReminderEditor.swift`, `ReminderActions.swift`, `RemindersView.swift` (modify) | Hide Time/importance/hour postpones per source; deadline label |
| `Sources/StickyCalendar/Views/Support.swift` (modify) | "Open Things", "Open To Do" |
| `Sources/StickyCalendar/AppDelegate.swift` (modify) | 30-second polling for Things |
| `Resources/Info.plist` (modify) | Apple Events usage text mentions Things |
| `Tests/StickyCalendarCoreTests/StubHTTP.swift` (modify) | Form-encoded bodies; `Retry-After: 0` on 429 |
| Tests (create) | `SourceCapabilityTests.swift`, `RemoteClientTests.swift`, `OsaScriptRunnerTests.swift`, `ThingsSourceTests.swift`, `MicrosoftAuthTests.swift`, `LoopbackRedirectTests.swift`, `MicrosoftToDoSourceTests.swift` |
| `RELEASING.md`, `CHANGELOG.md`, `README.md` (modify) | Registration steps, notes |

Spec clarifications made while planning (implement as written here):
- Things to-dos that are in no project, no area and not in the Inbox (e.g. scheduled for today without a project) go in a list "Other" (`things-other`), shown only when it has to-dos. New to-dos created there go to Things without a container (the Inbox if undated).
- Microsoft: when a date *without* a time is saved for a task whose time came from its reminder, the reminder is switched off, so it reads back without a time.
- A 404 from any remote source reads "That reminder no longer exists in <service>."
- The "Things is closed" notice is the error banner's "Things is closed. ⌘R opens it." (⌘R starts Things), rather than a separate link.

---

### Task 1: Source capabilities, deadlines and the store's rules

**Files:**
- Modify: `Sources/StickyCalendarCore/Reminders.swift` (ReminderItem ~line 18–56; protocol extension ~line 97–101)
- Modify: `Sources/StickyCalendarCore/ReminderStore.swift` (`edit` ~272, `postpone` ~295, `insert` ~375)
- Modify: `Sources/StickyCalendarCore/Postpone.swift`
- Modify: `Tests/StickyCalendarCoreTests/FakeReminderSource.swift`
- Test: `Tests/StickyCalendarCoreTests/SourceCapabilityTests.swift`

**Interfaces:**
- Produces: `ReminderItem.deadline: Date?` (init parameter `deadline: Date? = nil`, last); `ReminderSource.supportsTime: Bool` and `supportsPriority: Bool` (default `true` in the protocol extension); `Postpone.isHours: Bool`; `FakeReminderSource.supportsTime/supportsPriority` settable vars.

- [ ] **Step 1: Write the failing tests**

Create `Tests/StickyCalendarCoreTests/SourceCapabilityTests.swift`:

```swift
import Foundation
import Testing
@testable import StickyCalendarCore

/// A source without times (Things) or importance (Things) never receives them.
@MainActor
struct SourceCapabilityTests {
    let source = FakeReminderSource()
    let store: ReminderStore

    init() {
        let name = "SourceCapabilityTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        store = ReminderStore(source: source, settings: ReminderSettings(defaults: defaults), calendar: utc, now: { at(12) })
        source.stored = [ReminderItem(id: "1", title: "Plan", listID: "home", due: at(0))]
        source.supportsTime = false
        source.supportsPriority = false
    }

    @Test func editKeepsTheDayAndDropsTheTimeAndImportance() async {
        await store.reload()
        await store.edit(store.items[0], title: "Plan", due: at(15, 30, day: 29), dueHasTime: true, priority: .high, notes: nil)
        #expect(source.stored[0].due == at(0, day: 29) && !source.stored[0].dueHasTime)
        #expect(source.stored[0].priority == .none)
    }

    @Test func postponingByHoursBecomesADay() async {
        await store.reload()
        await store.postpone(store.items[0], .threeHours)
        #expect(source.stored[0].due == at(0) && !source.stored[0].dueHasTime)
    }

    @Test func aTypedTimeIsDroppedFromANewOne() async {
        await store.reload()
        await store.add("Call Sam tomorrow 10am")
        let added = source.stored.first { $0.title == "Call Sam" }
        #expect(added?.dueHasTime == false)
        #expect(added.flatMap(\.due).map { utc.component(.hour, from: $0) } == 0)
    }

    @Test func hourPostponesAreMarked() {
        #expect(Postpone.allCases.filter(\.isHours) == [.oneHour, .threeHours])
    }

    @Test func deadlinesDefaultToNone() {
        #expect(ReminderItem(title: "x", listID: "l").deadline == nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/test.sh --filter SourceCapability`
Expected: compile errors — `supportsTime`, `supportsPriority`, `isHours`, `deadline` not found.

- [ ] **Step 3: Implement**

In `Reminders.swift`, `ReminderItem`: add after `nextDue`:

```swift
    /// When it must be done by, where the source keeps that apart from the due date (Things).
    public var deadline: Date?
```

extend the init signature with `, deadline: Date? = nil` after `isRepeating: Bool = false` and set `self.deadline = deadline` at the end of the init.

In the `ReminderSource` protocol, after `var canEditNotes: Bool { get }`:

```swift
    /// Whether due dates can have a time of day (Things' can't).
    var supportsTime: Bool { get }
    /// Whether reminders have an importance (Things' don't).
    var supportsPriority: Bool { get }
```

and in `public extension ReminderSource`:

```swift
    var supportsTime: Bool { true }
    var supportsPriority: Bool { true }
```

In `Postpone.swift`, add inside the enum:

```swift
    /// "+1 h" and "+3 h": they need a source whose due dates have times.
    public var isHours: Bool { self == .oneHour || self == .threeHours }
```

In `ReminderStore.swift` add a helper near `current(_:)`:

```swift
    /// `item` as its source can keep it: no time, or no importance, where it has none.
    private func fitted(_ item: ReminderItem) -> ReminderItem {
        var item = item
        if !(source?.supportsTime ?? true), item.dueHasTime {
            item.due = item.due.map { calendar.startOfDay(for: $0) }
            item.dueHasTime = false
        }
        if !(source?.supportsPriority ?? true) { item.priority = .none }
        return item
    }
```

In `edit`, replace `guard changed != original else { return }` with:

```swift
        changed = fitted(changed)
        guard changed != original else { return }
```

In `postpone`, replace `guard changed != original else { return }` with:

```swift
        changed = fitted(changed)
        guard changed != original else { return }
```

In `insert`, change `var fresh = item` to `var fresh = fitted(item)`.

In `FakeReminderSource`, add:

```swift
    var supportsTime = true
    var supportsPriority = true
```

- [ ] **Step 4: Run the tests**

Run: `./scripts/test.sh`
Expected: all pass (the new suite included).

- [ ] **Step 5: Commit**

```bash
git add Sources/StickyCalendarCore/Reminders.swift Sources/StickyCalendarCore/ReminderStore.swift Sources/StickyCalendarCore/Postpone.swift Tests/StickyCalendarCoreTests/FakeReminderSource.swift Tests/StickyCalendarCoreTests/SourceCapabilityTests.swift
git commit -m "Reminders: sources can lack times or importance; deadlines on reminders

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: RemoteClient — token provider, absolute URLs, 429, 404

**Files:**
- Modify: `Sources/StickyCalendarCore/RemoteReminders.swift` (`RemoteClient`, top of file)
- Modify: `Tests/StickyCalendarCoreTests/StubHTTP.swift`
- Test: `Tests/StickyCalendarCoreTests/RemoteClientTests.swift`

**Interfaces:**
- Produces: `RemoteClient(base:token:session:service:tokenProvider:)` where `tokenProvider: (@MainActor @Sendable (_ renew: Bool) async throws -> String)? = nil`; `RemoteClient.get(url: URL) async throws -> Any`; `StubHTTP.Call.body` also filled from `application/x-www-form-urlencoded` bodies; `StubHTTP` adds header `Retry-After: 0` to every 429 response.

- [ ] **Step 1: Extend StubHTTP**

In `StubHTTP.startLoading()`, replace the line building `body` with:

```swift
        var body = bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        if body.isEmpty, let bodyData, let text = String(data: bodyData, encoding: .utf8), text.contains("=") {
            // A form (OAuth's token endpoint).
            var form = URLComponents()
            form.percentEncodedQuery = text
            for item in form.queryItems ?? [] { body[item.name] = item.value ?? "" }
        }
```

and replace the `HTTPURLResponse` line with:

```swift
        var headers = ["Content-Type": "application/json"]
        if status == 429 { headers["Retry-After"] = "0" }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/StickyCalendarCoreTests/RemoteClientTests.swift`:

```swift
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
```

`StubHTTP.Call` has no `headers` yet: add `let headers: [String: String]` to `Call` and fill it in `startLoading()` with `request.allHTTPHeaderFields ?? [:]` (note: `URLSessionConfiguration.httpAdditionalHeaders` are not in `allHTTPHeaderFields`, only per-request ones, which is where `Authorization` is set).

- [ ] **Step 3: Run to verify it fails**

Run: `./scripts/test.sh --filter RemoteClientTests`
Expected: compile errors (`tokenProvider`, `get(url:)`) or failures.

- [ ] **Step 4: Implement**

Replace `struct RemoteClient` in `RemoteReminders.swift` with:

```swift
/// JSON over HTTPS with a bearer token, for the Todoist, TickTick and Microsoft To Do sources.
struct RemoteClient: Sendable {
    let base: URL
    let token: String
    let session: URLSession
    /// "Todoist", "TickTick": for error messages.
    let service: String
    /// Asked for the token before each request instead of `token` (Microsoft's expire hourly),
    /// and once more with `renew` after a 401, the request then retried once.
    var tokenProvider: (@MainActor @Sendable (_ renew: Bool) async throws -> String)? = nil

    enum Failure: Error { case unauthorized }

    func get(_ path: String, query: [URLQueryItem] = []) async throws -> Any {
        try await send("GET", path, query: query, body: nil)
    }

    /// A page link the server handed back (Microsoft's `@odata.nextLink`).
    func get(url: URL) async throws -> Any {
        try await perform("GET", url: url, body: nil)
    }

    @discardableResult
    func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]?) async throws -> Any {
        var parts = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        return try await perform(method, url: parts.url!, body: body)
    }

    private func perform(_ method: String, url: URL, body: [String: Any]?,
                         renewed: Bool = false, waited: Bool = false) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = method
        let bearer = try await tokenProvider?(renewed) ?? token
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ReminderSourceError("Couldn't reach \(service): \(error.localizedDescription)")
        }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 401, tokenProvider != nil, !renewed {
            return try await perform(method, url: url, body: body, renewed: true, waited: waited)
        }
        if status == 401 || status == 403 { throw Failure.unauthorized }
        if status == 429, !waited {
            let seconds = min(Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1, 30)
            try await Task.sleep(for: .seconds(seconds))
            return try await perform(method, url: url, body: body, renewed: renewed, waited: true)
        }
        if status == 404 { throw ReminderSourceError("That reminder no longer exists in \(service).") }
        guard (200..<300).contains(status) else {
            throw ReminderSourceError("\(service) couldn't do that (error \(status)).")
        }
        return data.isEmpty ? [String: Any]() : (try? JSONSerialization.jsonObject(with: data)) ?? [String: Any]()
    }
}
```

- [ ] **Step 5: Run all tests**

Run: `./scripts/test.sh`
Expected: all pass (Todoist and TickTick suites unchanged in behaviour).

- [ ] **Step 6: Commit**

```bash
git add Sources/StickyCalendarCore/RemoteReminders.swift Tests/StickyCalendarCoreTests/StubHTTP.swift Tests/StickyCalendarCoreTests/RemoteClientTests.swift
git commit -m "RemoteClient: token provider with a retry after 401, page links, one wait on 429, 404 message

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Running JXA, and the Things scripting layer

**Files:**
- Create: `Sources/StickyCalendarCore/OsaScriptRunner.swift`
- Create: `Sources/StickyCalendarCore/ThingsScripting.swift`
- Test: `Tests/StickyCalendarCoreTests/OsaScriptRunnerTests.swift`

**Interfaces:**
- Produces:
  - `OsaScriptRunner(timeout: Duration = .seconds(20))`, `func run(_ script: String, args: Any = [String: Any]()) async throws -> String`; errors `OsaScriptRunner.Failure { notAllowed, appNotRunning, noSuchObject, timedOut, failed(code: Int?, message: String) }`.
  - `@MainActor protocol ThingsScripting: AnyObject` with `isRunning() -> Bool`, `launch() async`, `snapshot(completedSince: Date) async throws -> ThingsSnapshot`, `setStatus(id: String, completed: Bool) async throws`, `setName(id: String, name: String) async throws`, `setNotes(id: String, notes: String) async throws`, `schedule(id: String, on day: Date?) async throws`, `create(name: String, notes: String?, in container: ThingsContainer, on day: Date?) async throws -> String`, `delete(id: String) async throws`.
  - `ThingsSnapshot { open: [ToDo], done: [ToDo], inbox: [String], lists: [Container] }`, `ThingsSnapshot.ToDo { id, name, notes: String?, status: String, when: Date?, deadline: Date?, completed: Date? }`, `ThingsSnapshot.Container { id, name, kind: String, toDoIDs: [String] }`, `ThingsSnapshot.decode(_ json: String) throws -> ThingsSnapshot`.
  - `enum ThingsContainer: Equatable { case inbox, project(String), area(String), none }`.
  - `enum ThingsFailure: Error, Equatable { case notAllowed, notRunning, timedOut, notFound, other(String) }`.
  - `final class JXAThings: ThingsScripting` (real).

- [ ] **Step 1: Write the failing tests**

Create `Tests/StickyCalendarCoreTests/OsaScriptRunnerTests.swift` (these run real `osascript` but never touch Things):

```swift
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
```

(`1_790_546_400` is 2026-09-27T22:00:00Z: `date -u -r 1790546400`.)

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/test.sh --filter OsaScriptRunner`
Expected: compile errors (`OsaScriptRunner`, `ThingsSnapshot` not found).

- [ ] **Step 3: Implement `OsaScriptRunner.swift`**

```swift
import Foundation

/// Runs JavaScript for Automation with /usr/bin/osascript, in its own process: off the main
/// thread, stoppable after a time limit, and with the Automation permission asked for on
/// behalf of this app (macOS attributes a child process's Apple Events to its parent).
public struct OsaScriptRunner: Sendable {
    public enum Failure: Error, Equatable {
        /// -1743: the user hasn't allowed this app to control the other one.
        case notAllowed
        /// -600: the app isn't running.
        case appNotRunning
        /// -1728: no such object (e.g. a to-do deleted meanwhile).
        case noSuchObject
        case timedOut
        case failed(code: Int?, message: String)
    }

    public let timeout: Duration

    public init(timeout: Duration = .seconds(20)) { self.timeout = timeout }

    /// Runs `script` with `args` available to it as the constant `args`, and returns what the
    /// script's last expression evaluates to, as text. Arguments go in as a JSON literal, so
    /// no text in them can end a string or run as code.
    public func run(_ script: String, args: Any = [String: Any]()) async throws -> String {
        let json = try JSONSerialization.data(withJSONObject: args, options: [.fragmentsAllowed])
        let source = "const args = \(String(decoding: json, as: UTF8.self));\n\(script)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-"]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let exited = AsyncStream<Void> { continuation in
            process.terminationHandler = { _ in continuation.yield(); continuation.finish() }
        }
        try process.run()
        // Read while it runs: a full pipe would otherwise stall it.
        let out = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
        let err = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }
        input.fileHandleForWriting.write(Data(source.utf8))
        try? input.fileHandleForWriting.close()
        let timedOut = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in exited {}; return false }
            group.addTask { try? await Task.sleep(for: timeout); return true }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        if timedOut, process.isRunning {
            process.terminate()
            throw Failure.timedOut
        }
        let text = String(decoding: await out.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            let message = String(decoding: await err.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Self.failure(from: message)
        }
        return text
    }

    /// "execution error: Error: Not authorized to send Apple events to Things3. (-1743)"
    static func failure(from message: String) -> Failure {
        let pattern = try! NSRegularExpression(pattern: #"\((-?\d+)\)\s*$"#)
        let range = NSRange(message.startIndex..., in: message)
        let code = pattern.firstMatch(in: message, range: range)
            .flatMap { Range($0.range(at: 1), in: message) }
            .flatMap { Int(message[$0]) }
        switch code {
        case -1743: return .notAllowed
        case -600: return .appNotRunning
        case -1728: return .noSuchObject
        default: return .failed(code: code, message: message)
        }
    }
}
```

The test `scriptErrorsCarryTheirNumber` pins the error-number parsing.

- [ ] **Step 4: Implement `ThingsScripting.swift`**

```swift
import AppKit
import Foundation

/// Where a new Things to-do goes.
public enum ThingsContainer: Equatable, Sendable {
    case inbox, project(String), area(String)
    /// No project or area: scheduled if it has a date, else Things puts it in the Inbox.
    case none
}

public enum ThingsFailure: Error, Equatable {
    case notAllowed, notRunning, timedOut, notFound, other(String)
}

/// One read of Things: open to-dos, those completed since a day began, and which list each
/// is in.
public struct ThingsSnapshot: Decodable, Equatable, Sendable {
    public struct ToDo: Decodable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var notes: String?
        /// "open", "completed", "canceled".
        public var status: String
        /// "When": the day it's planned for.
        public var when: Date?
        /// Things' "due date": the deadline.
        public var deadline: Date?
        public var completed: Date?

        public init(id: String, name: String, notes: String? = nil, status: String = "open",
                    when: Date? = nil, deadline: Date? = nil, completed: Date? = nil) {
            self.id = id; self.name = name; self.notes = notes; self.status = status
            self.when = when; self.deadline = deadline; self.completed = completed
        }
    }

    public struct Container: Decodable, Equatable, Sendable {
        public var id: String
        public var name: String
        /// "project" or "area".
        public var kind: String
        public var toDoIDs: [String]

        public init(id: String, name: String, kind: String, toDoIDs: [String]) {
            self.id = id; self.name = name; self.kind = kind; self.toDoIDs = toDoIDs
        }
    }

    public var open: [ToDo]
    public var done: [ToDo]
    public var inbox: [String]
    public var lists: [Container]

    public init(open: [ToDo] = [], done: [ToDo] = [], inbox: [String] = [], lists: [Container] = []) {
        self.open = open; self.done = done; self.inbox = inbox; self.lists = lists
    }

    public static func decode(_ json: String) throws -> ThingsSnapshot {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = withFraction.date(from: text) ?? plain.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
            }
            return date
        }
        return try decoder.decode(ThingsSnapshot.self, from: Data(json.utf8))
    }
}

/// What `ThingsSource` needs from Things.
@MainActor
public protocol ThingsScripting: AnyObject {
    func isRunning() -> Bool
    /// Starts Things in the background.
    func launch() async
    func snapshot(completedSince: Date) async throws -> ThingsSnapshot
    func setStatus(id: String, completed: Bool) async throws
    func setName(id: String, name: String) async throws
    func setNotes(id: String, notes: String) async throws
    /// Sets "When" to `day`; nil moves it to Anytime.
    func schedule(id: String, on day: Date?) async throws
    /// Returns the new to-do's id.
    func create(name: String, notes: String?, in container: ThingsContainer, on day: Date?) async throws -> String
    /// Moves it to Things' Trash.
    func delete(id: String) async throws
}

/// Things through JavaScript for Automation. Built-in lists are addressed by id
/// (`TMInboxListSource`, `TMLogbookListSource`, `TMNextListSource` = Anytime), so it works
/// whatever language Things runs in. Every property is read in bulk, one Apple Event each.
@MainActor
public final class JXAThings: ThingsScripting {
    public static let bundleID = "com.culturedcode.ThingsMac"
    private let runner: OsaScriptRunner

    public init(runner: OsaScriptRunner = OsaScriptRunner()) { self.runner = runner }

    public func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    public func launch() async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        // Give it a moment to answer Apple Events.
        for _ in 0..<20 where !isRunning() { try? await Task.sleep(for: .milliseconds(250)) }
        try? await Task.sleep(for: .seconds(1))
    }

    public func snapshot(completedSince: Date) async throws -> ThingsSnapshot {
        let json = try await run(Self.readScript, ["since": ISO8601DateFormatter().string(from: completedSince)])
        do { return try ThingsSnapshot.decode(json) } catch { throw ThingsFailure.other("Things answered in a way Sticky Calendar doesn't understand.") }
    }

    public func setStatus(id: String, completed: Bool) async throws {
        _ = try await run("T.toDos.byId(args.id).status = args.status; ''", ["id": id, "status": completed ? "completed" : "open"])
    }

    public func setName(id: String, name: String) async throws {
        _ = try await run("T.toDos.byId(args.id).name = args.name; ''", ["id": id, "name": name])
    }

    public func setNotes(id: String, notes: String) async throws {
        _ = try await run("T.toDos.byId(args.id).notes = args.notes; ''", ["id": id, "notes": notes])
    }

    public func schedule(id: String, on day: Date?) async throws {
        _ = try await run("""
            const t = T.toDos.byId(args.id);
            if (args.day) { T.schedule(t, {for: new Date(args.day)}); } else { T.move(t, {to: T.lists.byId('TMNextListSource')}); }
            ''
            """, ["id": id, "day": day.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()])
    }

    public func create(name: String, notes: String?, in container: ThingsContainer, on day: Date?) async throws -> String {
        let (kind, containerID): (String, String) = switch container {
        case .inbox: ("inbox", "")
        case let .project(id): ("project", id)
        case let .area(id): ("area", id)
        case .none: ("none", "")
        }
        return try await run("""
            const t = T.ToDo({name: args.name, notes: args.notes || ''});
            if (args.kind === 'project') { T.projects.byId(args.container).toDos.push(t); }
            else if (args.kind === 'area') { T.areas.byId(args.container).toDos.push(t); }
            else { T.lists.byId('TMInboxListSource').toDos.push(t); }
            const made = T.toDos.byId(t.id());
            if (args.day) { T.schedule(made, {for: new Date(args.day)}); }
            made.id()
            """, ["name": name, "notes": notes ?? "", "kind": kind, "container": containerID,
                  "day": day.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()])
    }

    public func delete(id: String) async throws {
        _ = try await run("T.delete(T.toDos.byId(args.id)); ''", ["id": id])
    }

    private func run(_ body: String, _ args: [String: Any]) async throws -> String {
        do {
            return try await runner.run("const T = Application('\(Self.bundleID)');\n\(body)", args: args)
        } catch let failure as OsaScriptRunner.Failure {
            switch failure {
            case .notAllowed: throw ThingsFailure.notAllowed
            case .appNotRunning: throw ThingsFailure.notRunning
            case .noSuchObject: throw ThingsFailure.notFound
            case .timedOut: throw ThingsFailure.timedOut
            case let .failed(_, message): throw ThingsFailure.other(message)
            }
        }
    }

    /// Reads everything in bulk. Projects are to-dos too in Things' dictionary, so they're
    /// left out of the open to-dos by id.
    static let readScript = """
        function iso(d) { return d ? d.toISOString() : null; }
        function bulk(items) {
          const ids = items.id();
          if (ids.length === 0) { return []; }
          const names = items.name(), notes = items.notes(), status = items.status(),
                when = items.activationDate(), deadline = items.dueDate(), done = items.completionDate();
          return ids.map((id, i) => ({id: id, name: names[i], notes: notes[i], status: status[i],
                                     when: iso(when[i]), deadline: iso(deadline[i]), completed: iso(done[i])}));
        }
        const projects = T.projects.whose({status: 'open'});
        const projectIDs = projects.id(), projectNames = projects.name();
        const open = bulk(T.toDos.whose({status: 'open'})).filter(t => projectIDs.indexOf(t.id) < 0);
        const done = bulk(T.lists.byId('TMLogbookListSource').toDos.whose({completionDate: {_greaterThan: new Date(args.since)}}));
        const lists = [];
        projectIDs.forEach((id, i) => lists.push({id: id, name: projectNames[i], kind: 'project', toDoIDs: T.projects.byId(id).toDos.id()}));
        const areaIDs = T.areas.id(), areaNames = T.areas.name();
        areaIDs.forEach((id, i) => lists.push({id: id, name: areaNames[i], kind: 'area', toDoIDs: T.areas.byId(id).toDos.id()}));
        JSON.stringify({open: open, done: done, inbox: T.lists.byId('TMInboxListSource').toDos.id(), lists: lists})
        """
}
```

The scripts can only be checked against the real Things app (Real-account checklist, spec); tests here cover the runner and decoding.

- [ ] **Step 5: Run the tests**

Run: `./scripts/test.sh --filter OsaScriptRunner` then `./scripts/test.sh`
Expected: PASS (the timeout test takes about a second).

- [ ] **Step 6: Commit**

```bash
git add Sources/StickyCalendarCore/OsaScriptRunner.swift Sources/StickyCalendarCore/ThingsScripting.swift Tests/StickyCalendarCoreTests/OsaScriptRunnerTests.swift
git commit -m "Things scripting: run JXA via osascript with a time limit; Things snapshot and commands

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: ThingsSource, and Things in the app

**Files:**
- Create: `Sources/StickyCalendarCore/ThingsSource.swift`
- Modify: `Sources/StickyCalendarCore/Reminders.swift` (`ReminderProvider`, `ReminderSources.make`)
- Modify: `Sources/StickyCalendar/Views/ReminderSourceChooser.swift`, `ReminderEditor.swift`, `ReminderActions.swift`, `RemindersView.swift`, `Support.swift`
- Modify: `Sources/StickyCalendar/AppDelegate.swift` (`scheduleReminderRefresh`)
- Modify: `Resources/Info.plist`
- Test: `Tests/StickyCalendarCoreTests/ThingsSourceTests.swift`

**Interfaces:**
- Consumes: `ThingsScripting`, `ThingsSnapshot`, `ThingsContainer`, `ThingsFailure`, `JXAThings` (Task 3); `KnownTasks` (existing, `RemoteReminders.swift`); `supportsTime`, `supportsPriority`, `deadline`, `Postpone.isHours` (Task 1).
- Produces: `ThingsSource(things: ThingsScripting = JXAThings(), calendar: Calendar = .autoupdatingCurrent, now: @escaping () -> Date = Date.init)`; `ThingsSource.inboxID = "things-inbox"`, `ThingsSource.otherID = "things-other"`; `ReminderProvider.things`; `ReminderProvider.chooserCases: [ReminderProvider]`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/StickyCalendarCoreTests/ThingsSourceTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/test.sh --filter ThingsSource`
Expected: compile error, `ThingsSource` not found.

- [ ] **Step 3: Implement `ThingsSource.swift`**

```swift
import Foundation

/// Reminders from Things 3 on this Mac, through `ThingsScripting`. The due date is Things'
/// "When" (so Today matches Things' Today; a past "When" counts as today, as Things rolls it
/// over); deadlines are shown apart. Things has no times or importance for us.
@MainActor
public final class ThingsSource: ReminderSource {
    public var onChange: (() -> Void)?

    public static let inboxID = "things-inbox"
    /// To-dos in no project, no area and not in the Inbox (e.g. planned for today).
    public static let otherID = "things-other"

    private let things: ThingsScripting
    private let calendar: Calendar
    private let now: () -> Date
    private var listInfos: [ReminderListInfo] = []
    private var kinds: [String: String] = [:]
    private var rejected = false
    /// Things is started for the first load and after ⌘R, not by the regular checks, so
    /// quitting it stays quit.
    private var mayLaunch = true
    private var known = KnownTasks()

    private static let palette: [RGBA] = [0x4A90D9, 0x7B61FF, 0x2FB57A, 0xE58A2B, 0xD9534F, 0x3AAFB9, 0xB85FC6, 0x8C9A2B]
        .map(RGBA.init(hex:))

    public init(things: ThingsScripting = JXAThings(), calendar: Calendar = .autoupdatingCurrent,
                now: @escaping () -> Date = Date.init) {
        self.things = things
        self.calendar = calendar
        self.now = now
    }

    public func currentAccess() -> CalendarAccess { rejected ? .denied : .granted }
    public func requestAccess() async -> CalendarAccess { currentAccess() }
    public func lists() -> [ReminderListInfo] { listInfos }
    public func defaultListID() -> String? { Self.inboxID }
    public var supportsTime: Bool { false }
    public var supportsPriority: Bool { false }
    public func refreshIfNeeded() { mayLaunch = true }

    public func reminders(completedSince: Date) async throws -> [ReminderItem] {
        if !things.isRunning() {
            guard mayLaunch else { throw ReminderSourceError("Things is closed. ⌘R opens it.") }
            await things.launch()
        }
        mayLaunch = false
        let snapshot = try await call { try await self.things.snapshot(completedSince: completedSince) }
        var listOf: [String: String] = [:]
        for container in snapshot.lists { for id in container.toDoIDs where listOf[id] == nil { listOf[id] = container.id } }
        for id in snapshot.inbox { listOf[id] = Self.inboxID }
        let today = calendar.startOfDay(for: now())
        var items = snapshot.open.map { item($0, listID: listOf[$0.id] ?? Self.otherID, today: today) }
        let open = Set(items.map(\.id))
        items += snapshot.done.filter { !open.contains($0.id) }
            .map { item($0, listID: listOf[$0.id] ?? Self.otherID, today: today) }
        var infos = [ReminderListInfo(id: Self.inboxID, title: "Inbox", color: RGBA(hex: 0x3A8DDE))]
        kinds = [:]
        for (index, container) in snapshot.lists.enumerated() {
            kinds[container.id] = container.kind
            infos.append(ReminderListInfo(id: container.id, title: container.name, color: Self.palette[index % Self.palette.count]))
        }
        if items.contains(where: { $0.listID == Self.otherID }) {
            infos.append(ReminderListInfo(id: Self.otherID, title: "Other", color: RGBA(hex: 0x8E8E93)))
        }
        listInfos = infos
        known.read(items)
        return items
    }

    public func save(_ item: ReminderItem) async throws -> ReminderItem {
        try await call {
            if item.isNew {
                let container: ThingsContainer = switch item.listID {
                case Self.inboxID: .inbox
                case Self.otherID: .none
                case let id where self.kinds[id] == "project": .project(id)
                case let id where self.kinds[id] == "area": .area(id)
                default: .inbox
                }
                var saved = item
                saved.id = try await self.things.create(name: item.title, notes: item.notes, in: container, on: item.due)
                self.known.saved(saved)
                return saved
            }
            let before = self.known[item.id]
            if before?.title != item.title { try await self.things.setName(id: item.id, name: item.title) }
            if before?.notes != item.notes { try await self.things.setNotes(id: item.id, notes: item.notes ?? "") }
            if before?.due != item.due { try await self.things.schedule(id: item.id, on: item.due) }
            if before?.isCompleted != item.isCompleted { try await self.things.setStatus(id: item.id, completed: item.isCompleted) }
            self.known.saved(item)
            return item
        }
    }

    public func remove(_ item: ReminderItem) async throws {
        try await call { try await self.things.delete(id: item.id) }
    }

    public func link(for item: ReminderItem) -> URL? {
        var parts = URLComponents(string: "things:///show")!
        parts.queryItems = [URLQueryItem(name: "id", value: item.id)]
        return parts.url
    }

    private func item(_ todo: ThingsSnapshot.ToDo, listID: String, today: Date) -> ReminderItem {
        var due = todo.when.map { calendar.startOfDay(for: $0) }
        if let day = due, day < today, todo.status == "open" { due = today }
        return ReminderItem(
            id: todo.id, title: todo.name, listID: listID, due: due, dueHasTime: false,
            isCompleted: todo.status == "completed", completionDate: todo.completed,
            notes: todo.notes?.isEmpty == false ? todo.notes : nil,
            deadline: todo.deadline.map { calendar.startOfDay(for: $0) }
        )
    }

    /// Runs `body`, turning Things' failures into what the store shows.
    private func call<T>(_ body: () async throws -> T) async throws -> T {
        do {
            let result = try await body()
            rejected = false
            return result
        } catch let failure as ThingsFailure {
            switch failure {
            case .notAllowed:
                rejected = true
                throw ReminderSourceError("Sticky Calendar isn't allowed to control Things.")
            case .notRunning: throw ReminderSourceError("Things is closed. ⌘R opens it.")
            case .timedOut: throw ReminderSourceError("Things didn't answer.")
            case .notFound: throw ReminderSourceError("That reminder no longer exists in Things.")
            case let .other(message): throw ReminderSourceError("Things couldn't do that: \(message)")
            }
        }
    }
}
```

Note: `KnownTasks.read(_:)` and `saved(_:)` are internal in `RemoteReminders.swift` and usable here (same module). The `known` ordering for the "Other" check in `writesOnlyWhatChanged`: the test expects name then status — keep the `save` order above.

- [ ] **Step 4: Run the source tests**

Run: `./scripts/test.sh --filter ThingsSource`
Expected: PASS.

- [ ] **Step 5: Add the provider and wire the app**

`Reminders.swift`, `ReminderProvider`: add `case things` after `obsidian`; in `name` add `case .things: "Things"`; add:

```swift
    /// The sources the chooser offers, in its order.
    public static var chooserCases: [ReminderProvider] { [.appleReminders, .todoist, .tickTick, .obsidian, .things] }
```

`ReminderSources.make`: add `case .things: ThingsSource()`.

`ReminderSourceChooser.swift`:
- `ForEach(ReminderProvider.allCases, …)` → `ForEach(ReminderProvider.chooserCases, …)`; wrap each row button with `.disabled(!Self.isAvailable(provider))`.
- Add:

```swift
    static func isAvailable(_ provider: ReminderProvider) -> Bool {
        provider != .things || NSWorkspace.shared.urlForApplication(withBundleIdentifier: JXAThings.bundleID) != nil
    }
```

- `row(_:)`: dim unavailable rows with `.opacity(Self.isAvailable(provider) ? 1 : 0.5)`.
- `setup(for:)` add:

```swift
        case .things:
            if store.access == .denied {
                Text("Sticky Calendar isn't allowed to control Things. Allow it in System Settings → Privacy & Security → Automation, under Sticky Calendar.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Automation Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
                .font(.system(size: 11))
            } else {
                Text("To-dos from Things on this Mac: its Today, Inbox, projects and areas. macOS will ask whether Sticky Calendar may control Things.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
```

- `pick`: `case .things: break`; `isReady`: `case .things: true`; `connect()` candidate: `case .things: ThingsSource()`; the save switch: `case .things: break`.
- `icon`: `case .things: "checkmark.circle.fill"`; `tint`: `case .things: Color(.sRGB, red: 0.23, green: 0.55, blue: 0.87)`; `blurb`: `case .things: isAvailable(.things) ? "Things 3 on this Mac (beta)" : "Things isn't installed"`.

`Support.swift`, `openReminderSource`: `case .things: openApp(JXAThings.bundleID, orWeb: "https://culturedcode.com/things/")`.

`ReminderEditor.swift`: add `let supportsTime: Bool` and `let supportsPriority: Bool` properties and init parameters (after `canEditNotes`). Wrap the `Toggle("Time", …)` in `if hasDate && supportsTime`; wrap the Importance `HStack` in `if supportsPriority { … }`; in `postponeButtons`, iterate `Postpone.allCases.filter { supportsTime || !$0.isHours }`.

`ReminderActions.swift`: pass `supportsTime: store.source?.supportsTime ?? true, supportsPriority: store.source?.supportsPriority ?? true` to `ReminderEditor`; in `ReminderMenu`'s Postpone menu iterate `Postpone.allCases.filter { (store.source?.supportsTime ?? true) || !$0.isHours }`.

`RemindersView.swift`, in `row(_:in:)` after the due label `if let due = dueLabel(…) { … }` block, add:

```swift
            if let deadline = item.deadline, !item.isCompleted {
                Text("Deadline " + dayText(deadline, hasTime: false))
                    .font(.system(size: 10.5 * zoom).monospacedDigit())
                    .foregroundStyle(deadline < Calendar.autoupdatingCurrent.startOfDay(for: Date()) ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
```

`AppDelegate.swift`: add `private var reminderTicks = 0` next to `reminderRefresh`, and replace `scheduleReminderRefresh()` with:

```swift
    /// Todoist, TickTick and To Do don't announce changes: look again every few minutes;
    /// Things every 30 seconds. A check still under way isn't doubled.
    private func scheduleReminderRefresh() {
        reminderRefresh = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reminderTicks += 1
                guard self.reminderSettings.isVisible, !self.reminderStore.isLoading else { return }
                guard self.reminderSettings.provider == .things || self.reminderTicks % 10 == 0 else { return }
                Task { await self.reminderStore.reload() }
            }
        }
    }
```

`Resources/Info.plist`: set `NSAppleEventsUsageDescription` to `Sticky Calendar opens Calendar on the day you're viewing, and reads and changes your Things to-dos when Things is your reminders source.`

- [ ] **Step 6: Build and run all tests**

Run: `swift build 2>&1 | grep -E "error|warning: .*(Things|Reminder)|Build complete"` then `./scripts/test.sh`
Expected: `Build complete!`, all tests pass. Any `switch` over `ReminderProvider` the compiler flags as non-exhaustive gets a `.things` arm following the patterns above.

- [ ] **Step 7: Commit**

```bash
git add Sources Resources/Info.plist Tests/StickyCalendarCoreTests/ThingsSourceTests.swift
git commit -m "Reminders: Things 3 as a source (beta)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Microsoft sign-in logic (PKCE, authorize URL, tokens)

**Files:**
- Create: `Sources/StickyCalendarCore/MicrosoftAuth.swift`
- Test: `Tests/StickyCalendarCoreTests/MicrosoftAuthTests.swift`

**Interfaces:**
- Produces:
  - `struct PKCE { let verifier: String; let challenge: String; static func make() -> PKCE; init(verifier: String) }` (challenge = base64url(SHA-256(verifier)), no padding).
  - `enum MicrosoftAuth { static let clientID: String; static let tokenAccount = "microsoftToDo"; static var isAvailable: Bool; static func authorizeURL(clientID: String = clientID, redirect: URL, pkce: PKCE, state: String) -> URL; static func randomState() -> String }`.
  - `@MainActor final class MicrosoftSession` with `init(clientID: String = MicrosoftAuth.clientID, refreshToken: String? = ReminderTokens.token(for: MicrosoftAuth.tokenAccount), session: URLSession = .shared, now: @escaping () -> Date = Date.init, keep: @escaping (String?) -> Void = { ReminderTokens.setToken($0, for: MicrosoftAuth.tokenAccount) })`, `var isSignedIn: Bool`, `func exchange(code: String, verifier: String, redirect: URL) async throws`, `func token(renew: Bool) async throws -> String`, `func signOut()`; errors `MicrosoftSession.Failure { signedOut, refused }`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/StickyCalendarCoreTests/MicrosoftAuthTests.swift`:

```swift
import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct MicrosoftAuthTests {
    final class Kept { var tokens: [String?] = [] }

    private static let tokenPath = "/common/oauth2/v2.0/token"

    @Test func pkceChallengeIsTheHashedVerifier() {
        // RFC 7636, appendix B.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(PKCE.make().verifier.count >= 43)
    }

    @Test func theAuthorizeURLCarriesEverything() {
        let pkce = PKCE(verifier: "v".padding(toLength: 43, withPad: "v", startingAt: 0))
        let url = MicrosoftAuth.authorizeURL(clientID: "cid", redirect: URL(string: "http://localhost:5555")!, pkce: pkce, state: "s1")
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: parts.queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(parts.host == "login.microsoftonline.com" && parts.path == "/common/oauth2/v2.0/authorize")
        #expect(query["client_id"] == "cid" && query["response_type"] == "code")
        #expect(query["redirect_uri"] == "http://localhost:5555" && query["scope"] == "Tasks.ReadWrite offline_access")
        #expect(query["code_challenge"] == pkce.challenge && query["code_challenge_method"] == "S256" && query["state"] == "s1")
    }

    @Test func exchangingACodeKeepsTheRefreshToken() async throws {
        let (session, log) = StubHTTP.session { _ in
            (200, ["access_token": "A1", "refresh_token": "R1", "expires_in": 3600])
        }
        let kept = Kept()
        let auth = MicrosoftSession(clientID: "cid", refreshToken: nil, session: session, now: { at(12) }, keep: { kept.tokens.append($0) })
        try await auth.exchange(code: "C", verifier: "V", redirect: URL(string: "http://localhost:5555")!)
        #expect(try await auth.token(renew: false) == "A1")
        #expect(kept.tokens == ["R1"] && auth.isSignedIn)
        let body = log()[0].body
        #expect(log()[0].path == Self.tokenPath && body["grant_type"] as? String == "authorization_code")
        #expect(body["code"] as? String == "C" && body["code_verifier"] as? String == "V" && body["client_id"] as? String == "cid")
        #expect(body["client_secret"] == nil)
    }

    @Test func anExpiringTokenIsRenewedOnceForManyCallers() async throws {
        let (session, log) = StubHTTP.session { call in
            (200, ["access_token": "A2", "refresh_token": "R2", "expires_in": 3600])
        }
        let kept = Kept()
        let auth = MicrosoftSession(clientID: "cid", refreshToken: "R1", session: session, now: { at(12) }, keep: { kept.tokens.append($0) })
        async let a = auth.token(renew: false)
        async let b = auth.token(renew: false)
        async let c = auth.token(renew: false)
        async let d = auth.token(renew: false)
        let tokens = try await [a, b, c, d]
        #expect(tokens == ["A2", "A2", "A2", "A2"])
        #expect(log().filter { $0.path == Self.tokenPath }.count == 1)
        #expect(log()[0].body["refresh_token"] as? String == "R1" && kept.tokens == ["R2"])
    }

    @Test func aRefusedRefreshSignsOut() async {
        let (session, _) = StubHTTP.session { _ in (400, ["error": "invalid_grant"]) }
        let kept = Kept()
        let auth = MicrosoftSession(clientID: "cid", refreshToken: "R1", session: session, now: { at(12) }, keep: { kept.tokens.append($0) })
        await #expect(throws: MicrosoftSession.Failure.refused) { try await auth.token(renew: true) }
        #expect(!auth.isSignedIn && kept.tokens == [nil])
    }

    @Test func withoutARefreshTokenItIsSignedOut() async {
        let auth = MicrosoftSession(clientID: "cid", refreshToken: nil, session: .shared, now: { at(12) }, keep: { _ in })
        await #expect(throws: MicrosoftSession.Failure.signedOut) { try await auth.token(renew: false) }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/test.sh --filter MicrosoftAuth`
Expected: compile errors.

- [ ] **Step 3: Implement `MicrosoftAuth.swift`**

```swift
import CryptoKit
import Foundation

/// A PKCE pair (RFC 7636): the app keeps the verifier and sends its hash.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func make() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return PKCE(verifier: base64URL(Data(bytes)))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Signing in to Microsoft (Entra ID, personal and work accounts) as a public client: no
/// secret, PKCE, and a redirect to a local port.
public enum MicrosoftAuth {
    /// The app's registration in Microsoft Entra (see RELEASING.md). Empty until registered,
    /// and then Microsoft To Do isn't offered.
    public static let clientID = ""
    public static let tokenAccount = "microsoftToDo"
    static let authority = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/")!
    static let scopes = "Tasks.ReadWrite offline_access"

    public static var isAvailable: Bool { !clientID.isEmpty }

    public static func authorizeURL(clientID: String = clientID, redirect: URL, pkce: PKCE, state: String) -> URL {
        var parts = URLComponents(url: authority.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirect.absoluteString),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return parts.url!
    }

    public static func randomState() -> String { PKCE.make().verifier }
}

/// Holds a Microsoft sign-in: the refresh token (kept in the keychain) and an access token
/// (in memory). Renewals happen one at a time, as Microsoft replaces the refresh token on
/// every use: parallel renewals would race, and the losers would be refused.
@MainActor
public final class MicrosoftSession {
    public enum Failure: Error, Equatable {
        /// Never signed in, or signed out.
        case signedOut
        /// Microsoft refused the refresh token (expired, revoked, password changed).
        case refused
    }

    private let clientID: String
    private let session: URLSession
    private let now: () -> Date
    private let keep: (String?) -> Void
    private var refreshToken: String?
    private var accessToken: String?
    private var expiry = Date.distantPast
    private var renewal: Task<String, Error>?

    public init(clientID: String = MicrosoftAuth.clientID,
                refreshToken: String? = ReminderTokens.token(for: MicrosoftAuth.tokenAccount),
                session: URLSession = .shared, now: @escaping () -> Date = Date.init,
                keep: @escaping (String?) -> Void = { ReminderTokens.setToken($0, for: MicrosoftAuth.tokenAccount) }) {
        self.clientID = clientID
        self.refreshToken = refreshToken
        self.session = session
        self.now = now
        self.keep = keep
    }

    public var isSignedIn: Bool { refreshToken != nil }

    /// Finishes signing in with the code from the redirect.
    public func exchange(code: String, verifier: String, redirect: URL) async throws {
        _ = try await redeem(["grant_type": "authorization_code", "code": code,
                              "code_verifier": verifier, "redirect_uri": redirect.absoluteString])
    }

    /// A usable access token: the current one while it has 5 minutes left, else a renewed
    /// one; `renew` forces renewal (after a 401).
    public func token(renew: Bool) async throws -> String {
        if !renew, let accessToken, expiry > now().addingTimeInterval(300) { return accessToken }
        if let renewal { return try await renewal.value }
        guard let refreshToken else { throw Failure.signedOut }
        let task = Task { try await self.redeem(["grant_type": "refresh_token", "refresh_token": refreshToken]) }
        renewal = task
        defer { renewal = nil }
        return try await task.value
    }

    public func signOut() {
        refreshToken = nil
        accessToken = nil
        keep(nil)
    }

    private func redeem(_ fields: [String: String]) async throws -> String {
        var request = URLRequest(url: MicrosoftAuth.authority.appendingPathComponent("token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = (fields.merging(["client_id": clientID, "scope": MicrosoftAuth.scopes]) { a, _ in a })
            .sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // "+" is literal in a query but a space in a form: encode it.
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ReminderSourceError("Couldn't reach Microsoft: \(error.localizedDescription)")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 400, json["error"] as? String == "invalid_grant" {
            signOut()
            throw Failure.refused
        }
        guard (200..<300).contains(status), let access = json["access_token"] as? String else {
            throw ReminderSourceError("Microsoft didn't accept the sign-in (error \(status)).")
        }
        accessToken = access
        expiry = now().addingTimeInterval(json["expires_in"] as? Double ?? 3600)
        if let refresh = json["refresh_token"] as? String {
            refreshToken = refresh
            keep(refresh)
        }
        return access
    }
}
```

- [ ] **Step 4: Run tests**

Run: `./scripts/test.sh --filter MicrosoftAuth` then `./scripts/test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/StickyCalendarCore/MicrosoftAuth.swift Tests/StickyCalendarCoreTests/MicrosoftAuthTests.swift
git commit -m "Microsoft sign-in: PKCE, authorize URL, token exchange and one-at-a-time renewal

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: LoopbackRedirect

**Files:**
- Create: `Sources/StickyCalendarCore/LoopbackRedirect.swift`
- Test: `Tests/StickyCalendarCoreTests/LoopbackRedirectTests.swift`

**Interfaces:**
- Produces: `final class LoopbackRedirect` with `init(state: String, timeout: Duration = .seconds(300))`, `func start() async throws -> URL` (returns `http://localhost:<port>`), `func code() async throws -> String`, `func cancel()`; errors `LoopbackRedirect.Failure { cancelled, timedOut, denied(String), couldNotListen }`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/StickyCalendarCoreTests/LoopbackRedirectTests.swift`:

```swift
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
        async let code = redirect.code()
        let (status, page) = await get(URL(string: "\(base)/?code=abc&state=s1")!)
        #expect(status == 200 && page.contains("Signed in to Sticky Calendar"))
        #expect(try await code == "abc")
    }

    @Test func ignoresStrayRequestsAndWrongStates() async throws {
        let redirect = LoopbackRedirect(state: "s1")
        let base = try await redirect.start()
        async let code = redirect.code()
        #expect(await get(URL(string: "\(base)/favicon.ico")!).0 == 404)
        #expect(await get(URL(string: "\(base)/?code=evil&state=other")!).0 == 400)
        let port = base.port!
        _ = await get(URL(string: "http://127.0.0.1:\(port)/?code=good&state=s1")!)
        #expect(try await code == "good")
    }

    @Test func anErrorFromMicrosoftEndsIt() async throws {
        let redirect = LoopbackRedirect(state: "s1")
        let base = try await redirect.start()
        async let code = redirect.code()
        _ = await get(URL(string: "\(base)/?error=access_denied&error_description=The%20user%20declined&state=s1")!)
        await #expect(throws: LoopbackRedirect.Failure.denied("The user declined")) { try await code }
    }

    @Test func givesUpAfterItsTimeLimit() async throws {
        let redirect = LoopbackRedirect(state: "s1", timeout: .milliseconds(300))
        _ = try await redirect.start()
        await #expect(throws: LoopbackRedirect.Failure.timedOut) { try await redirect.code() }
    }

    @Test func cancelEndsTheWait() async throws {
        let redirect = LoopbackRedirect(state: "s1")
        _ = try await redirect.start()
        async let code = redirect.code()
        try await Task.sleep(for: .milliseconds(100))
        redirect.cancel()
        await #expect(throws: LoopbackRedirect.Failure.cancelled) { try await code }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/test.sh --filter LoopbackRedirect`
Expected: compile error.

- [ ] **Step 3: Implement `LoopbackRedirect.swift`**

```swift
import Foundation
import Network

/// Waits, on a free port reachable only from this Mac, for the browser to come back from
/// Microsoft's sign-in with a code. Answers that one request with a page the user can close,
/// ignores anything else (a favicon, a wrong `state`), and stops after one code, an error,
/// a cancel, or its time limit.
public final class LoopbackRedirect: @unchecked Sendable {
    public enum Failure: Error, Equatable {
        case cancelled, timedOut, couldNotListen
        /// Microsoft sent an error back (e.g. the user declined).
        case denied(String)
    }

    private let state: String
    private let timeout: Duration
    private let queue = DispatchQueue(label: "LoopbackRedirect")
    private let lock = NSLock()
    private var listener: NWListener?
    private var outcome: Result<String, Failure>?
    private var waiter: CheckedContinuation<String, Error>?

    public init(state: String, timeout: Duration = .seconds(300)) {
        self.state = state
        self.timeout = timeout
    }

    /// Starts listening; returns the redirect URI to give Microsoft.
    public func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.acceptLocalOnly = true
        let listener: NWListener
        do { listener = try NWListener(using: parameters, on: .any) } catch { throw Failure.couldNotListen }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed, .cancelled:
                    resumed = true
                    continuation.resume(throwing: Failure.couldNotListen)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        return URL(string: "http://localhost:\(port)")!
    }

    /// Waits for the code.
    public func code() async throws -> String {
        let limit = timeout
        Task { [weak self] in
            try? await Task.sleep(for: limit)
            self?.finish(.failure(.timedOut))
        }
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let outcome {
                lock.unlock()
                continuation.resume(with: outcome.mapError { $0 as Error })
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    public func cancel() { finish(.failure(.cancelled)) }

    private func finish(_ result: Result<String, Failure>) {
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = result
        let waiter = waiter
        self.waiter = nil
        lock.unlock()
        listener?.cancel()
        waiter?.resume(with: result.mapError { $0 as Error })
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self else { return connection.cancel() }
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let target = request.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? ""
            let parts = URLComponents(string: "http://localhost\(target)")
            let query = Dictionary((parts?.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { a, _ in a }
            guard parts?.path == "/" || parts?.path == "", query["code"] != nil || query["error"] != nil else {
                return self.reply(connection, status: "404 Not Found", message: "Nothing here.")
            }
            guard query["state"] == self.state else {
                return self.reply(connection, status: "400 Bad Request", message: "This sign-in link doesn't match. Try again from Sticky Calendar.")
            }
            if let error = query["error"] {
                let reason = query["error_description"].flatMap { $0.isEmpty ? nil : $0 } ?? error
                self.reply(connection, status: "200 OK", message: "Sign-in didn't finish: \(reason)")
                self.finish(.failure(.denied(reason)))
            } else if let code = query["code"] {
                self.reply(connection, status: "200 OK", message: "Signed in to Sticky Calendar. You can close this tab.")
                self.finish(.success(code))
            }
        }
    }

    private func reply(_ connection: NWConnection, status: String, message: String) {
        let escaped = message.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        let body = """
            <!doctype html><meta charset="utf-8"><title>Sticky Calendar</title>
            <body style="font: 15px -apple-system, sans-serif; margin: 3em; color: #333">\(escaped)</body>
            """
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
```

Note: the `denied` test expects `error_description` decoded by `URLComponents` ("The user declined"); `queryItems` percent-decodes values.

- [ ] **Step 4: Run tests**

Run: `./scripts/test.sh --filter LoopbackRedirect` then `./scripts/test.sh`
Expected: PASS. If `NWListener` on `.loopback` doesn't answer `localhost` over IPv6 on this machine, the first test fails at `get(base…)`; then change `start()` to return `http://127.0.0.1:<port>` only if both families can't be served — but first check `curl -v http://localhost:<port>/` and `curl -v http://127.0.0.1:<port>/` by hand.

- [ ] **Step 5: Commit**

```bash
git add Sources/StickyCalendarCore/LoopbackRedirect.swift Tests/StickyCalendarCoreTests/LoopbackRedirectTests.swift
git commit -m "Microsoft sign-in: one-shot loopback listener for the redirect

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: MicrosoftToDoSource

**Files:**
- Create: `Sources/StickyCalendarCore/MicrosoftToDoSource.swift`
- Test: `Tests/StickyCalendarCoreTests/MicrosoftToDoSourceTests.swift`

**Interfaces:**
- Consumes: `RemoteClient` with `tokenProvider` and `get(url:)` (Task 2); `MicrosoftSession.token(renew:)`, `isSignedIn`, `MicrosoftSession.Failure` (Task 5); `KnownTasks`, `RemoteDates` (existing).
- Produces: `MicrosoftToDoSource(auth: MicrosoftSession, session: URLSession = .shared, calendar: Calendar = .autoupdatingCurrent)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/StickyCalendarCoreTests/MicrosoftToDoSourceTests.swift`:

```swift
import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct MicrosoftToDoSourceTests {
    static func graph(_ call: StubHTTP.Call) -> (status: Int, json: Any) {
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
        await #expect(throws: ReminderSourceError.self) { try await source.reminders(completedSince: at(0)) }
        #expect(source.currentAccess() == .notDetermined || source.currentAccess() == .denied)
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
```

(`at(_:_:day:)` builds 2026-09-<day> in UTC and lets the day run over: `at(0, day: 32)` is 2026-10-02.)

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/test.sh --filter MicrosoftToDoSource`
Expected: compile error.

- [ ] **Step 3: Implement `MicrosoftToDoSource.swift`**

```swift
import Foundation

/// Reminders from Microsoft To Do through Microsoft Graph. Lists are To Do's lists; "Tasks"
/// is the default and "Flagged email" is read-only. To Do's due date has no time, so a time
/// lives in the task's reminder: a reminder on the due day (or without a due day) is the
/// due time.
@MainActor
public final class MicrosoftToDoSource: ReminderSource {
    public var onChange: (() -> Void)?

    private let auth: MicrosoftSession
    private let client: RemoteClient
    private let calendar: Calendar
    private var listInfos: [ReminderListInfo] = []
    private var defaultID: String?
    private var rejected = false
    private var filterUnsupported = false
    private var known = KnownTasks()

    private static let palette: [RGBA] = [0x2564CF, 0x7B61FF, 0x2FB57A, 0xE58A2B, 0xD9534F, 0x3AAFB9, 0xB85FC6, 0x8C9A2B]
        .map(RGBA.init(hex:))

    public init(auth: MicrosoftSession, session: URLSession = .shared, calendar: Calendar = .autoupdatingCurrent) {
        self.auth = auth
        self.calendar = calendar
        client = RemoteClient(base: URL(string: "https://graph.microsoft.com/v1.0/")!, token: "", session: session,
                              service: "Microsoft To Do", tokenProvider: { renew in try await auth.token(renew: renew) })
    }

    public func currentAccess() -> CalendarAccess {
        !auth.isSignedIn ? (rejected ? .denied : .notDetermined) : rejected ? .denied : .granted
    }

    public func requestAccess() async -> CalendarAccess { currentAccess() }
    public func lists() -> [ReminderListInfo] { listInfos }
    public func defaultListID() -> String? { defaultID ?? listInfos.first(where: \.isWritable)?.id }

    public func reminders(completedSince: Date) async throws -> [ReminderItem] {
        try await authorized {
            let rows = try await self.pages("me/todo/lists")
            var infos: [ReminderListInfo] = []
            for (index, row) in rows.enumerated() {
                guard let id = row["id"] as? String, let name = row["displayName"] as? String else { continue }
                let kind = row["wellknownListName"] as? String
                if kind == "defaultList" { self.defaultID = id }
                infos.append(ReminderListInfo(id: id, title: name, color: Self.palette[index % Self.palette.count],
                                              isWritable: kind != "flaggedEmails"))
            }
            var items: [ReminderItem] = []
            // Four lists at a time.
            for start in stride(from: 0, to: infos.count, by: 4) {
                let chunk = infos[start..<min(start + 4, infos.count)]
                try await withThrowingTaskGroup(of: [ReminderItem].self) { group in
                    for list in chunk {
                        group.addTask { try await self.tasks(in: list.id, completedSince: completedSince) }
                    }
                    for try await found in group { items += found }
                }
            }
            self.listInfos = infos
            self.known.read(items)
            return items
        }
    }

    public func save(_ item: ReminderItem) async throws -> ReminderItem {
        try await authorized {
            let path = "me/todo/lists/\(item.listID)/tasks"
            if item.isNew {
                let row = try await self.client.send("POST", path, body: self.fields(item, before: nil)) as? [String: Any]
                let saved = row.flatMap { self.item($0, listID: item.listID) } ?? item
                self.known.saved(saved)
                return saved
            }
            let body = self.fields(item, before: self.known[item.id])
            guard !body.isEmpty else { return item }
            let row = try await self.client.send("PATCH", "\(path)/\(item.id)", body: body) as? [String: Any]
            var saved = row.flatMap { self.item($0, listID: item.listID) } ?? item
            saved.nextDue = item.nextDue
            self.known.saved(saved)
            return saved
        }
    }

    public func remove(_ item: ReminderItem) async throws {
        try await authorized { try await self.client.send("DELETE", "me/todo/lists/\(item.listID)/tasks/\(item.id)", body: nil) }
    }

    /// To Do on the web (the format is to be confirmed with a real account).
    public func link(for item: ReminderItem) -> URL? {
        URL(string: "https://to-do.live.com/tasks/id/\(item.id)/details")
    }

    // MARK: Private

    private func authorized<T>(_ body: () async throws -> T) async throws -> T {
        do {
            let result = try await body()
            rejected = false
            return result
        } catch MicrosoftSession.Failure.refused, MicrosoftSession.Failure.signedOut, RemoteClient.Failure.unauthorized {
            rejected = true
            throw ReminderSourceError("Microsoft To Do signed you out. Sign in again.")
        }
    }

    /// A list's open tasks and those completed since `since`.
    private func tasks(in listID: String, completedSince since: Date) async throws -> [ReminderItem] {
        let path = "me/todo/lists/\(listID)/tasks"
        let stamp = RemoteDates.utcString(since, format: "yyyy-MM-dd'T'HH:mm:ss")
        var rows: [[String: Any]]
        if !filterUnsupported {
            do {
                rows = try await pages(path, filter: "status ne 'completed'")
                rows += try await pages(path, filter: "status eq 'completed' and completedDateTime/dateTime ge '\(stamp)'")
            } catch is ReminderSourceError {
                // Graph may not filter tasks: fetch all and filter here.
                filterUnsupported = true
                rows = try await pages(path)
            }
        } else {
            rows = try await pages(path)
        }
        return rows.compactMap { item($0, listID: listID) }
            .filter { !$0.isCompleted || ($0.completionDate ?? .distantPast) >= since }
    }

    private func pages(_ path: String, filter: String? = nil) async throws -> [[String: Any]] {
        var page = try await client.get(path, query: filter.map { [URLQueryItem(name: "$filter", value: $0)] } ?? [])
            as? [String: Any] ?? [:]
        var rows = page["value"] as? [[String: Any]] ?? []
        while let next = (page["@odata.nextLink"] as? String).flatMap(URL.init(string:)), rows.count < 5000 {
            page = try await client.get(url: next) as? [String: Any] ?? [:]
            rows += page["value"] as? [[String: Any]] ?? []
        }
        return rows
    }

    private func item(_ row: [String: Any], listID: String) -> ReminderItem? {
        guard let id = row["id"] as? String, let title = row["title"] as? String else { return nil }
        let day = ((row["dueDateTime"] as? [String: Any])?["dateTime"] as? String)
            .flatMap { RemoteDates.day(String($0.prefix(10)), in: calendar.timeZone) }
        let reminder = row["isReminderOn"] as? Bool == true ? instant(row["reminderDateTime"]) : nil
        let due: Date?
        let hasTime: Bool
        if let reminder, day.map({ calendar.isDate(reminder, inSameDayAs: $0) }) ?? true {
            (due, hasTime) = (reminder, true)
        } else {
            (due, hasTime) = (day, false)
        }
        let body = row["body"] as? [String: Any]
        var notes = body?["content"] as? String
        if body?["contentType"] as? String == "html" {
            notes = notes?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
        }
        notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let priority: ReminderPriority = switch row["importance"] as? String {
        case "high": .high
        case "low": .low
        default: .none
        }
        return ReminderItem(
            id: id, title: title, listID: listID, due: due, dueHasTime: hasTime,
            isCompleted: row["status"] as? String == "completed",
            completionDate: instant(row["completedDateTime"]),
            notes: notes?.isEmpty == false ? notes : nil, priority: priority,
            isRepeating: row["recurrence"] is [String: Any]
        )
    }

    /// A Graph `dateTimeTimeZone`, as an instant.
    private func instant(_ value: Any?) -> Date? {
        guard let value = value as? [String: Any], let text = value["dateTime"] as? String else { return nil }
        let zone = (value["timeZone"] as? String).flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "UTC")!
        return RemoteDates.dateTime(String(text.prefix(19)), floating: zone)
    }

    /// What to send: only what changed since `before` (everything for a new task).
    private func fields(_ item: ReminderItem, before: ReminderItem?) -> [String: Any] {
        var body: [String: Any] = [:]
        let zone = calendar.timeZone.identifier
        if before?.title != item.title { body["title"] = item.title }
        if before?.notes != item.notes, item.notes != nil || before != nil {
            body["body"] = ["content": item.notes ?? "", "contentType": "text"]
        }
        if before?.priority != item.priority, item.priority != .none || before != nil {
            body["importance"] = switch item.priority {
            case .none: "normal"
            case .low: "low"
            case .medium, .high: "high"
            }
        }
        if before?.due != item.due || before?.dueHasTime != item.dueHasTime, item.due != nil || before != nil {
            if let due = item.due {
                body["dueDateTime"] = ["dateTime": RemoteDates.dayString(due, in: calendar.timeZone) + "T00:00:00", "timeZone": zone]
                if item.dueHasTime {
                    let local = DateFormatter()
                    local.locale = Locale(identifier: "en_US_POSIX")
                    local.timeZone = calendar.timeZone
                    local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                    body["reminderDateTime"] = ["dateTime": local.string(from: due), "timeZone": zone]
                    body["isReminderOn"] = true
                } else if before?.dueHasTime == true {
                    body["isReminderOn"] = false
                }
            } else {
                body["dueDateTime"] = NSNull()
                if before?.dueHasTime == true { body["isReminderOn"] = false }
            }
        }
        if before?.isCompleted != item.isCompleted, item.isCompleted || before != nil {
            body["status"] = item.isCompleted ? "completed" : "notStarted"
        }
        return body
    }
}
```

Note `RemoteDates.day(_:in:)` and `RemoteDates.dayString(_:in:)` exist (`RemoteReminders.swift`, `enum RemoteDates`); `RemoteDates.dateTime(_:floating:)` parses `yyyy-MM-dd'T'HH:mm:ss` in the given zone.

- [ ] **Step 4: Run tests**

Run: `./scripts/test.sh --filter MicrosoftToDoSource` then `./scripts/test.sh`
Expected: PASS. If `StubHTTP.Call` has no public memberwise init with `headers:` (used by `fallsBackWhenTheFilterIsRejected`), add one in `StubHTTP.swift`.

- [ ] **Step 5: Commit**

```bash
git add Sources/StickyCalendarCore/MicrosoftToDoSource.swift Tests/StickyCalendarCoreTests/MicrosoftToDoSourceTests.swift Tests/StickyCalendarCoreTests/StubHTTP.swift
git commit -m "Reminders: Microsoft To Do source via Microsoft Graph

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Microsoft To Do in the app

**Files:**
- Modify: `Sources/StickyCalendarCore/Reminders.swift` (`ReminderProvider`, `chooserCases`, `ReminderSources.make`)
- Modify: `Sources/StickyCalendar/Views/ReminderSourceChooser.swift`
- Modify: `Sources/StickyCalendar/Views/Support.swift`
- Modify: `RELEASING.md`

**Interfaces:**
- Consumes: `MicrosoftAuth`, `PKCE`, `MicrosoftSession` (Task 5), `LoopbackRedirect` (Task 6), `MicrosoftToDoSource` (Task 7).
- Produces: `ReminderProvider.microsoftToDo`.

- [ ] **Step 1: Provider and source construction**

`ReminderProvider`: add `case microsoftToDo`; `name`: `case .microsoftToDo: "Microsoft To Do"`; `chooserCases`:

```swift
    public static var chooserCases: [ReminderProvider] {
        [.appleReminders, .todoist, .tickTick] + (MicrosoftAuth.isAvailable ? [.microsoftToDo] : []) + [.obsidian, .things]
    }
```

`ReminderSources.make`: `case .microsoftToDo: MicrosoftToDoSource(auth: MicrosoftSession())`.

Add a test to `Tests/StickyCalendarCoreTests/ReminderStoreTests.swift` (end of the `ReminderStoreTests` struct):

```swift
    @Test func microsoftIsOfferedOnlyOnceRegistered() {
        #expect(ReminderProvider.chooserCases.contains(.microsoftToDo) == MicrosoftAuth.isAvailable)
        #expect(ReminderProvider.chooserCases.contains(.things))
    }
```

Run: `./scripts/test.sh --filter microsoftIsOfferedOnlyOnceRegistered`
Expected: PASS once the build compiles (next step).

- [ ] **Step 2: Chooser sign-in flow**

In `ReminderSourceChooser`, add state:

```swift
    @State private var signIn: LoopbackRedirect?
```

`setup(for:)`, add:

```swift
        case .microsoftToDo:
            Text(store.access == .denied
                 ? "Microsoft To Do signed you out. Sign in again to continue."
                 : "Sign in with your Microsoft account in the browser. Sticky Calendar can then read and change your To Do tasks.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if signIn != nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Finish signing in in your browser…").font(.system(size: 11))
                    Spacer()
                    Button("Cancel") { signIn?.cancel() }
                }
            }
```

`pick`: `case .microsoftToDo: break`; `isReady`: `case .microsoftToDo: signIn == nil`; the connect button's title: `provider == .appleReminders ? "Use Apple Reminders" : provider == .microsoftToDo ? "Sign in with Microsoft" : "Connect"`.

Add (it's called from `connect()`, below):

```swift
    /// Browser sign-in: listen locally, open Microsoft's page, trade the code for tokens,
    /// try one fetch, then save.
    private func signInToMicrosoft() {
        let pkce = PKCE.make()
        let state = MicrosoftAuth.randomState()
        let redirect = LoopbackRedirect(state: state)
        signIn = redirect
        error = nil
        Task {
            defer { signIn = nil }
            do {
                let uri = try await redirect.start()
                NSWorkspace.shared.open(MicrosoftAuth.authorizeURL(redirect: uri, pkce: pkce, state: state))
                let code = try await redirect.code()
                let auth = MicrosoftSession(refreshToken: nil)
                try await auth.exchange(code: code, verifier: pkce.verifier, redirect: uri)
                let candidate = MicrosoftToDoSource(auth: auth)
                _ = try await candidate.reminders(completedSince: Date())
                settings.setProvider(.microsoftToDo)
                store.use(candidate)
                NSApp.activate()
            } catch LoopbackRedirect.Failure.cancelled {
                return
            } catch LoopbackRedirect.Failure.timedOut {
                error = "Signing in took too long. Try again."
            } catch let LoopbackRedirect.Failure.denied(reason) {
                error = "Microsoft didn't sign you in: \(reason)"
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
```

In `connect()`'s save switch add `case .microsoftToDo: break`, and after `settings.setProvider(provider)` add (so switching away signs out of Microsoft):

```swift
            ReminderTokens.setToken(nil, for: MicrosoftAuth.tokenAccount)
```

`icon`: `case .microsoftToDo: "checkmark.circle"`; `tint`: `case .microsoftToDo: Color(.sRGB, red: 0.15, green: 0.39, blue: 0.81)`; `blurb`: `case .microsoftToDo: "Sign in with your Microsoft account"`.

In `connect()`, turn the `let candidate: ReminderSource = switch provider { … }` expression into a statement so Microsoft can leave it (it signs in on its own path, above):

```swift
        let candidate: ReminderSource
        switch provider {
        case .appleReminders: candidate = ReminderKitSource()
        case .todoist: candidate = TodoistSource(token: token)
        case .tickTick: candidate = TickTickSource(token: token)
        case .obsidian: candidate = ObsidianSource(vault: URL(fileURLWithPath: vaultPath), inboxPath: inboxPath)
        case .things: candidate = ThingsSource()
        case .microsoftToDo: return signInToMicrosoft()
        }
```.

- [ ] **Step 3: "Open To Do"**

`Support.swift`, `openReminderSource`: `case .microsoftToDo: openApp("com.microsoft.to-do-mac", orWeb: "https://to-do.live.com/tasks/")`.

- [ ] **Step 4: Registration steps**

Append to `RELEASING.md`:

```markdown
## Microsoft To Do: app registration (once)

Microsoft To Do is offered only when `MicrosoftAuth.clientID`
(`Sources/StickyCalendarCore/MicrosoftAuth.swift`) is set.

1. Sign in to https://entra.microsoft.com with a Microsoft account (a free Azure account
   creates the directory if you have none).
2. App registrations → New registration: name "Sticky Calendar"; supported account types
   "Accounts in any organizational directory and personal Microsoft accounts".
3. Authentication → Add a platform → Mobile and desktop applications → custom redirect URI
   `http://localhost`. Under Advanced settings, set "Allow public client flows" to Yes.
4. API permissions: Microsoft Graph → Delegated → `Tasks.ReadWrite` (and `offline_access`).
   No admin consent needed.
5. Copy the Application (client) ID into `MicrosoftAuth.clientID`. It's not a secret.

The consent screen shows the app as unverified; personal accounts can still sign in, some
work or school directories need an admin to approve it.
```

- [ ] **Step 5: Build and test**

Run: `swift build 2>&1 | grep -E "error|Build complete"` then `./scripts/test.sh`
Expected: `Build complete!`, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources RELEASING.md Tests/StickyCalendarCoreTests/ReminderStoreTests.swift
git commit -m "Reminders: Microsoft To Do in the chooser (browser sign-in), hidden until registered

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: README and changelog

**Files:**
- Modify: `README.md` (the reminders paragraph listing sources, ~line 35)
- Modify: `CHANGELOG.md` (new "Unreleased" section at the top)

- [ ] **Step 1: README**

In the sentence "The checklist button shows your reminders from Apple Reminders, Todoist, TickTick or the tasks in an Obsidian vault", change the list to "Apple Reminders, Todoist, TickTick, Things (beta), the tasks in an Obsidian vault, or Microsoft To Do", and add after that paragraph's first sentence: "With Things, the day is Things' "When" (so Today matches Things' Today) and deadlines show beside it."

- [ ] **Step 2: Changelog**

Add at the top, under the intro paragraph:

```markdown
## Unreleased

### Added
- **Things 3 as a reminders source (beta)**: Today, Inbox, projects and areas from Things on this Mac. The day is Things' "When", so Today matches Things' Today; deadlines show beside it ("Deadline Fri", red once missed). Tick, add, rename, reschedule and delete; changes made in Things show up within 30 seconds (or with ⌘R). macOS asks once whether Sticky Calendar may control Things.
- **Microsoft To Do as a reminders source**, signing in with your Microsoft account in the browser (it appears once the app's Microsoft registration is in place).
```

- [ ] **Step 3: Verify and commit**

Run: `./scripts/test.sh` — Expected: all pass.

```bash
git add README.md CHANGELOG.md
git commit -m "README and changelog: Things and Microsoft To Do sources

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Real-account checklist (after the plan; from the spec)

- To Do: full sign-in with a personal account; web link format; `$filter` on status and completion date; ticking a repeating task (same id advancing, or a new task); notes saved as plain text; Flagged email read-only; `com.microsoft.to-do-mac` bundle id.
- Things: the bulk JXA read against the real app, and its speed with a few hundred to-dos; scripting id = link id; untick via status open; built-in list ids (`TMInboxListSource`, `TMLogbookListSource`, `TMNextListSource`) in a non-English Things; how repeating copies look.
