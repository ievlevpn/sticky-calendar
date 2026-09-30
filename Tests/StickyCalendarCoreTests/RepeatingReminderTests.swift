import Foundation
import Testing
@testable import StickyCalendarCore

/// Ticking a repeating reminder: the source moves it to its next date and leaves it open
/// (as Todoist, TickTick and Reminders do). It should stay in view ticked, like any other,
/// and unticking or ⌘Z should put its date back rather than tick it again.
@MainActor
struct RepeatingReminderTests {
    let source = FakeReminderSource()
    let store: ReminderStore

    init() {
        let name = "RepeatingReminderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        store = ReminderStore(source: source, settings: ReminderSettings(defaults: defaults), calendar: utc, now: { at(12) })
        source.stored = [ReminderItem(id: "1", title: "Water plants", listID: "home", due: at(9), dueHasTime: true,
                                      isRepeating: true)]
        source.repeatingIDs = ["1"]
    }

    private func tick() async {
        await store.reload()
        await store.toggle(store.items[0])
        await store.idle()
    }

    @Test func aTickedRepeatStaysInViewWithItsNextDate() async {
        await tick()
        #expect(source.stored[0].due == at(9, day: 29) && !source.stored[0].isCompleted)
        let shown = store.todaySections.flatMap(\.items)
        #expect(shown.count == 1)
        #expect(shown[0].isCompleted && shown[0].due == at(9) && shown[0].nextDue == at(9, day: 29))
        #expect(store.openItems.isEmpty)
    }

    @Test func untickingPutsItsDateBack() async {
        await tick()
        await store.toggle(store.todaySections[0].items[0])
        await store.idle()
        #expect(source.stored[0].due == at(9) && !source.stored[0].isCompleted)
        #expect(store.openItems.map(\.title) == ["Water plants"])
    }

    @Test func undoPutsItsDateBackInsteadOfTickingAgain() async {
        await tick()
        store.undoManager.undo()
        await store.idle()
        #expect(source.stored[0].due == at(9) && !source.stored[0].isCompleted)
        #expect(store.openItems.map(\.title) == ["Water plants"])
    }

    @Test func editingATickedRepeatChangesTheRealOneWithoutTickingIt() async {
        await tick()
        let shown = store.todaySections[0].items[0]
        await store.edit(shown, title: "Water the plants", due: shown.due, dueHasTime: true, priority: .high, notes: nil)
        await store.idle()
        #expect(source.stored[0].title == "Water the plants" && source.stored[0].priority == .high)
        #expect(source.stored[0].due == at(9, day: 29) && !source.stored[0].isCompleted)
    }

    @Test func stillDueAfterTheTickItShowsOpen() async {
        source.stored[0].due = at(9, day: 26) // next: the 27th, still overdue
        await tick()
        #expect(store.openItems.map(\.due) == [at(9, day: 27)])
    }

    @Test func aNewDayShowsItsNextDate() async {
        await tick()
        store.handleDayChange()
        await store.idle()
        #expect(store.listSections.flatMap(\.items).map(\.due) == [at(9, day: 29)])
        #expect(store.listSections.flatMap(\.items).allSatisfy { !$0.isCompleted })
    }
}

