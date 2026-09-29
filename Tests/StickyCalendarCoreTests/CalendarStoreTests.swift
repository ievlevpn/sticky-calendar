import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct CalendarStoreTests {
    let source = FakeSource()
    let settings: AppSettings

    init() {
        let name = "CalendarStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = AppSettings(defaults: defaults)
    }

    func makeStore(now: @escaping () -> Date = { at(10) }) -> CalendarStore {
        CalendarStore(source: source, settings: settings, calendar: utc, now: now)
    }

    // MARK: Loading

    @Test func loadsTodaySplittingAllDayAndHidingCalendars() {
        source.stored = [
            event("b", at(11), at(12)),
            event("a", at(9), at(10)),
            event("hol", at(0), at(0, day: 29), calendar: "holidays", allDay: true),
            event("home", at(13), at(14), calendar: "home"),
            event("tomorrow", at(9, day: 29), at(10, day: 29)),
        ]
        settings.setCalendar("home", visible: false)
        let store = makeStore()
        #expect(store.day == at(0))
        #expect(store.timedEvents.map(\.id) == ["a", "b"])
        #expect(store.allDayEvents.map(\.id) == ["hol"])
        #expect(store.visibleCalendars.map(\.id) == ["work", "holidays"])
    }

    @Test func goesToAPickedDate() {
        let store = makeStore()
        store.goTo(at(15, day: 30))
        #expect(store.day == at(0, day: 30) && !store.isViewingToday)
        store.goTo(at(9))
        #expect(store.isViewingToday)
    }

    @Test func externalChangesTriggerReload() {
        let store = makeStore()
        source.stored = [event("new", at(9), at(10))]
        source.onChange?()
        #expect(store.timedEvents.map(\.id) == ["new"])
    }

    @Test func deniedAccessShowsNothingAndRecoversWhenGranted() {
        source.access = .denied
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        #expect(store.access == .denied)
        #expect(store.timedEvents.isEmpty)
        source.access = .granted
        store.reload()
        #expect(store.access == .granted)
        #expect(store.timedEvents.map(\.id) == ["a"])
    }

    @Test func requestsAccessOnlyWhenUndetermined() async {
        source.access = .notDetermined
        let store = makeStore()
        await store.requestAccessIfNeeded()
        #expect(store.access == .granted)
    }

    // MARK: Navigation

    @Test func navigatesDaysAndBack() {
        source.stored = [event("tomorrow", at(9, day: 29), at(10, day: 29))]
        let store = makeStore()
        store.goToDay(offset: 1)
        #expect(store.day == at(0, day: 29))
        #expect(!store.isViewingToday)
        #expect(store.timedEvents.map(\.id) == ["tomorrow"])
        store.goToToday()
        #expect(store.day == at(0))
        #expect(store.isViewingToday)
    }

    @Test func midnightRolloverFollowsTodayOnlyWhenViewingToday() {
        var now = at(23, 59)
        let store = makeStore(now: { now })
        now = at(0, 1, day: 29)
        store.handleClockChange()
        #expect(store.day == at(0, day: 29))

        store.goToDay(offset: 3) // viewing Oct 2
        now = at(0, 1, day: 30)
        store.handleClockChange()
        #expect(store.day == at(0, day: 32)) // still Oct 2 ("Sep 32" normalizes to Oct 2)
    }

    // MARK: Scrolling

    @Test func todayOpensScrolledToNow() {
        let store = makeStore()
        #expect(store.scrollRequest.target == .now)
    }

    @Test func otherDaysOpenAtFirstTimedEventOrMorning() {
        source.stored = [
            event("allday", at(0, day: 29), at(0, day: 30), allDay: true),
            event("late", at(15, day: 29), at(16, day: 29)),
            event("first", at(7, day: 29), at(8, day: 29)),
        ]
        let store = makeStore()
        store.goToDay(offset: 1)
        #expect(store.scrollRequest.target == .event("first"))
        store.goToDay(offset: 1)
        #expect(store.scrollRequest.target == .hour(8))
    }

    @Test func jumpToNowReturnsToTodayAndRequestsANewScroll() {
        let store = makeStore()
        let before = store.scrollRequest.id
        store.jumpToNow() // already on today: must still re-scroll
        #expect(store.scrollRequest.id != before)
        #expect(store.scrollRequest.target == .now)

        store.goToDay(offset: 2)
        store.jumpToNow()
        #expect(store.isViewingToday)
        #expect(store.scrollRequest.target == .now)
    }

    @Test func jumpToNowIsOfferedOnlyWhenNowIsOutOfSight() {
        let store = makeStore()
        store.isNowOnScreen = true
        #expect(!store.offersJumpToNow)
        store.isNowOnScreen = false
        #expect(store.offersJumpToNow)
        store.isNowOnScreen = true
        store.goToDay(offset: 1)
        #expect(store.offersJumpToNow)
    }

    // MARK: Drafts and creation

    @Test func draftUsesDefaultCalendarOrFirstVisibleWritable() {
        let store = makeStore()
        #expect(store.makeDraft(start: at(9), end: at(10))?.calendarID == "work")
        settings.setCalendar("work", visible: false)
        #expect(store.makeDraft(start: at(9), end: at(10))?.calendarID == "home")
        settings.setCalendar("home", visible: false)
        #expect(store.makeDraft(start: at(9), end: at(10)) == nil) // only read-only "holidays" left
    }

    @Test func createSavesSelectsAndUndoRedoWork() {
        let store = makeStore()
        var draft = store.makeDraft(start: at(9), end: at(10))!
        draft.title = "Focus"
        let saved = store.create(draft)
        #expect(saved != nil)
        #expect(store.timedEvents.map(\.title) == ["Focus"])
        #expect(store.selectedID == saved?.id)

        store.undoManager.undo()
        #expect(store.timedEvents.isEmpty)
        store.undoManager.redo()
        #expect(store.timedEvents.map(\.title) == ["Focus"])
    }

    @Test func blankTitleDraftIsDiscarded() {
        let store = makeStore()
        var draft = store.makeDraft(start: at(9), end: at(10))!
        draft.title = "   "
        #expect(store.create(draft) == nil)
        #expect(source.stored.isEmpty)
        #expect(!store.undoManager.canUndo)
    }

    // MARK: Updating

    @Test func updateNonRecurringSavesImmediatelyAndUndoes() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        let original = store.timedEvents[0]
        store.requestUpdate(from: original, to: EventDrag.apply(.move, to: original, delta: 3600))
        #expect(store.timedEvents[0].start == at(10))
        #expect(store.pendingEdit == nil)

        store.undoManager.undo()
        #expect(store.timedEvents[0].start == at(9))
        store.undoManager.redo()
        #expect(store.timedEvents[0].start == at(10))
    }

    @Test func recurringUpdateWaitsForSpanChoice() {
        source.stored = [event("r", at(9), at(10), recurring: true)]
        let store = makeStore()
        let original = store.timedEvents[0]
        var renamed = original
        renamed.title = "Renamed"
        store.requestUpdate(from: original, to: renamed)
        #expect(store.pendingEdit?.updated.title == "Renamed")
        #expect(source.stored[0].title == "r")

        store.confirmEdit(store.pendingEdit!, span: .futureEvents)
        #expect(store.pendingEdit == nil)
        #expect(source.stored[0].title == "Renamed")
        #expect(source.spans == [.futureEvents])
    }

    @Test func readOnlyAndUnchangedEditsAreIgnored() {
        source.stored = [event("ro", at(9), at(10), calendar: "holidays", readOnly: true)]
        let store = makeStore()
        let original = store.timedEvents[0]
        store.requestUpdate(from: original, to: EventDrag.apply(.move, to: original, delta: 3600))
        store.requestUpdate(from: original, to: original)
        store.requestDelete(original)
        #expect(source.spans.isEmpty)
        #expect(store.pendingDelete == nil)
    }

    @Test func failedSaveReportsErrorAndKeepsOriginal() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        let original = store.timedEvents[0]
        source.failNextWrite = true
        store.requestUpdate(from: original, to: EventDrag.apply(.move, to: original, delta: 3600))
        #expect(store.lastError == "Calendar is read-only")
        #expect(store.timedEvents[0].start == at(9))
        #expect(!store.undoManager.canUndo)
    }

    @Test func editingAnEventDeletedElsewhereReportsNotFound() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        let original = store.timedEvents[0]
        source.stored = []
        store.requestUpdate(from: original, to: EventDrag.apply(.move, to: original, delta: 3600))
        #expect(store.lastError == "The event no longer exists.")
        #expect(store.timedEvents.isEmpty)
    }

    // MARK: Deleting

    @Test func deleteSelectedAsksThenDeletesAndUndoRestores() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        store.selectedID = "a"
        store.requestDeleteSelected()
        #expect(store.pendingDelete?.id == "a")
        #expect(source.stored.count == 1)

        store.confirmDelete(store.pendingDelete!, span: .thisEvent)
        #expect(store.timedEvents.isEmpty)
        #expect(store.selectedID == nil)

        store.undoManager.undo()
        #expect(store.timedEvents.map(\.title) == ["a"])
        #expect(store.timedEvents[0].start == at(9))
    }

    @Test func recurringDeleteUsesChosenSpanAndIsNotUndoable() {
        source.stored = [event("r", at(9), at(10), recurring: true)]
        let store = makeStore()
        store.requestDelete(store.timedEvents[0])
        store.confirmDelete(store.pendingDelete!, span: .futureEvents)
        #expect(source.spans == [.futureEvents])
        #expect(!store.undoManager.canUndo)
    }

    @Test func cancelClearsPendingStateWithoutWriting() {
        source.stored = [event("a", at(9), at(10), recurring: true)]
        let store = makeStore()
        store.requestDelete(store.timedEvents[0])
        store.cancelPendingDelete()
        var renamed = store.timedEvents[0]
        renamed.title = "x"
        store.requestUpdate(from: store.timedEvents[0], to: renamed)
        store.cancelPendingEdit()
        #expect(store.pendingDelete == nil && store.pendingEdit == nil)
        #expect(source.spans.isEmpty)
    }

    @Test func confirmStillWorksIfDialogClearedPendingStateFirst() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        store.requestDelete(store.timedEvents[0])
        let item = store.pendingDelete!
        store.cancelPendingDelete() // SwiftUI may reset the binding before the button action
        store.confirmDelete(item, span: .thisEvent)
        #expect(source.stored.isEmpty)
    }
}

struct MonthGridTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var c = utc
        c.firstWeekday = firstWeekday
        return c
    }

    @Test func wholeWeeksFromTheFirstWeekday() {
        // September 2026 starts on a Tuesday and ends on a Wednesday.
        let monday = MonthGrid.days(of: at(12, day: 15), calendar: calendar(firstWeekday: 2))
        #expect(monday.count == 35)
        #expect(utc.component(.day, from: monday.first!) == 31)   // Mon 31 Aug
        #expect(utc.component(.day, from: monday.last!) == 4)     // Sun 4 Oct
        let sunday = MonthGrid.days(of: at(12, day: 15), calendar: calendar(firstWeekday: 1))
        #expect(utc.component(.day, from: sunday.first!) == 30)   // Sun 30 Aug
        #expect(sunday.count % 7 == 0)
    }

    @Test func weekdayInitialsFollowTheFirstWeekday() {
        var c = calendar(firstWeekday: 2)
        c.locale = Locale(identifier: "en_US")
        #expect(MonthGrid.weekdaySymbols(calendar: c) == ["M", "T", "W", "T", "F", "S", "S"])
    }
}
