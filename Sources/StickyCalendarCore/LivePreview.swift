import Foundation

/// Obsidian-style live preview of a note: Markdown syntax is hidden on every line except
/// the ones holding the cursor or selection; list, task and quote markers are drawn as a
/// bullet, a checkbox or a bar, and math as the typeset formula. The text itself never
/// changes.
public struct LivePreview: Equatable, Sendable {
    public enum Decoration: Equatable, Sendable {
        case bullet
        /// `mark` is the ` `/`x` between the brackets, for ticking the box.
        case task(checked: Bool, mark: NSRange)
        case quote
        /// A formula drawn over its whole source `range` (the first character stands in for
        /// it; the rest, line breaks included, is hidden).
        case math(tex: String, display: Bool, range: NSRange)
    }

    /// Characters laid out with no width.
    public let hidden: IndexSet
    /// Characters drawn as a decoration instead of themselves (one per marker).
    public let decorations: [Int: Decoration]

    /// `selection` is nil when the note isn't being edited: then every line is rendered.
    public init(text: String, spans: [MarkdownSpan], selection: [NSRange]?) {
        self.init(text: text, spans: spans, selection: selection, canDraw: { _, _ in true })
    }

    /// `canDraw` says whether a formula can be typeset; one that can't shows its source.
    public init(text: String, spans: [MarkdownSpan], selection: [NSRange]?,
                canDraw: (_ tex: String, _ display: Bool) -> Bool) {
        let ns = text as NSString
        let editing = (selection ?? []).map { ns.paragraphRange(for: $0) }
        func isEditing(_ range: NSRange) -> Bool {
            editing.contains {
                NSLocationInRange(range.location, $0) || NSIntersectionRange(range, $0).length > 0
                    || range.location == NSMaxRange($0) && $0.location == ns.length
            }
        }

        var hidden = IndexSet()
        var decorations: [Int: Decoration] = [:]
        /// Draws the marker's first non-blank character as `decoration` and hides the rest;
        /// indentation stays.
        func decorate(_ range: NSRange, as decoration: Decoration) {
            let marker = ns.substring(with: range)
            let indent = marker.prefix { $0 == " " || $0 == "\t" }.utf16.count
            decorations[range.location + indent] = decoration
            hidden.insert(integersIn: (range.location + indent + 1)..<NSMaxRange(range))
        }

        // A formula being edited on any of its lines shows all of its source, delimiters too.
        let editedMath = spans.filter { if case .math = $0.style { isEditing($0.range) } else { false } }.map(\.range)
        func isInEditedMath(_ range: NSRange) -> Bool {
            editedMath.contains { NSIntersectionRange($0, range).length == range.length }
        }

        for span in spans where span.range.length > 0 && !isEditing(span.range) && !isInEditedMath(span.range) {
            switch span.style {
            case .marker:
                hidden.insert(integersIn: span.range.location..<NSMaxRange(span.range))
            case .listMarker:
                let body = ns.substring(with: span.range).trimmingCharacters(in: .whitespaces)
                if ["-", "*", "+"].contains(body) { decorate(span.range, as: .bullet) } // numbers read fine as they are
            case .taskMarker(let checked):
                let open = ns.range(of: "[", range: span.range).location
                decorate(span.range, as: .task(checked: checked, mark: NSRange(location: open + 1, length: 1)))
            case .quoteMarker:
                decorate(span.range, as: .quote)
            case .math(let display):
                let tex = MarkdownStyler.tex(of: span, in: text) ?? ""
                guard canDraw(tex, display) else { continue }
                decorations[span.range.location] = .math(tex: tex, display: display, range: span.range)
                hidden.insert(integersIn: (span.range.location + 1)..<NSMaxRange(span.range))
            default:
                continue
            }
        }
        // A marker span can cover a decorated character (a formula's opening `$`).
        for index in decorations.keys { hidden.remove(index) }
        self.hidden = hidden
        self.decorations = decorations
    }
}
