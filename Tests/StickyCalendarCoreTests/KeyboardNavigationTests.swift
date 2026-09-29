import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct KeyboardNavigationTests {
    let source = FakeSource()
    let settings: AppSettings

    init() {
        let name = "KeyboardNavigationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = AppSettings(defaults: defaults)
    }

    func makeStore() -> CalendarStore {
        CalendarStore(source: source, settings: settings, calendar: utc, now: { at(10) })
    }

    @Test func readingOrderIsStartTimeThenColumn() {
        // b (9-11) and a (9-10) start together; the longer one takes column 0.
        source.stored = [event("c", at(12), at(13)), event("a", at(9), at(10)), event("b", at(9), at(11))]
        let store = makeStore()
        #expect(store.navigationOrder.map(\.id) == ["b", "a", "c"])
    }

    @Test func withNothingSelectedArrowsAreNotHandled() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        #expect(!store.selectAdjacent(1))
        #expect(store.selectedID == nil)
    }

    @Test func movesSelectionAndStopsAtTheEnds() {
        source.stored = [event("a", at(9), at(10)), event("b", at(11), at(12)), event("c", at(13), at(14))]
        let store = makeStore()
        store.selectedID = "a"
        #expect(store.selectAdjacent(1))
        #expect(store.selectedID == "b")
        #expect(store.selectAdjacent(1))
        #expect(store.selectAdjacent(1))
        #expect(store.selectedID == "c")
        #expect(store.selectAdjacent(-1))
        #expect(store.selectedID == "b")
        store.selectedID = "a"
        #expect(store.selectAdjacent(-1)) // handled, stays on the first block
        #expect(store.selectedID == "a")
    }

    @Test func keyboardSelectionAsksToRevealTheBlock() {
        source.stored = [event("a", at(9), at(10)), event("b", at(11), at(12))]
        let store = makeStore()
        store.selectedID = "a"
        let before = store.revealRequest?.id
        store.selectAdjacent(1)
        #expect(store.revealRequest?.eventID == "b")
        #expect(store.revealRequest?.id != before)
    }

    @Test func scrollStepsAreIssuedAsNewRequests() {
        let store = makeStore()
        store.scrollStep(.hour(1))
        let first = store.scrollStepRequest
        store.scrollStep(.hour(1))
        #expect(store.scrollStepRequest?.step == .hour(1))
        #expect(store.scrollStepRequest?.id != first?.id)
        store.scrollStep(.page(-1))
        #expect(store.scrollStepRequest?.step == .page(-1))
    }

    @Test func returnOpensTheEditorForTheSelectedBlockOnly() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        store.requestEditSelected()
        #expect(store.editRequest == nil)
        store.selectedID = "a"
        store.requestEditSelected()
        #expect(store.editRequest?.eventID == "a")
    }

    @Test func escapeClearsASelectionOnly() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        #expect(!store.clearSelection()) // nothing selected: not handled, Esc passes through
        store.selectedID = "a"
        #expect(store.clearSelection())
        #expect(store.selectedID == nil)
    }

    @Test func readOnlyBlocksCanBeSelectedAndOpened() {
        source.stored = [event("h", at(9), at(10), calendar: "holidays", readOnly: true)]
        let store = makeStore()
        store.selectedID = "h"
        store.requestEditSelected()
        #expect(store.editRequest?.eventID == "h") // the popover shows it read-only
    }
}

struct RevealAndStepTests {
    let g = TimelineGeometry(dayStart: at(0), pointsPerHour: 50, calendar: utc)

    @Test func revealDoesNothingWhenAlreadyVisible() {
        // Viewport shows y 400...900; block 500...550.
        #expect(g.revealOffset(top: 500, bottom: 550, scrollOffset: 400, viewportHeight: 500) == nil)
    }

    @Test func revealScrollsJustEnoughWithAMargin() {
        // Block below: bottom 1000 -> offset so bottom sits 8 pt above the viewport's end.
        #expect(g.revealOffset(top: 950, bottom: 1000, scrollOffset: 400, viewportHeight: 500) == 508)
        // Block above: top 300 -> offset so top sits 8 pt below the viewport's start.
        #expect(g.revealOffset(top: 300, bottom: 350, scrollOffset: 400, viewportHeight: 500) == 292)
    }

    @Test func revealOfATallBlockShowsItsTop() {
        // 550-pt block (11:00-22:00 at 50 pt/h) in a 500-pt viewport: align its top.
        #expect(g.revealOffset(top: 600, bottom: 1150, scrollOffset: 0, viewportHeight: 500) == 592)
    }

    @Test func stepOffsetsAreClampedToTheDay() {
        // Content 1200 tall, viewport 500 -> offsets 0...700.
        #expect(g.offset(after: .hour(1), from: 100, viewportHeight: 500) == 150)
        #expect(g.offset(after: .hour(-1), from: 20, viewportHeight: 500) == 0)
        #expect(g.offset(after: .page(1), from: 100, viewportHeight: 500) == 550) // a page keeps an hour of overlap
        #expect(g.offset(after: .page(1), from: 600, viewportHeight: 500) == 700)
    }
}
