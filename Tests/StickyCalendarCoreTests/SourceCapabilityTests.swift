import Foundation
import Testing
@testable import StickyCalendarCore

/// A source without times (Things) or importance (Things) never receives them.
@MainActor
struct SourceCapabilityTests {
    let source = FakeReminderSource()
    let store: ReminderStore

    init() {
        let name = "SourceCapabilityTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        store = ReminderStore(source: source, settings: ReminderSettings(defaults: defaults), calendar: utc, now: { at(12) })
        source.stored = [ReminderItem(id: "1", title: "Plan", listID: "home", due: at(0))]
        source.supportsTime = false
        source.supportsPriority = false
    }

    @Test func editKeepsTheDayAndDropsTheTimeAndImportance() async {
        await store.reload()
        await store.edit(store.items[0], title: "Plan", due: at(15, 30, day: 29), dueHasTime: true, priority: .high, notes: nil)
        #expect(source.stored[0].due == at(0, day: 29) && !source.stored[0].dueHasTime)
        #expect(source.stored[0].priority == .none)
    }

    @Test func postponingByHoursBecomesADay() async {
        await store.reload()
        await store.postpone(store.items[0], .threeHours)
        #expect(source.stored[0].due == at(0) && !source.stored[0].dueHasTime)
    }

    @Test func aTypedTimeIsDroppedFromANewOne() async {
        await store.reload()
        await store.add("Call Sam tomorrow 10am")
        let added = source.stored.first { $0.title == "Call Sam" }
        #expect(added?.dueHasTime == false)
        #expect(added.flatMap(\.due).map { utc.component(.hour, from: $0) } == 0)
    }

    @Test func hourPostponesAreMarked() {
        #expect(Postpone.allCases.filter(\.isHours) == [.oneHour, .threeHours])
    }

    @Test func deadlinesDefaultToNone() {
        #expect(ReminderItem(title: "x", listID: "l").deadline == nil)
    }
}
