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
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Calendar.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    static func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }
}
