import Foundation
import Testing
@testable import StickyCalendarCore

struct ObsidianTaskTests {
    @Test func readsTitleStateAndDates() {
        let task = ObsidianTask(line: "  - [ ] Call the bank ⏫ 📅 2026-09-30 🔁 every week")!
        #expect(task.indent == "  " && task.bullet == "-" && !task.isDone)
        #expect(task.title == "Call the bank")
        #expect(task.metadata == "⏫ 📅 2026-09-30 🔁 every week")
        let due = task.due(calendar: utc)!
        #expect(due.date == at(0, day: 30) && !due.hasTime)
        #expect(ObsidianTask(line: "* [x] Done ✅ 2026-09-28")!.doneDate(calendar: utc) == at(0))
        #expect(ObsidianTask(line: "- [ ] Standup ⏰ 2026-09-28 09:30")!.due(calendar: utc)! == (at(9, 30), true))
    }

    @Test func plainListItemsAndProseAreNotTasks() {
        #expect(ObsidianTask(line: "- a bullet") == nil)
        #expect(ObsidianTask(line: "[ ] no bullet") == nil)
        #expect(ObsidianTask(line: "- [ ] ")?.title == "")
    }

    @Test func editsKeepTheOtherMetadata() {
        var task = ObsidianTask(line: "- [ ] Call the bank ⏫ 📅 2026-09-30 🔁 every week")!
        task.title = "Call the bank about fees"
        task.setDone(true, on: at(12), calendar: utc)
        #expect(task.line == "- [x] Call the bank about fees ⏫ 📅 2026-09-30 🔁 every week ✅ 2026-09-28")
        task.setDone(false, on: at(12), calendar: utc)
        task.setDue(at(10, day: 29), hasTime: true, calendar: utc)
        #expect(task.line == "- [ ] Call the bank about fees ⏫ 🔁 every week 📅 2026-09-29 ⏰ 2026-09-29 10:00")
        task.setDue(nil, hasTime: false, calendar: utc)
        #expect(task.line == "- [ ] Call the bank about fees ⏫ 🔁 every week")
    }
}

@MainActor
struct ObsidianSourceTests {
    let vault: URL

    init() throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        try "# Home\n- [ ] Water plants 📅 2026-09-28\n- [x] Old ✅ 2026-01-01\nprose\n".write(
            to: vault.appendingPathComponent("Home.md"), atomically: true, encoding: .utf8)
        try "- [ ] Slides 📅 2026-10-02\n".write(
            to: vault.appendingPathComponent("Projects/Q4.md"), atomically: true, encoding: .utf8)
        try "- [ ] hidden\n".write(to: vault.appendingPathComponent(".obsidian/x.md"), atomically: true, encoding: .utf8)
        try "no tasks here\n".write(to: vault.appendingPathComponent("Notes.md"), atomically: true, encoding: .utf8)
    }

    private func source() -> ObsidianSource { ObsidianSource(vault: vault, inboxPath: "Inbox", calendar: utc) }
    private func read(_ path: String) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func readsTasksFromEveryFileButHiddenFolders() async throws {
        let s = source()
        let items = try await s.reminders(completedSince: at(0))
        #expect(items.map(\.title).sorted() == ["Slides", "Water plants"])  // the old done one is left out
        #expect(s.lists().map(\.title) == ["Inbox", "Home", "Q4"])           // the inbox first, even before it exists
        #expect(items.first { $0.title == "Slides" }?.listID == "Projects/Q4.md")
        #expect(s.currentAccess() == .granted)
    }

    @Test func addsToTheInboxCreatingIt() async throws {
        let s = source()
        _ = try await s.reminders(completedSince: at(0))
        let saved = try await s.save(ReminderItem(title: "Buy milk", listID: "Inbox.md", due: at(0), dueHasTime: false))
        #expect(try read("Inbox.md") == "- [ ] Buy milk 📅 2026-09-28\n")
        _ = try await s.save(ReminderItem(title: "Call Sam", listID: "Inbox.md", due: at(10), dueHasTime: true))
        #expect(try read("Inbox.md") == "- [ ] Buy milk 📅 2026-09-28\n- [ ] Call Sam 📅 2026-09-28 ⏰ 2026-09-28 10:00\n")
        #expect(saved.id == "Inbox.md#0")
        _ = try await s.reminders(completedSince: at(0))
        #expect(s.lists().map(\.title) == ["Inbox", "Home", "Q4"])   // the inbox stays first once it exists
    }

    @Test func ticksRenamesAndDeletesInPlace() async throws {
        let s = source()
        var plants = try #require(try await s.reminders(completedSince: at(0)).first { $0.title == "Water plants" })
        plants.isCompleted = true
        plants.title = "Water the plants"
        _ = try await s.save(plants)
        let today = ObsidianTask.dateString(Date(), calendar: utc)
        #expect(try read("Home.md") == "# Home\n- [x] Water the plants 📅 2026-09-28 ✅ \(today)\n- [x] Old ✅ 2026-01-01\nprose\n")
        try await s.remove(plants)
        #expect(try read("Home.md") == "# Home\n- [x] Old ✅ 2026-01-01\nprose\n")
    }

    @Test func findsATaskThatMovedAndRefusesOneThatChanged() async throws {
        let s = source()
        let items = try await s.reminders(completedSince: at(0))
        var plants = try #require(items.first { $0.title == "Water plants" })
        try "intro\n# Home\n- [ ] Water plants 📅 2026-09-28\n".write(
            to: vault.appendingPathComponent("Home.md"), atomically: true, encoding: .utf8)
        plants.title = "Water plants twice"
        _ = try await s.save(plants)                                   // moved down a line: still found
        #expect(try read("Home.md") == "intro\n# Home\n- [ ] Water plants twice 📅 2026-09-28\n")
        var slides = try #require(items.first { $0.title == "Slides" })
        try "- [ ] Slides edited\n".write(to: vault.appendingPathComponent("Projects/Q4.md"), atomically: true, encoding: .utf8)
        slides.isCompleted = true
        await #expect(throws: ReminderSourceError.self) { try await s.save(slides) }
        #expect(try read("Projects/Q4.md") == "- [ ] Slides edited\n")      // untouched
    }

    @Test func aMissingVaultIsDenied() {
        #expect(ObsidianSource(vault: vault.appendingPathComponent("nope"), inboxPath: "").currentAccess() == .denied)
        #expect(ObsidianSource.normalizedInboxPath(" Tasks/Inbox ") == "Tasks/Inbox.md")
    }
}
