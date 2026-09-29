import Foundation
import Observation

/// The scratch note under the timeline: its text, whether it's shown and how tall it is,
/// persisted in UserDefaults on every change. By default each day has its own note, which
/// follows the day being viewed; otherwise there is a single note.
@MainActor
@Observable
public final class Notepad {
    private enum Key {
        static let text = "noteText"
        static let isVisible = "isNoteVisible"
        static let height = "noteHeight"
        static let isPerDay = "isNotePerDay"
        static let dayNotes = "dayNotes"
        static let placement = "notePlacement"
        static let isWindowPinned = "noteWindowPinned"
    }

    public static let minHeight: Double = 60
    public static let defaultHeight: Double = 140

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    /// Per-day notes by "yyyy-MM-dd"; empty ones are dropped.
    @ObservationIgnored private var dayNotes: [String: String]
    @ObservationIgnored private var singleNote: String
    @ObservationIgnored private var dayKey: String

    /// The note being shown: the viewed day's, or the single note.
    public private(set) var text: String
    /// A note per day (default) rather than one note for every day.
    public private(set) var isPerDay: Bool
    /// The day being viewed, as the note sees it.
    public private(set) var day: Date
    /// Under the timeline (default) or in its own sticky. `isVisible` is for either.
    public private(set) var placement: NotePlacement
    /// The note's own sticky floats on top.
    public private(set) var isWindowPinned: Bool
    /// Hidden until the user opens it from the header.
    public private(set) var isVisible: Bool
    /// Preferred height; the view may show less when the window is short.
    public private(set) var height: Double

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent, day: Date = Date()) {
        self.defaults = defaults
        self.calendar = calendar
        let single = defaults.string(forKey: Key.text) ?? ""
        let perDay = defaults.object(forKey: Key.isPerDay) as? Bool ?? true
        let key = Self.key(for: day, calendar: calendar)
        let notes: [String: String]
        if let stored = defaults.dictionary(forKey: Key.dayNotes) as? [String: String] {
            notes = stored
        } else {
            // First run with per-day notes: the existing note becomes today's (the single
            // note stays, for switching back).
            notes = single.isEmpty ? [:] : [key: single]
            defaults.set(notes, forKey: Key.dayNotes)
        }
        singleNote = single
        isPerDay = perDay
        dayNotes = notes
        dayKey = key
        self.day = calendar.startOfDay(for: day)
        text = perDay ? notes[key] ?? "" : single
        isVisible = defaults.object(forKey: Key.isVisible) as? Bool ?? false
        placement = defaults.string(forKey: Key.placement).flatMap(NotePlacement.init(rawValue:)) ?? .pane
        isWindowPinned = defaults.object(forKey: Key.isWindowPinned) as? Bool ?? true
        height = max(defaults.object(forKey: Key.height) as? Double ?? Self.defaultHeight, Self.minHeight)
    }

    public func setText(_ value: String) {
        guard value != text else { return }
        text = value
        if isPerDay {
            dayNotes[dayKey] = value.isEmpty ? nil : value
            defaults.set(dayNotes, forKey: Key.dayNotes)
        } else {
            singleNote = value
            defaults.set(value, forKey: Key.text)
        }
    }

    /// Shows `date`'s note (when notes are per day).
    public func setDay(_ date: Date) {
        day = calendar.startOfDay(for: date)
        dayKey = Self.key(for: date, calendar: calendar)
        if isPerDay { text = dayNotes[dayKey] ?? "" }
    }

    public func setPerDay(_ perDay: Bool) {
        isPerDay = perDay
        defaults.set(perDay, forKey: Key.isPerDay)
        text = perDay ? dayNotes[dayKey] ?? "" : singleNote
    }

    /// Whether `date` has a per-day note.
    public func hasNote(on date: Date) -> Bool {
        dayNotes[Self.key(for: date, calendar: calendar)] != nil
    }

    private static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    public func setPlacement(_ value: NotePlacement) {
        placement = value
        defaults.set(value.rawValue, forKey: Key.placement)
    }

    public func setWindowPinned(_ pinned: Bool) {
        isWindowPinned = pinned
        defaults.set(pinned, forKey: Key.isWindowPinned)
    }

    public func setVisible(_ visible: Bool) {
        isVisible = visible
        defaults.set(visible, forKey: Key.isVisible)
    }

    public func setHeight(_ value: Double) {
        height = max(value, Self.minHeight)
        defaults.set(height, forKey: Key.height)
    }
}

/// Where the note appears.
public enum NotePlacement: String, Sendable, CaseIterable {
    /// Under the timeline, in the calendar sticky.
    case pane
    /// In its own sticky.
    case window
}
