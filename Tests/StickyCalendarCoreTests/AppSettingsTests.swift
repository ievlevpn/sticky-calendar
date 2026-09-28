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
        #expect(s.hourRange == HourRange(start: 8, end: 20))
        #expect(s.hiddenCalendarIDs.isEmpty)
        #expect(s.opacity == 0.92)
    }

    @Test func persistsChangesAcrossInstances() {
        let s = AppSettings(defaults: defaults)
        s.setStartHour(7)
        s.setEndHour(22)
        s.setCalendar("holidays", visible: false)
        s.setOpacity(0.7)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.hourRange == HourRange(start: 7, end: 22))
        #expect(reloaded.hiddenCalendarIDs == ["holidays"])
        #expect(reloaded.opacity == 0.7)
    }

    @Test func clampsOpacityAndKeepsRangeValid() {
        let s = AppSettings(defaults: defaults)
        s.setOpacity(0.1)
        #expect(s.opacity == 0.5)
        s.setStartHour(23)
        #expect(s.hourRange == HourRange(start: 23, end: 24))
    }

    @Test func showingACalendarAgainRemovesItFromHidden() {
        let s = AppSettings(defaults: defaults)
        s.setCalendar("home", visible: false)
        s.setCalendar("home", visible: true)
        #expect(s.hiddenCalendarIDs.isEmpty)
    }
}
