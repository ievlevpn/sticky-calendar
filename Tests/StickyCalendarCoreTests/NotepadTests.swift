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
        let n = Notepad(defaults: defaults, calendar: utc, day: at(9))
        n.setVisible(true)
        n.setText("- [ ] call **Anna**")
        n.setHeight(200)
        let reloaded = Notepad(defaults: defaults, calendar: utc, day: at(18))
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

    @Test func eachDayHasItsOwnNoteByDefault() {
        let n = Notepad(defaults: defaults, calendar: utc, day: at(9))
        #expect(n.isPerDay)
        n.setText("monday")
        n.setDay(at(9, day: 29))
        #expect(n.text.isEmpty)
        n.setText("tuesday")
        n.setDay(at(23, day: 28))
        #expect(n.text == "monday")
        #expect(n.hasNote(on: at(0, day: 29)) && !n.hasNote(on: at(0, day: 30)))
        #expect(Notepad(defaults: defaults, calendar: utc, day: at(8, day: 29)).text == "tuesday")
    }

    @Test func clearingADaysNoteForgetsIt() {
        let n = Notepad(defaults: defaults, calendar: utc, day: at(9))
        n.setText("x")
        n.setText("")
        #expect(!n.hasNote(on: at(9)))
    }

    @Test func aSingleNoteIsSharedByEveryDay() {
        let n = Notepad(defaults: defaults, calendar: utc, day: at(9))
        n.setText("today")
        n.setPerDay(false)
        n.setText("everywhere")
        n.setDay(at(9, day: 30))
        #expect(n.text == "everywhere")
        n.setPerDay(true)
        #expect(n.text.isEmpty)                      // the 30th has no note of its own
        n.setDay(at(9))
        #expect(n.text == "today")
    }

    @Test func theExistingNoteBecomesTodaysOnFirstRun() {
        defaults.set("from before", forKey: "noteText")   // a note saved by 0.4.0
        let n = Notepad(defaults: defaults, calendar: utc, day: at(9))
        #expect(n.text == "from before")
        n.setDay(at(9, day: 29))
        #expect(n.text.isEmpty)
        n.setPerDay(false)
        #expect(n.text == "from before")
    }
}
