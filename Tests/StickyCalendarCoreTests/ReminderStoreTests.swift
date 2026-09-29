import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct ReminderStoreTests {
    let source = FakeReminderSource()
    let settings: ReminderSettings
    let store: ReminderStore

    init() {
        let name = "ReminderStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = ReminderSettings(defaults: defaults)
        store = ReminderStore(source: source, settings: settings, calendar: utc, now: { at(12) })
    }

    private func reminder(_ id: String, _ title: String, list: String = "home", due: Date? = nil,
                          timed: Bool = false, done: Bool = false) -> ReminderItem {
        ReminderItem(id: id, title: title, listID: list, due: due, dueHasTime: timed,
                     isCompleted: done, completionDate: done ? at(9) : nil)
    }

    private func titles(_ section: ReminderSection?) -> [String] { section?.items.map(\.title) ?? [] }

    @Test func todayShowsOverdueThenTodaysInOrder() async {
        source.stored = [
            reminder("1", "Renew passport", due: at(0, day: 26)),
            reminder("2", "Buy milk", due: at(0)),
            reminder("3", "Call the bank", due: at(10), timed: true),
            reminder("4", "Standup notes", due: at(9), timed: true),
            reminder("5", "Someday", due: nil),
            reminder("6", "Next week", due: at(0, day: 30)),
            reminder("7", "Send invoice", due: at(8), timed: true, done: true),
        ]
        await store.reload()
        let sections = store.todaySections
        #expect(sections.map(\.kind) == [.overdue, .today])
        #expect(titles(sections[0]) == ["Renew passport"])
        #expect(titles(sections[1]) == ["Standup notes", "Call the bank", "Buy milk"]) // done ones hidden by default
        settings.setShowsCompleted(true)
        #expect(titles(store.todaySections.last) == ["Standup notes", "Call the bank", "Buy milk", "Send invoice"])
    }

    @Test func listsGroupByListInOrderAndLeaveOutEmptyOnes() async {
        source.stored = [
            reminder("1", "Laptop charger", list: "work"),
            reminder("2", "Water plants", list: "home", due: at(0, day: 29)),
            reminder("3", "Buy milk", list: "home"),
        ]
        settings.setMode(.lists)
        await store.reload()
        #expect(store.sections.map(\.title) == ["Home", "Work"])
        #expect(titles(store.sections[0]) == ["Water plants", "Buy milk"])     // dated first
    }

    @Test func hiddenListsAreLeftOut() async {
        source.stored = [reminder("1", "Work thing", list: "work", due: at(0)), reminder("2", "Home thing", due: at(0))]
        settings.setList("work", visible: false)
        await store.reload()
        #expect(titles(store.todaySections.first) == ["Home thing"])
    }

    @Test func tickingKeepsItInViewAndUndoUnticks() async {
        source.stored = [reminder("1", "Buy milk", due: at(0))]
        await store.reload()
        await store.toggle(store.items[0])
        await store.reload()
        #expect(source.stored[0].isCompleted)
        #expect(store.todaySections.first?.items.first?.isCompleted == true) // struck, still shown
        store.undoManager.undo()
        await store.idle()
        await store.reload()
        #expect(!source.stored[0].isCompleted)
    }

    @Test func renameAndUndo() async {
        source.stored = [reminder("1", "Buy mlik", due: at(0))]
        await store.reload()
        await store.rename(store.items[0], to: "  Buy milk ")
        #expect(source.stored[0].title == "Buy milk")
        store.undoManager.undo()
        await store.idle()
        #expect(source.stored[0].title == "Buy mlik")
        await store.rename(store.items[0], to: "   ")                                // blank: ignored
        #expect(source.stored[0].title == "Buy mlik")
    }

    @Test func aFailedSaveShowsTheOriginalAndAnError() async {
        source.stored = [reminder("1", "Buy milk", due: at(0))]
        await store.reload()
        source.failNextSave = true
        await store.toggle(store.items[0])
        #expect(store.items[0].isCompleted == false)
        #expect(store.lastError != nil)
    }

    @Test func switchingSourcesStartsOver() async {
        source.stored = [reminder("1", "Buy milk", due: at(0))]
        await store.reload()
        let other = FakeReminderSource()
        other.stored = [reminder("9", "Other", due: at(0))]
        store.use(other)
        await store.idle()
        #expect(store.items.map(\.title) == ["Other"])
        store.use(nil)
        #expect(!store.hasSource && store.items.isEmpty)
    }

    @Test func addingInTodayModeIsDueTodayAndGoesToTheDefaultList() async {
        await store.reload()
        let added = await store.add("Buy milk")
        #expect(added?.due == at(0) && added?.dueHasTime == false && added?.listID == "home")
        settings.setMode(.lists)
        let someday = await store.add("Someday", listID: "work")
        #expect(someday?.due == nil)
        let blank = await store.add("   ")
        #expect(blank == nil)
    }

    @Test func newRemindersSkipHiddenOrReadOnlyDefaultLists() async {
        source.defaultID = "shared"                                          // read-only
        await store.reload()
        #expect(store.defaultWritableListID() == "home")
        settings.setList("home", visible: false)
        #expect(store.defaultWritableListID() == "work")
    }

    @Test func deleteAndUndoRestoresIt() async {
        source.stored = [reminder("1", "Buy milk", due: at(0))]
        await store.reload()
        await store.delete(store.items[0])
        #expect(source.stored.isEmpty)
        store.undoManager.undo()
        await store.idle()
        #expect(source.stored.map(\.title) == ["Buy milk"])
    }

    @Test func searchLooksEverywhereAndPrefersTitles() async {
        source.stored = [
            reminder("1", "Call the bank", list: "work", due: at(0, day: 30)),   // not due today
            reminder("2", "Groceries", due: at(0)),
            reminder("3", "Water plants", due: nil),
        ]
        source.stored[1].notes = "oat milk, bananas, coffee beans"
        await store.reload()
        #expect(store.search("clbnk").map(\.title) == ["Call the bank"])   // outside Today too
        #expect(store.search("bananas").map(\.title) == ["Groceries"])       // in the notes
        #expect(store.search("zzz").isEmpty)
    }

    @Test func editChangesEverythingAtOnceAndUndoes() async {
        source.stored = [reminder("1", "Call bank", due: at(0))]
        await store.reload()
        await store.edit(store.items[0], title: "Call the bank", due: at(10, day: 29), dueHasTime: true,
                         priority: .high, notes: "  ask about fees  ")
        let saved = source.stored[0]
        #expect(saved.title == "Call the bank" && saved.due == at(10, day: 29) && saved.dueHasTime)
        #expect(saved.priority == .high && saved.notes == "ask about fees")
        store.undoManager.undo()
        await store.idle()
        #expect(source.stored[0].title == "Call bank" && source.stored[0].priority == .none && source.stored[0].notes == nil)
    }

    @Test func editLeavesNotesAloneWhereTheyCantBeWritten() async {
        source.stored = [reminder("1", "Task", due: at(0))]
        source.stored[0].notes = "from the vault"
        source.canEditNotes = false
        await store.reload()
        await store.edit(store.items[0], title: "Task", due: nil, dueHasTime: false, priority: .low, notes: "changed")
        #expect(source.stored[0].notes == "from the vault" && source.stored[0].priority == .low && source.stored[0].due == nil)
    }

    @Test func moreImportantFirstOnTheSameDay() async {
        source.stored = [reminder("1", "A", due: at(0)), reminder("2", "B", due: at(0))]
        source.stored[1].priority = .high
        await store.reload()
        #expect(store.todaySections.first?.items.map(\.title) == ["B", "A"])
    }

    @Test func settingsPersist() {
        let name = "ReminderSettings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let s = ReminderSettings(defaults: defaults)
        #expect(s.placement == .tab && !s.isPlacementChosen && s.mode == .today && s.hotKey == .controlOptionR && s.isPinned && !s.isVisible)
        s.setPlacement(.tab); s.setMode(.lists); s.setShowsCompleted(true); s.setList("x", visible: false)
        s.setPinned(false); s.setVisible(true); s.setHotKey(.off)
        let r = ReminderSettings(defaults: defaults)
        #expect(r.placement == .tab && r.isPlacementChosen && r.mode == .lists && r.showsCompleted && r.hiddenListIDs == ["x"])
        #expect(!r.isPinned && r.isVisible && r.hotKey == .off)
        #expect(r.provider == nil && r.obsidianInboxPath == "Inbox.md")
        r.setProvider(.obsidian)
        r.setObsidian(vault: "/v", inbox: "Tasks/Inbox")
        let o = ReminderSettings(defaults: defaults)
        #expect(o.provider == .obsidian && o.obsidianVaultPath == "/v" && o.obsidianInboxPath == "Tasks/Inbox.md")
        o.setProvider(nil)
        #expect(ReminderSettings(defaults: defaults).provider == nil)
    }
}

struct FuzzyMatchTests {
    @Test func findsLettersInOrder() {
        #expect(FuzzyMatch.score("clbnk", in: "Call the bank") != nil)
        #expect(FuzzyMatch.score("bank call", in: "Call the bank") == nil)   // out of order
        #expect(FuzzyMatch.score("xyz", in: "Call the bank") == nil)
        #expect(FuzzyMatch.score("   ", in: "anything") == nil)
    }

    @Test func runsAndWordStartsRankHigher() {
        let exact = FuzzyMatch.score("bank", in: "Call the bank")!
        let scattered = FuzzyMatch.score("bank", in: "Bring a nice kettle")!
        #expect(exact > scattered)
        #expect(FuzzyMatch.score("milk", in: "Buy milk")! > FuzzyMatch.score("milk", in: "Buy milk and eggs for the week")!)
    }
}

@MainActor
struct RefreshTests {
    @Test func calendarRefreshAsksTheSourceToSyncAndReloads() {
        let defaults = UserDefaults(suiteName: "RefreshTests-\(UUID().uuidString)")!
        let source = FakeSource()
        let store = CalendarStore(source: source, settings: AppSettings(defaults: defaults), calendar: utc, now: { at(12) })
        source.stored = [event("a", at(9), at(10))]
        #expect(store.timedEvents.isEmpty)
        store.refresh()
        #expect(source.refreshCount == 1)
        #expect(store.timedEvents.map(\.eventIdentifier) == ["a"])
    }
}

struct ReminderInputTests {
    private let calendar = Calendar.current

    @Test func takesTheDateOutOfTheTitle() {
        let input = ReminderInput.parse("Call the bank tomorrow at 10am")
        #expect(input.title == "Call the bank")
        #expect(input.dueHasTime)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        #expect(calendar.isDate(input.due!, inSameDayAs: tomorrow))
        #expect(calendar.component(.hour, from: input.due!) == 10)
    }

    @Test func aDayWithoutATimeIsAllDay() {
        let input = ReminderInput.parse("Pay rent tomorrow")
        #expect(input.title == "Pay rent")
        #expect(input.due != nil && !input.dueHasTime)
    }

    @Test func plainTitlesAndNumbersStayAsTheyAre() {
        #expect(ReminderInput.parse("Buy milk") == ReminderInput(title: "Buy milk", due: nil, dueHasTime: false))
        #expect(ReminderInput.parse(" Buy 2 apples ").title == "Buy 2 apples")
        #expect(ReminderInput.parse("Buy 2 apples").due == nil)
    }
}
