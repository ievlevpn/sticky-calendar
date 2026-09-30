import Foundation
import Testing
@testable import StickyCalendarCore

/// A reload already under way when a change is made read the source partly before the
/// change and partly after: an unticked reminder was in neither its open nor its completed
/// tasks, and vanished until the change's own reload (the friend's recording, 2026-09-30).
@MainActor
struct ReloadRaceTests {
    let source = FakeReminderSource()
    let store: ReminderStore

    init() {
        let name = "ReloadRaceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        store = ReminderStore(source: source, settings: ReminderSettings(defaults: defaults), calendar: utc, now: { at(12) })
        source.stored = [ReminderItem(id: "1", title: "Practise piano", listID: "home", due: at(0)),
                         ReminderItem(id: "2", title: "Check the translation", listID: "home", due: at(0))]
    }

    private var shown: [String] {
        store.todaySections.flatMap(\.items).map { "\($0.title)\($0.isCompleted ? " ✓" : "")" }.sorted()
    }

    private func until(_ condition: () -> Bool) async {
        while !condition() { await Task.yield() }
    }

    @Test func aReloadUnderWayDoesNotUndoAnUntick() async {
        await store.reload()
        await store.toggle(store.items[0])  // tick "Practise piano"
        await store.idle()
        // Ticking the other one starts a reload; it reads the open tasks, then pauses.
        source.pauseNextRead = true
        await store.toggle(store.items[1])
        await until { source.pausedRead != nil }
        // Now untick "Practise piano"; its save is slow to answer.
        source.pauseNextSave = true
        let untick = Task { await store.toggle(store.todaySections.flatMap(\.items).first { $0.id == "1" }!) }
        await until { source.pausedSave != nil }
        #expect(shown == ["Check the translation ✓", "Practise piano"])
        source.resumeRead()                 // the old reload finishes: "Practise piano" is in neither part
        await until { source.pausedRead == nil }
        for _ in 0..<20 { await Task.yield() }
        #expect(shown == ["Check the translation ✓", "Practise piano"])
        source.resumeSave()
        await untick.value
        await store.idle()
        #expect(shown == ["Check the translation ✓", "Practise piano"])
    }
}

@MainActor
struct CompletedButtonTests {
    @Test func hidingCompletedHidesJustTickedOnesToo() async {
        let name = "CompletedButtonTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let source = FakeReminderSource()
        source.stored = [ReminderItem(id: "1", title: "Practise piano", listID: "home", due: at(0))]
        let store = ReminderStore(source: source, settings: ReminderSettings(defaults: defaults), calendar: utc, now: { at(12) })
        await store.reload()
        await store.toggle(store.items[0])
        await store.idle()
        #expect(store.showsCompletedItems)
        store.setShowsCompleted(false)
        #expect(store.todaySections.isEmpty && !store.showsCompletedItems)
        store.setShowsCompleted(true)
        #expect(store.todaySections.flatMap(\.items).map(\.isCompleted) == [true] && store.showsCompletedItems)
    }
}
