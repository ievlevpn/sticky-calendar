import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct CutCopyPasteTests {
    let source = FakeSource()
    let settings: AppSettings

    init() {
        let name = "CutCopyPasteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = AppSettings(defaults: defaults)
    }

    func makeStore() -> CalendarStore {
        CalendarStore(source: source, settings: settings, calendar: utc, now: { at(10) })
    }

    @Test func pastesCopiesOnTheViewedDayAtTheSameTimesAndSelectsThem() {
        source.stored = [event("a", at(9), at(10)), event("b", at(11), at(12, 30))]
        let store = makeStore()
        store.selectedID = "a"
        store.toggleSelection("b")
        let copied = store.selectedEvents
        #expect(copied.map(\.title) == ["a", "b"])
        store.goToDay(offset: 2)
        let pasted = store.paste(copied)
        #expect(pasted.map(\.start) == [at(9, day: 30), at(11, day: 30)])
        #expect(pasted.map(\.end) == [at(10, day: 30), at(12, 30, day: 30)])
        #expect(store.selectedIDs == Set(pasted.map(\.id)))
        #expect(source.stored.count == 4)
        store.undoManager.undo()                                 // one step removes both
        #expect(source.stored.map(\.title).sorted() == ["a", "b"])
    }

    @Test func cutRemovesAtOnceAndOneUndoBringsThemBack() {
        source.stored = [event("a", at(9), at(10)), event("b", at(11), at(12))]
        let store = makeStore()
        store.selectedID = "a"
        store.toggleSelection("b")
        store.deleteSelectedForCut()
        #expect(source.stored.isEmpty && store.pendingGroupDelete == nil)
        store.undoManager.undo()
        #expect(source.stored.count == 2)
    }

    @Test func cuttingARepeatingEventAsksFirst() {
        let repeating = event("a", at(9), at(10), recurring: true)
        source.stored = [repeating, event("b", at(11), at(12))]
        let store = makeStore()
        store.selectedID = repeating.id
        store.toggleSelection("b")
        store.deleteSelectedForCut()
        #expect(source.stored.count == 2)
        #expect(store.pendingGroupDelete?.count == 2)
    }
}
