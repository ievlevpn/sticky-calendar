import Foundation

/// How note files are named when notes are kept in a folder. A day's note takes its name
/// from a pattern in the date tokens Obsidian's daily notes (and its plugins) use:
/// `YYYY` year, `MM` / `M` month, `MMM` / `MMMM` its name, `DD` / `D` day, `ddd` / `dddd`
/// weekday, `[text]` as is. A `/` makes folders: `YYYY/MM/YYYY-MM-DD` files each day under
/// its year and month.
public struct NoteFileNames: Equatable, Sendable {
    public static let defaultDayPattern = "YYYY-MM-DD"
    public static let defaultSingleName = "Sticky Note"
    /// Common choices, offered next to the field.
    public static let dayPatternPresets = [
        "YYYY-MM-DD", "YYYY-MM-DD dddd", "DD.MM.YYYY", "YYYY/MM/YYYY-MM-DD", "YYYY/YYYY-MM-DD",
    ]

    /// Cleaned up: no `.md` ending, no leading or trailing `/`, no `..`; blank means the default.
    public let dayPattern: String
    public let singleName: String

    public init(dayPattern: String = Self.defaultDayPattern, singleName: String = Self.defaultSingleName) {
        self.dayPattern = Self.cleaned(dayPattern) ?? Self.defaultDayPattern
        self.singleName = Self.cleaned(singleName) ?? Self.defaultSingleName
    }

    /// `date`'s note, relative to the folder: "2026-09-30.md".
    public func dayPath(for date: Date, calendar: Calendar) -> String {
        formatter(calendar).string(from: date) + ".md"
    }

    /// The single note, relative to the folder: "Sticky Note.md".
    public var singlePath: String { singleName + ".md" }

    /// The day a note file is for, if its path (relative to the folder) fits the pattern.
    public func day(fromPath path: String, calendar: Calendar) -> Date? {
        guard path.hasSuffix(".md") else { return nil }
        let name = String(path.dropLast(3))
        let formatter = formatter(calendar)
        guard let date = formatter.date(from: name), formatter.string(from: date) == name else { return nil }
        return calendar.startOfDay(for: date)
    }

    private func formatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX") // English names, as Obsidian's by default
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        formatter.dateFormat = Self.icuPattern(fromMoment: dayPattern)
        return formatter
    }

    /// The pattern in `DateFormatter`'s terms: tokens translated, everything else quoted.
    static func icuPattern(fromMoment moment: String) -> String {
        let tokens: [(String, String)] = [
            ("YYYY", "yyyy"), ("YY", "yy"), ("MMMM", "MMMM"), ("MMM", "MMM"), ("MM", "MM"), ("M", "M"),
            ("DD", "dd"), ("D", "d"), ("dddd", "EEEE"), ("ddd", "EEE"),
        ]
        var result = ""
        var literal = ""
        func flushLiteral() {
            guard !literal.isEmpty else { return }
            result += "'" + literal.replacingOccurrences(of: "'", with: "''") + "'"
            literal = ""
        }
        var rest = Substring(moment)
        while let first = rest.first {
            if first == "[", let close = rest.firstIndex(of: "]") {
                literal += rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
            } else if let (token, icu) = tokens.first(where: { rest.hasPrefix($0.0) }) {
                flushLiteral()
                result += icu
                rest = rest.dropFirst(token.count)
            } else {
                literal.append(first)
                rest = rest.dropFirst()
            }
        }
        flushLiteral()
        return result
    }

    private static func cleaned(_ name: String) -> String? {
        var name = name.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .joined(separator: "/")
        if name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
        return name.isEmpty ? nil : name
    }
}
