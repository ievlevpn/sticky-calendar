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
        /// An Obsidian-style `#tag`.
        case tag
        /// LaTeX math with its delimiters: `$…$` inline, `$$…$$` display (may span lines).
        case math(display: Bool)
    }

    public let range: NSRange
    public let style: Style

    public init(_ range: NSRange, _ style: Style) {
        self.range = range
        self.style = style
    }
}

/// Finds the Markdown in a note: block syntax per line (headings, lists, tasks, quotes),
/// inline syntax (code, bold, italic, strikethrough, links) and LaTeX math. Nothing is
/// matched inside inline code or math.
public enum MarkdownStyler {
    public static func spans(in text: String) -> [MarkdownSpan] {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var spans: [MarkdownSpan] = []

        // Code, then math, claim their text first: nothing else is Markdown inside them.
        var verbatim: [NSRange] = []
        func isFree(_ range: NSRange) -> Bool {
            !verbatim.contains { NSIntersectionRange($0, range).length > 0 }
        }
        for m in Pattern.code.matches(in: text, range: whole) {
            verbatim.append(m.range)
            spans += wrapped(m, style: .code)
        }
        var displayMath: [NSRange] = []
        for (pattern, display) in [(Pattern.displayMath, true), (Pattern.inlineMath, false)] {
            for m in pattern.matches(in: text, range: whole) where isFree(m.range) {
                verbatim.append(m.range)
                if display { displayMath.append(m.range) }
                spans.append(MarkdownSpan(m.range, .math(display: display)))
                spans += wrapped(m, style: nil)
            }
        }

        ns.enumerateSubstrings(in: whole, options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            // A line of a display-math block is TeX, not a list item or heading.
            guard !displayMath.contains(where: { NSIntersectionRange($0, line).length > 0 }) else { return }
            spans += blockSpans(ns, line: line)
        }

        for pattern in [Pattern.boldStar, Pattern.boldUnderscore] {
            for m in pattern.matches(in: text, range: whole) where isFree(m.range) {
                spans += wrapped(m, style: .bold)
            }
        }
        // The italic patterns refuse a delimiter next to another one, so `**` never reads as italic.
        for pattern in [Pattern.italicStar, Pattern.italicUnderscore] {
            for m in pattern.matches(in: text, range: whole) where isFree(m.range) {
                spans += wrapped(m, style: .italic)
            }
        }
        for m in Pattern.strike.matches(in: text, range: whole) where isFree(m.range) {
            spans += wrapped(m, style: .strikethrough)
        }
        for m in Pattern.link.matches(in: text, range: whole) where isFree(m.range) {
            let label = m.range(at: 1), target = m.range(at: 2)
            guard let url = URL(string: ns.substring(with: target)), url.scheme != nil else { continue }
            verbatim.append(m.range) // its address isn't a bare link or a tag
            spans.append(MarkdownSpan(NSRange(location: m.range.location, length: 1), .marker))
            spans.append(MarkdownSpan(label, .link(url)))
            spans.append(MarkdownSpan(NSRange(location: NSMaxRange(label), length: NSMaxRange(m.range) - NSMaxRange(label)), .marker))
        }
        // Bare addresses are links too (without trailing punctuation, which usually ends the sentence).
        for m in Pattern.bareLink.matches(in: text, range: whole) where isFree(m.range) {
            var range = m.range
            while range.length > 0, let last = ns.substring(with: NSRange(location: NSMaxRange(range) - 1, length: 1)).first,
                  ".,;:!?)]}'\"".contains(last) {
                range.length -= 1
            }
            guard let url = URL(string: ns.substring(with: range)), url.host != nil else { continue }
            verbatim.append(range)
            spans.append(MarkdownSpan(range, .link(url)))
        }
        for m in Pattern.tag.matches(in: text, range: whole) where isFree(m.range) {
            spans.append(MarkdownSpan(m.range, .tag))
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

    /// Delimiters (outside capture group 1) as markers, the content with `style` (if any).
    private static func wrapped(_ m: NSTextCheckingResult, style: MarkdownSpan.Style?) -> [MarkdownSpan] {
        let inner = m.range(at: 1)
        return [
            MarkdownSpan(NSRange(location: m.range.location, length: inner.location - m.range.location), .marker),
            style.map { MarkdownSpan(inner, $0) },
            MarkdownSpan(NSRange(location: NSMaxRange(inner), length: NSMaxRange(m.range) - NSMaxRange(inner)), .marker),
        ].compactMap { $0 }
    }

    /// The first link in the text (a Markdown link's target, or a bare address).
    public static func firstLink(in text: String) -> URL? {
        spans(in: text).lazy.compactMap { span -> (Int, URL)? in
            if case .link(let url) = span.style { return (span.range.location, url) }
            return nil
        }.min { $0.0 < $1.0 }?.1
    }

    /// The TeX inside a math span, without its `$`/`$$` and surrounding blanks.
    public static func tex(of span: MarkdownSpan, in text: String) -> String? {
        guard case .math(let display) = span.style else { return nil }
        let delimiter = display ? 2 : 1
        let inner = NSRange(location: span.range.location + delimiter, length: span.range.length - 2 * delimiter)
        return (text as NSString).substring(with: inner).trimmingCharacters(in: .whitespacesAndNewlines)
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
        static let bareLink = regex(#"\bhttps?://[^\s<>]+"#)
        /// #tag, #nested/tag, #to-read — not a heading (which has a space) or a colour like #fff inside words.
        static let tag = regex(#"(?<![\w#&/])#[\p{L}_][\p{L}\p{N}_/-]*"#)
        /// `$$…$$`, possibly over several lines.
        static let displayMath = regex(#"(?<!\\)\$\$(?=[\s\S]*?\S[\s\S]*?\$\$)([\s\S]+?)\$\$"#)
        /// `$…$` on one line, Pandoc-style so prices don't match: no blank just inside the
        /// dollars, no digit right after the closing one.
        static let inlineMath = regex(#"(?<![\\$])\$(?=[^\s$])([^\n$]+?)(?<=[^\s\\])\$(?![\d$])"#)

        private static func regex(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
    }
}
