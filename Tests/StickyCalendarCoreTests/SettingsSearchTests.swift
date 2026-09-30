import Testing
@testable import StickyCalendarCore

struct SettingsSearchTests {
    private let settings: [(title: String, keywords: [String])] = [
        ("Opacity", ["transparency", "appearance"]),
        ("Fade when idle", ["fade after", "dim"]),
        ("Keep notes in a folder", ["markdown", "obsidian", "vault"]),
        ("Launch at login", ["startup"]),
    ]

    private func search(_ query: String) -> [String] {
        SettingsSearch.rank(settings, query: query) { [$0.title] + $0.keywords }.map(\.title)
    }

    @Test func findsByLooseTitleOrKeyword() {
        #expect(search("fde").first == "Fade when idle")
        #expect(search("obsid") == ["Keep notes in a folder"])
        #expect(search("startup") == ["Launch at login"])
    }

    @Test func titleMatchesRankFirstAndScatteredLettersDontCount() {
        #expect(search("opa").first == "Opacity")
        #expect(search("eto").isEmpty)                     // e…t…o scattered through "Keep notes in a folder"
        #expect(search("").count == settings.count)
    }
}
