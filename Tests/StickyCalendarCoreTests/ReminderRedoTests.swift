import Foundation
import Testing
@testable import StickyCalendarCore

/// Reminder changes save asynchronously; undo and redo must still land on the right stacks.
@MainActor
struct ReminderRedoTests {
    let source = FakeReminderSource()
    let store: ReminderStore

    init() {
        let name = "ReminderRedoTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        store = ReminderStore(source: source, settings: ReminderSettings(defaults: defaults), calendar: utc, now: { at(12) })
        source.stored = [ReminderItem(id: "1", title: "A", listID: "home", due: at(9))]
    }

    private func undo() async {
        store.undoManager.undo()
        await store.idle()
    }

    private func redo() async {
        store.undoManager.redo()
        await store.idle()
    }

    @Test func renameUndoRedoUndo() async {
        await store.reload()
        await store.rename(store.items[0], to: "B")
        await undo()
        #expect(source.stored[0].title == "A")
        #expect(store.undoManager.canRedo && !store.undoManager.canUndo)
        await redo()
        #expect(source.stored[0].title == "B")
        await undo()
        #expect(source.stored[0].title == "A")
    }

    @Test func tickUndoRedo() async {
        await store.reload()
        await store.toggle(store.items[0])
        await undo()
        #expect(!source.stored[0].isCompleted)
        await redo()
        #expect(source.stored[0].isCompleted)
    }

    @Test func deleteUndoRedoUndo() async {
        await store.reload()
        await store.delete(store.items[0])
        await undo()
        #expect(source.stored.map(\.title) == ["A"])
        await redo()
        #expect(source.stored.isEmpty)
        await undo()
        #expect(source.stored.map(\.title) == ["A"])
    }

    @Test func addUndoRedo() async {
        await store.reload()
        await store.add("B")
        await undo()
        #expect(source.stored.map(\.title) == ["A"])
        await redo()
        #expect(source.stored.map(\.title) == ["A", "B"])
    }

    @Test func tickingARepeatUndoRedo() async {
        source.stored[0].isRepeating = true
        source.stored[0].dueHasTime = true
        source.repeatingIDs = ["1"]
        await store.reload()
        await store.toggle(store.items[0])
        await undo()
        #expect(source.stored[0].due == at(9))
        await redo()
        #expect(source.stored[0].due == at(9, day: 29))
        #expect(store.todaySections.flatMap(\.items).map(\.isCompleted) == [true])
    }
}
