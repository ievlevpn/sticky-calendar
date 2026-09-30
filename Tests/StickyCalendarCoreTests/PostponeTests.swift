import Foundation
import Testing
@testable import StickyCalendarCore

struct PostponeTests {
    private func due(_ option: Postpone, from due: Date?, timed: Bool, now: Date = at(12, 7)) -> Postpone.Due {
        option.due(from: due, hasTime: timed, now: now, calendar: utc)
    }

    @Test func hoursCountFromNowAndGiveATime() {
        #expect(due(.oneHour, from: at(9), timed: true) == .init(date: at(13, 7), hasTime: true))   // overdue
        #expect(due(.threeHours, from: at(0), timed: false) == .init(date: at(15, 7), hasTime: true)) // date only
        #expect(due(.oneHour, from: nil, timed: false) == .init(date: at(13, 7), hasTime: true))
    }

    @Test func hoursDropTheSeconds() {
        let now = at(12, 7).addingTimeInterval(42)
        #expect(due(.oneHour, from: nil, timed: false, now: now).date == at(13, 7))
    }

    @Test func tomorrowAndNextWeekKeepTheTime() {
        #expect(due(.tomorrow, from: at(9, 30, day: 20), timed: true) == .init(date: at(9, 30, day: 29), hasTime: true))
        #expect(due(.nextWeek, from: at(17, day: 28), timed: true) == .init(date: at(17, day: 5 + 30), hasTime: true))
    }

    @Test func tomorrowAndNextWeekStayDateOnly() {
        #expect(due(.tomorrow, from: at(0), timed: false) == .init(date: at(0, day: 29), hasTime: false))
        #expect(due(.nextWeek, from: nil, timed: false) == .init(date: at(0, day: 35), hasTime: false))
    }

    @Test func crossesTheMonthEnd() {
        #expect(due(.tomorrow, from: nil, timed: false, now: at(20, day: 30)) == .init(date: at(0, day: 31), hasTime: false))
        #expect(utc.component(.month, from: at(0, day: 31)) == 10)
    }
}

@MainActor
struct PostponeStoreTests {
    @Test func postponeSavesTheNewDueDateAndUndoes() async {
        let name = "PostponeStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let source = FakeReminderSource()
        let store = ReminderStore(source: source, settings: ReminderSettings(defaults: defaults),
                                  calendar: utc, now: { at(12) })
        source.stored = [ReminderItem(id: "1", title: "Call bank", listID: "home", due: at(9), dueHasTime: true,
                                      isCompleted: false, completionDate: nil)]
        await store.reload()
        await store.postpone(store.items[0], .tomorrow)
        #expect(source.stored[0].due == at(9, day: 29) && source.stored[0].dueHasTime)
        store.undoManager.undo()
        await store.idle()
        #expect(source.stored[0].due == at(9))
    }
}
