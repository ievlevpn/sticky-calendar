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

    @Test func calendarButtonChoiceStartsUnaskedAndPersists() {
        let s = AppSettings(defaults: defaults)
        #expect(s.calendarJumpMode == nil)
        s.setCalendarJumpMode(.sameDay)
        #expect(AppSettings(defaults: defaults).calendarJumpMode == .sameDay)
        s.setCalendarJumpMode(.justOpen)
        #expect(AppSettings(defaults: defaults).calendarJumpMode == .justOpen)
    }

    @Test func unknownStoredCalendarButtonChoiceCountsAsUnasked() {
        defaults.set("somethingElse", forKey: "calendarJumpMode")
        #expect(AppSettings(defaults: defaults).calendarJumpMode == nil)
    }

    @Test func zoomStepsInAndOutAndStopsAtTheEnds() {
        let s = AppSettings(defaults: defaults)
        #expect(s.zoom == 1)
        s.zoomIn()
        #expect(s.zoom == 1.1)
        s.zoomIn(); s.zoomIn()
        #expect(s.zoom == 1.5)
        for _ in 0..<10 { s.zoomIn() }
        #expect(s.zoom == 2 && !s.canZoomIn)
        s.resetZoom()
        #expect(s.zoom == 1)
        for _ in 0..<10 { s.zoomOut() }
        #expect(s.zoom == 0.8 && !s.canZoomOut)
    }

    @Test func zoomPersistsAndSnapsToAStep() {
        let s = AppSettings(defaults: defaults)
        s.setZoom(1.3)
        #expect(s.zoom == 1.25)
        #expect(AppSettings(defaults: defaults).zoom == 1.25)
        defaults.set(7.0, forKey: "zoom")
        #expect(AppSettings(defaults: defaults).zoom == 2)
    }
}
