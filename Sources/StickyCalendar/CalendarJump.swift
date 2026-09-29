import AppKit
import StickyCalendarCore

/// The header's calendar button (and ⌘O): opens Calendar.app, on the sticky's day if the
/// user chose that. Asks which behaviour they want the first time.
@MainActor
enum CalendarJump {
    static func perform(day: Date, settings: AppSettings, store: CalendarStore) {
        switch settings.calendarJumpMode ?? ask(settings) {
        case .justOpen:
            SystemLinks.openCalendarApp()
        case .sameDay:
            if !SystemLinks.showDayInCalendar(day) {
                SystemLinks.openCalendarApp()
                store.lastError = "To open Calendar on the same day, allow Sticky Calendar under System Settings → Privacy & Security → Automation."
            }
        }
    }

    private static func ask(_ settings: AppSettings) -> CalendarJumpMode {
        let alert = NSAlert()
        alert.messageText = "Open Calendar on the day shown in the sticky?"
        alert.informativeText = "For this, macOS will ask to let Sticky Calendar control Calendar. You can change this later in Settings."
        alert.addButton(withTitle: "Show Same Day")
        alert.addButton(withTitle: "Just Open Calendar")
        NSApp.activate()
        let mode: CalendarJumpMode = alert.runModal() == .alertFirstButtonReturn ? .sameDay : .justOpen
        settings.setCalendarJumpMode(mode)
        return mode
    }
}
