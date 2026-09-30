import Foundation
import Testing
@testable import StickyCalendarCore

struct NoteFileNamesTests {
    @Test func formatsObsidianStylePatterns() {
        let day = at(9, day: 30) // Wednesday, 30 September 2026
        #expect(NoteFileNames().dayPath(for: day, calendar: utc) == "2026-09-30.md")
        #expect(NoteFileNames(dayPattern: "YYYY/MM/YYYY-MM-DD dddd").dayPath(for: day, calendar: utc)
                == "2026/09/2026-09-30 Wednesday.md")
        #expect(NoteFileNames(dayPattern: "D MMM YY").dayPath(for: day, calendar: utc) == "30 Sep 26.md")
        #expect(NoteFileNames(dayPattern: "[Daily] DD.MM.YYYY").dayPath(for: day, calendar: utc) == "Daily 30.09.2026.md")
    }

    @Test func readsTheDayBackOnlyFromNamesThatFit() {
        let names = NoteFileNames(dayPattern: "YYYY/MM/YYYY-MM-DD")
        #expect(names.day(fromPath: "2026/09/2026-09-30.md", calendar: utc) == at(0, day: 30))
        #expect(names.day(fromPath: "2026-09-30.md", calendar: utc) == nil)
        #expect(names.day(fromPath: "2026/09/Ideas.md", calendar: utc) == nil)
    }

    @Test func cleansUpNamesAndFallsBackWhenBlank() {
        #expect(NoteFileNames(dayPattern: " /Journal/YYYY-MM-DD.md/ ").dayPattern == "Journal/YYYY-MM-DD")
        #expect(NoteFileNames(dayPattern: "../..", singleName: "  ").dayPattern == NoteFileNames.defaultDayPattern)
        #expect(NoteFileNames(singleName: "Scratch.md").singlePath == "Scratch.md")
        #expect(NoteFileNames(singleName: "").singlePath == "Sticky Note.md")
    }
}
