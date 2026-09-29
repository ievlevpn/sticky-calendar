import Foundation

/// What the header's calendar button does; asked once, changeable in Settings.
public enum CalendarJumpMode: String, Sendable, CaseIterable {
    /// Open Calendar.app on the day shown in the sticky (AppleScript; needs Automation permission).
    case sameDay
    /// Just bring Calendar.app to the front.
    case justOpen
}

/// AppleScript for Calendar.app. macOS has no public URL for "show this date".
public enum CalendarScript {
    /// Switches Calendar to Day view on `date`'s day (as `calendar` sees it). The day is set
    /// to 1 before the month changes so e.g. "31st" + September can't roll into October.
    public static func showDay(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return """
        tell application "Calendar"
            activate
            switch view to day view
            set d to current date
            set day of d to 1
            set year of d to \(parts.year!)
            set month of d to \(parts.month!)
            set day of d to \(parts.day!)
            set time of d to 12 * hours
            view calendar at d
        end tell
        """
    }
}
