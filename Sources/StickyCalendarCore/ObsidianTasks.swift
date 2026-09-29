import Foundation

/// One Markdown task line in the Obsidian Tasks plugin's format:
/// `- [ ] Call the bank ⏫ 📅 2026-09-30 ✅ 2026-09-29`. The title is everything before the
/// first metadata emoji; the metadata keeps its own order and is rewritten only where a
/// change needs it (📅 due, ⏰ due time, ✅ done), so other fields survive edits.
public struct ObsidianTask: Equatable, Sendable {
    public var indent: String
    public var bullet: Character
    public var isDone: Bool
    public var title: String
    /// Everything after the title, as written (📅, ✅, priority, recurrence, …).
    public var metadata: String

    /// Task-plugin fields, and the Reminder plugin's ⏰ (its date and time).
    static let metadataMarkers: [Character] = ["📅", "⏳", "🛫", "➕", "✅", "❌", "🔁", "⏫", "🔼", "🔽", "⏬", "🔺", "🆔", "⛔", "🏁", "⏰"]

    private static let line = try! NSRegularExpression(pattern: #"^(\s*)([-*+]) \[([ xX])\] (.*)$"#)

    /// nil for a line that isn't a task.
    public init?(line text: String) {
        let ns = text as NSString
        guard let m = Self.line.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        indent = ns.substring(with: m.range(at: 1))
        bullet = Character(ns.substring(with: m.range(at: 2)))
        isDone = ns.substring(with: m.range(at: 3)) != " "
        let body = ns.substring(with: m.range(at: 4))
        if let start = body.firstIndex(where: { Self.metadataMarkers.contains($0) }) {
            title = String(body[..<start]).trimmingCharacters(in: .whitespaces)
            metadata = String(body[start...]).trimmingCharacters(in: .whitespaces)
        } else {
            title = body.trimmingCharacters(in: .whitespaces)
            metadata = ""
        }
    }

    public init(indent: String = "", bullet: Character = "-", isDone: Bool = false, title: String, metadata: String = "") {
        self.indent = indent
        self.bullet = bullet
        self.isDone = isDone
        self.title = title
        self.metadata = metadata
    }

    public var line: String {
        let body = [title, metadata].filter { !$0.isEmpty }.joined(separator: " ")
        return "\(indent)\(bullet) [\(isDone ? "x" : " ")] \(body)"
    }

    // MARK: Fields

    /// When it's due: 📅 date, or ⏰ date and time.
    public func due(calendar: Calendar) -> (date: Date, hasTime: Bool)? {
        if let text = value(after: "⏰"), let date = Self.parse(text, withTime: true, calendar: calendar) {
            return (date, true)
        }
        if let text = value(after: "📅"), let date = Self.parse(text, withTime: false, calendar: calendar) {
            return (date, false)
        }
        return nil
    }

    public func doneDate(calendar: Calendar) -> Date? {
        value(after: "✅").flatMap { Self.parse($0, withTime: false, calendar: calendar) }
    }

    public mutating func setDue(_ due: Date?, hasTime: Bool, calendar: Calendar) {
        remove("📅")
        remove("⏰")
        guard let due else { return }
        append("📅 \(Self.format(due, withTime: false, calendar: calendar))")
        if hasTime { append("⏰ \(Self.format(due, withTime: true, calendar: calendar))") }
    }

    /// Ticks (adding ✅ and the date, as the Tasks plugin does) or unticks.
    public mutating func setDone(_ done: Bool, on date: Date, calendar: Calendar) {
        isDone = done
        remove("✅")
        if done { append("✅ \(Self.format(date, withTime: false, calendar: calendar))") }
    }

    // MARK: Metadata editing

    /// The text after `marker` up to the next marker.
    private func value(after marker: Character) -> String? {
        guard let start = metadata.firstIndex(of: marker) else { return nil }
        let rest = metadata[metadata.index(after: start)...]
        let end = rest.firstIndex(where: { Self.metadataMarkers.contains($0) }) ?? rest.endIndex
        return rest[..<end].trimmingCharacters(in: .whitespaces)
    }

    private mutating func remove(_ marker: Character) {
        guard let start = metadata.firstIndex(of: marker) else { return }
        let after = metadata.index(after: start)
        let end = metadata[after...].firstIndex(where: { Self.metadataMarkers.contains($0) }) ?? metadata.endIndex
        metadata.removeSubrange(start..<end)
        metadata = metadata.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private mutating func append(_ field: String) {
        metadata = metadata.isEmpty ? field : "\(metadata) \(field)"
    }

    private static func parse(_ text: String, withTime: Bool, calendar: Calendar) -> Date? {
        let formatter = dateFormatter(withTime: withTime, calendar: calendar)
        let prefix = String(text.prefix(withTime ? 16 : 10))
        return formatter.date(from: prefix)
    }

    /// A day as the Tasks plugin writes it: 2026-09-30.
    public static func dateString(_ date: Date, calendar: Calendar) -> String {
        format(date, withTime: false, calendar: calendar)
    }

    private static func format(_ date: Date, withTime: Bool, calendar: Calendar) -> String {
        dateFormatter(withTime: withTime, calendar: calendar).string(from: date)
    }

    private static func dateFormatter(withTime: Bool, calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = withTime ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return f
    }
}
