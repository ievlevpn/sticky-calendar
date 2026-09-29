import Foundation

/// A styled range of Markdown source. The note is edited as plain text, so markers stay in
/// the text and are only dimmed; everything is drawn at one font size.
public struct MarkdownSpan: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        /// Inline syntax and heading hashes: `#`, `**`, `` ` ``, link brackets and URLs…
        case marker
        /// A list item's leading `- `, `* `, `+ ` or `1. ` (with its indentation).
        case listMarker
        /// A task's leading `- [ ] ` or `- [x] ` (with its indentation).
        case taskMarker(checked: Bool)
        /// A quote's leading `> `.
        case quoteMarker
        case heading
        case bold
        case italic
        case strikethrough
        case code
        case quote
        /// The text of a checked task (`- [x] …`).
        case done
        case link(URL)
    }

    public let range: NSRange
    public let style: Style

    public init(_ range: NSRange, _ style: Style) {
        self.range = range
        self.style = style
    }
}

/// Finds the Markdown in a note: block syntax per line (headings, lists, tasks, quotes)
/// and inline syntax (code, bold, italic, strikethrough, links). Nothing is matched
/// inside inline code.
public enum MarkdownStyler {
    public static func spans(in text: String) -> [MarkdownSpan] {
        let ns = text as NSString
        var spans: [MarkdownSpan] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            spans += blockSpans(ns, line: line)
        }

        var code: [NSRange] = []
        for m in Pattern.code.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            code.append(m.range)
            spans += wrapped(m, style: .code)
        }
        func outsideCode(_ m: NSTextCheckingResult) -> Bool {
            !code.contains { NSIntersectionRange($0, m.range).length > 0 }
        }
        let whole = NSRange(location: 0, length: ns.length)
        for pattern in [Pattern.boldStar, Pattern.boldUnderscore] {
            for m in pattern.matches(in: text, range: whole) where outsideCode(m) {
                spans += wrapped(m, style: .bold)
            }
        }
        // The italic patterns refuse a delimiter next to another one, so `**` never reads as italic.
        for pattern in [Pattern.italicStar, Pattern.italicUnderscore] {
            for m in pattern.matches(in: text, range: whole) where outsideCode(m) {
                spans += wrapped(m, style: .italic)
            }
        }
        for m in Pattern.strike.matches(in: text, range: whole) where outsideCode(m) {
            spans += wrapped(m, style: .strikethrough)
        }
        for m in Pattern.link.matches(in: text, range: whole) where outsideCode(m) {
            let label = m.range(at: 1), target = m.range(at: 2)
            guard let url = URL(string: ns.substring(with: target)), url.scheme != nil else { continue }
            spans.append(MarkdownSpan(NSRange(location: m.range.location, length: 1), .marker))
            spans.append(MarkdownSpan(label, .link(url)))
            spans.append(MarkdownSpan(NSRange(location: NSMaxRange(label), length: NSMaxRange(m.range) - NSMaxRange(label)), .marker))
        }
        return spans
    }

    private static func blockSpans(_ ns: NSString, line: NSRange) -> [MarkdownSpan] {
        let text = ns as String
        if let m = Pattern.heading.firstMatch(in: text, range: line) {
            return [MarkdownSpan(m.range(at: 1), .marker), MarkdownSpan(m.range(at: 2), .heading)]
        }
        if let m = Pattern.task.firstMatch(in: text, range: line) {
            let checked = ns.substring(with: m.range(at: 2)).lowercased() == "x"
            return [MarkdownSpan(m.range(at: 1), .taskMarker(checked: checked))]
                + (checked ? [MarkdownSpan(m.range(at: 3), .done)] : [])
        }
        if let m = Pattern.bullet.firstMatch(in: text, range: line) {
            return [MarkdownSpan(m.range(at: 1), .listMarker)]
        }
        if let m = Pattern.quote.firstMatch(in: text, range: line) {
            return [MarkdownSpan(m.range(at: 1), .quoteMarker), MarkdownSpan(m.range(at: 2), .quote)]
        }
        return []
    }

    /// Delimiters (outside capture group 1) as markers, the content with `style`.
    private static func wrapped(_ m: NSTextCheckingResult, style: MarkdownSpan.Style) -> [MarkdownSpan] {
        let inner = m.range(at: 1)
        return [
            MarkdownSpan(NSRange(location: m.range.location, length: inner.location - m.range.location), .marker),
            MarkdownSpan(inner, style),
            MarkdownSpan(NSRange(location: NSMaxRange(inner), length: NSMaxRange(m.range) - NSMaxRange(inner)), .marker),
        ]
    }

    private enum Pattern {
        static let heading = regex(#"^(#{1,6}[ \t]+)(.*)$"#)
        static let task = regex(#"^([ \t]*[-*+][ \t]+\[([ xX])\][ \t]+)(.*)$"#)
        static let bullet = regex(#"^([ \t]*(?:[-*+]|\d+[.)])[ \t]+)"#)
        static let quote = regex(#"^([ \t]*>[ \t]?)(.*)$"#)
        static let code = regex(#"`([^`\n]+)`"#)
        static let boldStar = regex(#"\*\*(?=\S)([^\n]+?)(?<=\S)\*\*"#)
        static let boldUnderscore = regex(#"(?<!\w)__(?=\S)([^\n]+?)(?<=\S)__(?!\w)"#)
        static let italicStar = regex(#"(?<![*\w])\*(?=[^\s*])([^\n*]+?)(?<=[^\s*])\*(?![*\w])"#)
        static let italicUnderscore = regex(#"(?<![_\w])_(?=[^\s_])([^\n_]+?)(?<=[^\s_])_(?![_\w])"#)
        static let strike = regex(#"~~(?=\S)([^\n]+?)(?<=\S)~~"#)
        static let link = regex(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)

        private static func regex(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
    }
}
