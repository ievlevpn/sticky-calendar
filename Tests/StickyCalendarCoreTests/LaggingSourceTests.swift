import Foundation
import Testing
@testable import StickyCalendarCore

/// Todoist can answer a read made right after a change with what was there before it. For a
/// little while, the app's own changes win over such reads, then the server's word counts.
@MainActor
struct LaggingSourceTests {
    final class Clock { var now = at(12) }

    let source = FakeReminderSource()
    let clock = Clock()
    let store: ReminderStore

    init() {
        let name = "LaggingSourceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let clock = clock
        store = ReminderStore(source: source, settings: ReminderSettings(defaults: defaults), calendar: utc,
                              now: { clock.now }, recheckDelay: .milliseconds(1))
        source.stored = [ReminderItem(id: "1", title: "Practise piano", listID: "home", due: at(0))]
    }

    private var shown: [ReminderItem] { store.todaySections.flatMap(\.items) }

    @Test func anUntickSurvivesALaggingRead() async {
        await store.reload()
        await store.toggle(store.items[0])  // ticked
        await store.idle()
        source.staleReads = 1
        await store.toggle(shown[0])        // unticked; the next read still has it ticked
        await store.reload()
        #expect(shown.map(\.isCompleted) == [false])
        await store.idle()
        #expect(shown.map(\.isCompleted) == [false] && !source.stored[0].isCompleted)
    }

    @Test func anUntickSurvivesAReadWhereItIsMissing() async {
        source.stored[0].isCompleted = true
        source.stored[0].completionDate = at(9)
        source.stored.append(ReminderItem(id: "2", title: "Other", listID: "home", due: at(0)))
        await store.reload()
        // Todoist's reopen leaves the completed list before the task is back in the open one.
        let reopened = ReminderItem(id: "1", title: "Practise piano", listID: "home", due: at(0))
        await store.toggle(ReminderItem(id: "1", title: "Practise piano", listID: "home", due: at(0),
                                        isCompleted: true, completionDate: at(9)))
        source.stored.removeAll { $0.id == "1" }
        await store.reload()
        #expect(shown.map(\.title).sorted() == ["Other", "Practise piano"])
        source.stored.append(reopened)
        await store.idle()
        #expect(shown.map(\.title).sorted() == ["Other", "Practise piano"])
    }

    @Test func aTickSurvivesALaggingRead() async {
        await store.reload()
        source.staleReads = 1
        await store.toggle(store.items[0])
        await store.reload()
        #expect(shown.map(\.isCompleted) == [true])
    }

    @Test func aDeleteSurvivesALaggingRead() async {
        await store.reload()
        source.staleReads = 1
        await store.delete(store.items[0])
        await store.reload()
        #expect(shown.isEmpty)
    }

    @Test func afterAWhileTheServerCounts() async {
        await store.reload()
        await store.toggle(store.items[0])
        await store.idle()
        source.stored[0].isCompleted = false   // reopened elsewhere
        source.stored[0].completionDate = nil
        clock.now = at(12).addingTimeInterval(11)
        await store.reload()
        #expect(shown.map(\.isCompleted) == [false])
    }

    @Test func hidingCompletedHidesJustTickedOnesToo() async {
        await store.reload()
        await store.toggle(store.items[0])
        await store.idle()
        #expect(store.showsCompletedItems)
        store.setShowsCompleted(false)
        #expect(shown.isEmpty && !store.showsCompletedItems)
        store.setShowsCompleted(true)
        #expect(shown.map(\.isCompleted) == [true] && store.showsCompletedItems)
    }
}
