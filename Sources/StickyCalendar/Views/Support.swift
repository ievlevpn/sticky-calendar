import AppKit
import StickyCalendarCore
import SwiftUI

extension Color {
    init(rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

/// Translucent window material that follows light/dark mode.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

@MainActor
enum SystemLinks {
    /// Shows the event in Calendar.app; falls back to just opening Calendar.app.
    static func openInCalendar(_ item: EventItem) {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        if let external = item.externalIdentifier,
           let encoded = external.addingPercentEncoding(withAllowedCharacters: allowed),
           let url = URL(string: "ical://ekevent/\(encoded)?method=show&options=more"),
           NSWorkspace.shared.open(url) {
            return
        }
        openCalendarApp()
    }

    static func openCalendarApp() {
        // macOS 14 activation is cooperative: only the active app can hand focus to another.
        // The sticky never activates on click, so activate first or Calendar stays behind.
        NSApp.activate()
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Calendar.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    /// Opens Calendar.app in Day view on `date`. False if the script failed, e.g. because
    /// the user declined Automation permission (error -1743).
    static func showDayInCalendar(_ date: Date) -> Bool {
        NSApp.activate() // see openCalendarApp(): lets the script's `activate` take effect
        var error: NSDictionary?
        NSAppleScript(source: CalendarScript.showDay(date, calendar: .autoupdatingCurrent))?
            .executeAndReturnError(&error)
        return error == nil
    }

    static func openRemindersApp() {
        NSApp.activate() // see openCalendarApp()
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Reminders.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    static func openRemindersPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
    }

    static func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }
}
