import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct AppSettingsTests {
    let defaults: UserDefaults

    init() {
        let name = "AppSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    @Test func usesDefaultsWhenNothingStored() {
        let s = AppSettings(defaults: defaults)
        #expect(s.isPinned)
        #expect(s.hiddenCalendarIDs.isEmpty)
        #expect(s.opacity == 0.92)
    }

    @Test func persistsChangesAcrossInstances() {
        let s = AppSettings(defaults: defaults)
        s.setPinned(false)
        s.setCalendar("holidays", visible: false)
        s.setOpacity(0.7)
        let reloaded = AppSettings(defaults: defaults)
        #expect(!reloaded.isPinned)
        #expect(reloaded.hiddenCalendarIDs == ["holidays"])
        #expect(reloaded.opacity == 0.7)
    }

    @Test func clampsOpacity() {
        let s = AppSettings(defaults: defaults)
        s.setOpacity(0.1)
        #expect(s.opacity == 0.5)
        s.setOpacity(3)
        #expect(s.opacity == 1)
    }

    @Test func showingACalendarAgainRemovesItFromHidden() {
        let s = AppSettings(defaults: defaults)
        s.setCalendar("home", visible: false)
        s.setCalendar("home", visible: true)
        #expect(s.hiddenCalendarIDs.isEmpty)
    }
}
