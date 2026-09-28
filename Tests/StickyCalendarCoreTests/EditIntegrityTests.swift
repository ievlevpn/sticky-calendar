import Foundation
import Testing
@testable import StickyCalendarCore

/// Edits must never change data the user did not touch, and undo/redo must keep working
/// when EventKit hands back a new identifier.
@MainActor
struct EditIntegrityTests {
    let source = FakeSource()
    let settings: AppSettings

    init() {
        let name = "EditIntegrityTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = AppSettings(defaults: defaults)
    }

    func makeStore() -> CalendarStore {
        CalendarStore(source: source, settings: settings, calendar: utc, now: { at(10) })
    }

    // MARK: Viewing is not editing

    @Test func closingEditorOnShortUntrimmedEventWritesNothing() {
        var short = event("s", at(10), at(10, 5))
        short.title = "Standup "
        source.stored = [short]
        let store = makeStore()
        let snapshot = store.timedEvents[0]
        store.requestEdit(of: snapshot, result: snapshot)
        store.requestUpdate(from: snapshot, to: snapshot)
        #expect(source.spans.isEmpty)
        #expect(store.pendingEdit == nil)
    }

    @Test func viewingRecurringEventDoesNotAskForSpan() {
        source.stored = [event("r", at(10), at(10), recurring: true)]
        let store = makeStore()
        let snapshot = store.timedEvents[0]
        store.requestEdit(of: snapshot, result: snapshot)
        #expect(store.pendingEdit == nil)
    }

    @Test func movingShortEventKeepsItsDuration() {
        source.stored = [event("s", at(10), at(10, 5))]
        let store = makeStore()
        let original = store.timedEvents[0]
        store.requestUpdate(from: original, to: EventDrag.apply(.move, to: original, delta: 3600))
        #expect(source.stored[0].start == at(11))
        #expect(source.stored[0].end == at(11, 5))
    }

    // MARK: Stale editor snapshots

    @Test func closingEditorKeepsChangesSyncedWhileItWasOpen() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        let snapshot = store.timedEvents[0]
        source.stored[0].title = "Synced"
        source.onChange?()
        store.requestEdit(of: snapshot, result: snapshot)
        #expect(source.spans.isEmpty)
        #expect(source.stored[0].title == "Synced")
    }

    @Test func editorAppliesOnlyTheFieldsTheUserChanged() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        let snapshot = store.timedEvents[0]
        source.stored[0].title = "Synced"
        source.onChange?()
        var result = snapshot
        result.location = "Room 1"
        store.requestEdit(of: snapshot, result: result)
        #expect(source.stored[0].title == "Synced")
        #expect(source.stored[0].location == "Room 1")
    }

    // MARK: Undo/redo across identifier changes

    @Test func redoChainSurvivesRecreatedEvent() {
        let store = makeStore()
        var draft = store.makeDraft(start: at(9), end: at(10))!
        draft.title = "Focus"
        let created = store.create(draft)!
        store.requestUpdate(from: created, to: EventDrag.apply(.move, to: created, delta: 3600))
        store.undoManager.undo() // move
        store.undoManager.undo() // create
        store.undoManager.redo() // create again: new identifier
        store.undoManager.redo() // move
        #expect(store.lastError == nil)
        #expect(store.timedEvents.map(\.start) == [at(10)])
    }

    @Test func undoChainSurvivesRestoredDelete() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        let original = store.timedEvents[0]
        store.requestUpdate(from: original, to: EventDrag.apply(.move, to: original, delta: 3600))
        store.confirmDelete(store.timedEvents[0], span: .thisEvent)
        store.undoManager.undo() // delete: restored with a new identifier
        store.undoManager.undo() // move
        #expect(store.lastError == nil)
        #expect(store.timedEvents.map(\.start) == [at(9)])
    }

    @Test func undoWorksAfterMovingEventToAnotherCalendar() {
        source.stored = [event("a", at(9), at(10))]
        let store = makeStore()
        let original = store.timedEvents[0]
        var moved = original
        moved.calendarID = "home"
        store.requestUpdate(from: original, to: moved)
        store.undoManager.undo()
        #expect(store.lastError == nil)
        #expect(source.stored.map(\.calendarID) == ["work"])
    }

    // MARK: Faithful restore

    @Test func undoDeleteRestoresUntitledEvent() {
        var untitled = event("u", at(9), at(10))
        untitled.title = ""
        source.stored = [untitled]
        let store = makeStore()
        store.confirmDelete(store.timedEvents[0], span: .thisEvent)
        store.undoManager.undo()
        #expect(store.timedEvents.count == 1)
    }

    @Test func undoDeleteKeepsAlarmsAndURL() {
        var e = event("a", at(9), at(10))
        e.alarmOffsets = [-600]
        e.url = URL(string: "https://example.com/meet")
        source.stored = [e]
        let store = makeStore()
        store.confirmDelete(store.timedEvents[0], span: .thisEvent)
        store.undoManager.undo()
        #expect(source.stored.first?.alarmOffsets == [-600])
        #expect(source.stored.first?.url == URL(string: "https://example.com/meet"))
    }

    @Test func deletingMeetingWithAttendeesIsNotUndoable() {
        var meeting = event("m", at(9), at(10))
        meeting.hasAttendees = true
        source.stored = [meeting]
        let store = makeStore()
        #expect(!store.timedEvents[0].canUndoDelete)
        store.confirmDelete(store.timedEvents[0], span: .thisEvent)
        #expect(!store.undoManager.canUndo)
    }
}
