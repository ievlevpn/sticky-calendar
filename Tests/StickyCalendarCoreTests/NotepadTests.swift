import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct NotepadTests {
    let defaults: UserDefaults

    init() {
        let name = "NotepadTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    @Test func startsHiddenAndEmpty() {
        let n = Notepad(defaults: defaults)
        #expect(!n.isVisible)
        #expect(n.text.isEmpty)
        #expect(n.height == Notepad.defaultHeight)
    }

    @Test func persistsChangesAcrossInstances() {
        let n = Notepad(defaults: defaults)
        n.setVisible(true)
        n.setText("- [ ] call **Anna**")
        n.setHeight(200)
        let reloaded = Notepad(defaults: defaults)
        #expect(reloaded.isVisible)
        #expect(reloaded.text == "- [ ] call **Anna**")
        #expect(reloaded.height == 200)
    }

    @Test func heightNeverDropsBelowMinimum() {
        let n = Notepad(defaults: defaults)
        n.setHeight(5)
        #expect(n.height == Notepad.minHeight)
        defaults.set(-40.0, forKey: "noteHeight")
        #expect(Notepad(defaults: defaults).height == Notepad.minHeight)
    }
}
