import Foundation
import Observation

/// The scratch note under the timeline: its text, whether it's shown and how tall it is,
/// persisted on every change. By default each day has its own note, which follows the day
/// being viewed; otherwise there is a single note. Notes are kept in UserDefaults, or as
/// Markdown files in a folder the user picks (e.g. in an Obsidian vault): `2026-09-30.md`
/// for a day's note, like Obsidian's daily notes, and `Sticky Note.md` for the single note.
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
        static let folderPath = "noteFolderPath"
    }

    public static let minHeight: Double = 60
    public static let defaultHeight: Double = 140
    /// The single note's file name, when notes are kept in a folder.
    public static let singleNoteFileName = "Sticky Note.md"

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
    /// The folder notes are kept in as Markdown files; nil keeps them in the app.
    public private(set) var folderPath: String?
    /// Why the last save to the folder failed (nil when it worked).
    public private(set) var saveError: String?

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
        folderPath = defaults.string(forKey: Key.folderPath)
        text = ""
        isVisible = defaults.object(forKey: Key.isVisible) as? Bool ?? false
        placement = defaults.string(forKey: Key.placement).flatMap(NotePlacement.init(rawValue:)) ?? .pane
        isWindowPinned = defaults.object(forKey: Key.isWindowPinned) as? Bool ?? true
        height = max(defaults.object(forKey: Key.height) as? Double ?? Self.defaultHeight, Self.minHeight)
        text = stored(forKey: shownKey)
    }

    public func setText(_ value: String) {
        guard value != text else { return }
        text = value
        store(value, forKey: shownKey)
    }

    /// Shows `date`'s note (when notes are per day).
    public func setDay(_ date: Date) {
        day = calendar.startOfDay(for: date)
        dayKey = Self.key(for: date, calendar: calendar)
        if isPerDay { text = stored(forKey: dayKey) }
    }

    public func setPerDay(_ perDay: Bool) {
        isPerDay = perDay
        defaults.set(perDay, forKey: Key.isPerDay)
        text = stored(forKey: shownKey)
    }

    /// Whether `date` has a per-day note.
    public func hasNote(on date: Date) -> Bool {
        !stored(forKey: Self.key(for: date, calendar: calendar)).isEmpty
    }

    // MARK: Where notes are kept

    /// Keeps notes as Markdown files in `path`, or (nil) in the app. Notes move along without
    /// overwriting: into the folder, the app's notes that have no file there yet; back into
    /// the app, every note file in the folder (the files stay).
    public func setFolder(_ path: String?) {
        if let path {
            copyAppNotes(into: path)
        } else if let old = folderPath {
            copyFolderNotes(from: old)
        }
        folderPath = path
        defaults.set(path, forKey: Key.folderPath)
        saveError = nil
        text = stored(forKey: shownKey)
    }

    /// Picks up changes made to the note's file elsewhere (e.g. in Obsidian).
    public func reloadFromFolder() {
        guard folderPath != nil else { return }
        let fresh = stored(forKey: shownKey)
        if fresh != text { text = fresh }
    }

    /// The shown note's key: the day's, or nil for the single note.
    private var shownKey: String? { isPerDay ? dayKey : nil }

    private func fileURL(forKey key: String?, in folder: String) -> URL {
        URL(fileURLWithPath: folder, isDirectory: true)
            .appendingPathComponent(key.map { "\($0).md" } ?? Self.singleNoteFileName)
    }

    private func stored(forKey key: String?) -> String {
        if let folderPath {
            return (try? String(contentsOf: fileURL(forKey: key, in: folderPath), encoding: .utf8)) ?? ""
        }
        guard let key else { return singleNote }
        return dayNotes[key] ?? ""
    }

    private func store(_ value: String, forKey key: String?) {
        if let folderPath {
            let url = fileURL(forKey: key, in: folderPath)
            // An empty note gets no file; one that had a file keeps it, emptied.
            if value.isEmpty && !FileManager.default.fileExists(atPath: url.path) { return }
            do {
                try value.write(to: url, atomically: true, encoding: .utf8)
                saveError = nil
            } catch {
                saveError = error.localizedDescription
            }
            return
        }
        if let key {
            dayNotes[key] = value.isEmpty ? nil : value
            defaults.set(dayNotes, forKey: Key.dayNotes)
        } else {
            singleNote = value
            defaults.set(value, forKey: Key.text)
        }
    }

    private func copyAppNotes(into folder: String) {
        var notes = dayNotes.map { (key: Optional($0.key), text: $0.value) }
        notes.append((key: nil, text: singleNote))
        for note in notes where !note.text.isEmpty {
            let url = fileURL(forKey: note.key, in: folder)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try? note.text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func copyFolderNotes(from folder: String) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        for name in names {
            let key: String?
            if name == Self.singleNoteFileName {
                key = nil
            } else if name.range(of: #"^\d{4}-\d{2}-\d{2}\.md$"#, options: .regularExpression) != nil {
                key = String(name.dropLast(3))
            } else {
                continue
            }
            guard let text = try? String(contentsOf: fileURL(forKey: key, in: folder), encoding: .utf8) else { continue }
            if let key {
                dayNotes[key] = text.isEmpty ? nil : text
            } else {
                singleNote = text
            }
        }
        defaults.set(dayNotes, forKey: Key.dayNotes)
        defaults.set(singleNote, forKey: Key.text)
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
