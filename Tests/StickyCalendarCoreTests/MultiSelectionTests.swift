import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct MultiSelectionTests {
    let source = FakeSource()
    let settings: AppSettings

    init() {
        let name = "MultiSelectionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = AppSettings(defaults: defaults)
    }

    func makeStore() -> CalendarStore {
        CalendarStore(source: source, settings: settings, calendar: utc, now: { at(10) })
    }

    func moved(_ item: EventItem, by delta: TimeInterval) -> EventChange {
        var updated = item
        updated.start += delta
        updated.end += delta
        return EventChange(original: item, updated: updated)
    }

    @Test func toggleAddsAndRemovesAndKeepsAPrimary() {
        source.stored = [event("a", at(9), at(10)), event("b", at(11), at(12)), event("c", at(13), at(14))]
        let store = makeStore()
        store.selectedID = "a"
        store.toggleSelection("c")
        #expect(store.selectedIDs == ["a", "c"])
        #expect(store.selectedID == "c")
        store.toggleSelection("c")
        #expect(store.selectedIDs == ["a"])
        #expect(store.selectedID == "a")
        store.toggleSelection("a")
        #expect(store.selectedIDs.isEmpty && store.selectedID == nil)
    }

    @Test func plainSelectionAndEscReplaceTheWholeSelection() {
        source.stored = [event("a", at(9), at(10)), event("b", at(11), at(12))]
        let store = makeStore()
        store.selectedID = "a"
        store.toggleSelection("b")
        store.selectedID = "a"
        #expect(store.selectedIDs == ["a"])
        store.toggleSelection("b")
        #expect(store.clearSelection())
        #expect(store.selectedIDs.isEmpty)
    }

    @Test func reloadDropsVanishedEventsFromTheSelection() {
        source.stored = [event("a", at(9), at(10)), event("b", at(11), at(12))]
        let store = makeStore()
        store.selectedID = "a"
        store.toggleSelection("b")
        source.stored.removeAll { $0.id == "b" }
        store.reload()
        #expect(store.selectedIDs == ["a"])
        #expect(store.selectedID == "a")
    }

    @Test func movesSeveralEventsAsOneUndoStep() {
        source.stored = [event("a", at(9), at(10)), event("b", at(11), at(12))]
        let store = makeStore()
        store.requestUpdates(store.timedEvents.map { moved($0, by: 1800) })
        #expect(store.timedEvents.map(\.start) == [at(9, 30), at(11, 30)])
        #expect(store.undoManager.undoActionName == "Move Events")

        store.undoManager.undo()
        #expect(store.timedEvents.map(\.start) == [at(9), at(11)])
        store.undoManager.redo()
        #expect(store.timedEvents.map(\.start) == [at(9, 30), at(11, 30)])
    }

    @Test func aRecurringEventInTheGroupAsksOnceForAll() {
        source.stored = [event("a", at(9), at(10)), event("r", at(11), at(12), recurring: true)]
        let store = makeStore()
        store.requestUpdates(store.timedEvents.map { moved($0, by: 3600) })
        #expect(store.pendingEdit?.original.title == "r")
        #expect(store.pendingEdit?.updated(id: "a")?.start == at(10))
        #expect(source.spans.isEmpty)

        store.confirmEdit(store.pendingEdit!, span: .futureEvents)
        #expect(store.timedEvents.map(\.start) == [at(10), at(12)])
        #expect(Set(source.spans) == [.thisEvent, .futureEvents])
    }

    @Test func deletesTheSelectionAfterAskingAndUndoRestoresIt() {
        source.stored = [event("a", at(9), at(10)), event("b", at(11), at(12)), event("c", at(13), at(14))]
        let store = makeStore()
        store.selectedID = "a"
        store.toggleSelection("c")
        store.requestDeleteSelected()
        #expect(store.pendingDelete == nil)
        #expect(store.pendingGroupDelete?.map(\.title) == ["a", "c"])

        store.confirmGroupDelete(store.pendingGroupDelete!, span: .thisEvent)
        #expect(store.pendingGroupDelete == nil)
        #expect(store.timedEvents.map(\.title) == ["b"])
        #expect(store.selectedIDs.isEmpty)
        #expect(store.undoManager.undoActionName == "Delete Events")

        store.undoManager.undo()
        #expect(store.timedEvents.map(\.title) == ["a", "b", "c"])
    }

    @Test func groupDeleteSkipsReadOnlyAndAppliesTheSpanToRepeats() {
        source.stored = [
            event("a", at(9), at(10)),
            event("r", at(11), at(12), recurring: true),
            event("ro", at(13), at(14), calendar: "holidays", readOnly: true),
        ]
        let store = makeStore()
        for id in store.timedEvents.map(\.id) { store.toggleSelection(id) }
        store.requestDeleteSelected()
        #expect(store.pendingGroupDelete?.map(\.title) == ["a", "r"])

        store.confirmGroupDelete(store.pendingGroupDelete!, span: .futureEvents)
        #expect(store.timedEvents.map(\.title) == ["ro"])
        #expect(Set(source.spans) == [.thisEvent, .futureEvents])
    }

    @Test func aSingleWritableBlockInTheSelectionUsesTheOrdinaryDelete() {
        source.stored = [event("a", at(9), at(10)), event("ro", at(13), at(14), calendar: "holidays", readOnly: true)]
        let store = makeStore()
        for id in store.timedEvents.map(\.id) { store.toggleSelection(id) }
        store.requestDeleteSelected()
        #expect(store.pendingGroupDelete == nil)
        #expect(store.pendingDelete?.title == "a")
    }
}
