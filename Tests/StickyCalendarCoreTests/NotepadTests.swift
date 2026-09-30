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

    private func tempFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    @Test func aFolderKeepsEachDaysNoteAsAMarkdownFile() {
        let folder = tempFolder()
        let n = Notepad(defaults: defaults, calendar: utc, day: at(9))
        n.setFolder(folder.path)
        n.setText("# Monday")
        #expect(read(folder.appendingPathComponent("2026-09-28.md")) == "# Monday")
        n.setDay(at(9, day: 29))
        #expect(n.text.isEmpty)
        n.setText("")                                   // an empty note makes no file
        #expect(read(folder.appendingPathComponent("2026-09-29.md")) == nil)
        n.setPerDay(false)
        n.setText("one note")
        #expect(read(folder.appendingPathComponent(NoteFileNames().singlePath)) == "one note")
        // Read back by a fresh instance.
        let reloaded = Notepad(defaults: defaults, calendar: utc, day: at(9))
        #expect(reloaded.folderPath == folder.path && reloaded.text == "one note")
    }

    @Test func choosingAFolderCopiesNotesInWithoutOverwriting() throws {
        let folder = tempFolder()
        try "already there".write(to: folder.appendingPathComponent("2026-09-28.md"), atomically: true, encoding: .utf8)
        let n = Notepad(defaults: defaults, calendar: utc, day: at(9))
        n.setText("in the app, 28th")
        n.setDay(at(9, day: 27))
        n.setText("in the app, 27th")
        n.setFolder(folder.path)
        #expect(read(folder.appendingPathComponent("2026-09-28.md")) == "already there")
        #expect(read(folder.appendingPathComponent("2026-09-27.md")) == "in the app, 27th")
        n.setDay(at(9))
        #expect(n.text == "already there")
    }

    @Test func picksUpEditsMadeElsewhereAndBringsFilesBackIntoTheApp() throws {
        let folder = tempFolder()
        let n = Notepad(defaults: defaults, calendar: utc, day: at(9))
        n.setFolder(folder.path)
        n.setText("mine")
        try "edited in Obsidian".write(to: folder.appendingPathComponent("2026-09-28.md"), atomically: true, encoding: .utf8)
        n.reloadFromFolder()
        #expect(n.text == "edited in Obsidian")
        n.setFolder(nil)
        #expect(n.text == "edited in Obsidian")
        #expect(read(folder.appendingPathComponent("2026-09-28.md")) == "edited in Obsidian") // files stay
    }

    @Test func customNamesPutDayNotesInFoldersAndReadThemBack() throws {
        let folder = tempFolder()
        let n = Notepad(defaults: defaults, calendar: utc, day: at(9, day: 30))
        n.setFolder(folder.path)
        n.setFileNames(NoteFileNames(dayPattern: "YYYY/MM/YYYY-MM-DD dddd", singleName: "Scratch"))
        n.setText("Wednesday's")
        #expect(read(folder.appendingPathComponent("2026/09/2026-09-30 Wednesday.md")) == "Wednesday's")
        n.setPerDay(false)
        n.setText("single")
        #expect(read(folder.appendingPathComponent("Scratch.md")) == "single")
        n.setPerDay(true)
        n.setFolder(nil)                                          // back into the app, found in subfolders
        #expect(n.text == "Wednesday's")
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

    @Test func placementAndItsPinPersist() {
        let n = Notepad(defaults: defaults, calendar: utc, day: at(9))
        #expect(n.placement == .pane && n.isWindowPinned)
        n.setPlacement(.window)
        n.setWindowPinned(false)
        let r = Notepad(defaults: defaults, calendar: utc, day: at(9))
        #expect(r.placement == .window && !r.isWindowPinned)
    }
}
