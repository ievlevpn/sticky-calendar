import Foundation
import Testing
@testable import StickyCalendarCore

struct MarkdownStylerTests {
    /// The styled substrings, e.g. `["**": marker, "hi": bold, …]`, in source order.
    private func styled(_ text: String) -> [String] {
        let ns = text as NSString
        return MarkdownStyler.spans(in: text)
            .filter { $0.range.length > 0 }
            .sorted { ($0.range.location, $0.range.length) < ($1.range.location, $1.range.length) }
            .map { "\(ns.substring(with: $0.range))=\(name($0.style))" }
    }

    private func name(_ style: MarkdownSpan.Style) -> String {
        switch style {
        case .marker: "marker"
        case .listMarker: "list"
        case .taskMarker(let checked): checked ? "task(x)" : "task( )"
        case .quoteMarker: "quote-marker"
        case .heading: "heading"
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strike"
        case .code: "code"
        case .quote: "quote"
        case .done: "done"
        case .link(let url): "link(\(url.absoluteString))"
        case .math(let display): display ? "display-math" : "math"
        }
    }

    @Test func plainTextHasNoSpans() {
        #expect(MarkdownStyler.spans(in: "just a thought, 2 * 3 = 6").isEmpty)
    }

    @Test func headings() {
        #expect(styled("## Today") == ["## =marker", "Today=heading"])
        #expect(styled("#hashtag").isEmpty)
    }

    @Test func boldItalicStrike() {
        #expect(styled("a **b** c") == ["**=marker", "b=bold", "**=marker"])
        #expect(styled("a __b__ c") == ["__=marker", "b=bold", "__=marker"])
        #expect(styled("*b*") == ["*=marker", "b=italic", "*=marker"])
        #expect(styled("_b_") == ["_=marker", "b=italic", "_=marker"])
        #expect(styled("~~b~~") == ["~~=marker", "b=strike", "~~=marker"])
    }

    @Test func underscoresInsideWordsAreNotItalic() {
        #expect(styled("snake_case_name").isEmpty)
    }

    @Test func nothingMatchesInsideCode() {
        #expect(styled("`**x**`") == ["`=marker", "**x**=code", "`=marker"])
    }

    @Test func listsAndTasks() {
        #expect(styled("- milk") == ["- =list"])
        #expect(styled("12. step") == ["12. =list"])
        #expect(styled("- [ ] open") == ["- [ ] =task( )"])
        #expect(styled("- [x] shut") == ["- [x] =task(x)", "shut=done"])
    }

    @Test func quotes() {
        #expect(styled("> so it goes") == ["> =quote-marker", "so it goes=quote"])
    }

    @Test func links() {
        #expect(styled("see [docs](https://a.b/c)") == [
            "[=marker", "docs=link(https://a.b/c)", "](https://a.b/c)=marker",
        ])
        #expect(styled("[not](a link)").isEmpty)
    }

    @Test func blockSyntaxAppliesPerLine() {
        #expect(styled("# A\nplain\n- b") == ["# =marker", "A=heading", "- =list"])
    }

    @Test func inlineMath() {
        #expect(styled("so $e^{i\\pi}+1=0$ holds") == ["$=marker", "$e^{i\\pi}+1=0$=math", "$=marker"])
    }

    @Test func displayMathMaySpanLines() {
        let text = "$$\n\\int_0^1 x\\,dx\n$$"
        #expect(styled(text) == ["$$=marker", "$$\n\\int_0^1 x\\,dx\n$$=display-math", "$$=marker"])
        let span = MarkdownStyler.spans(in: text).first { $0.style == .math(display: true) }!
        #expect(MarkdownStyler.tex(of: span, in: text) == "\\int_0^1 x\\,dx")
    }

    @Test func pricesAndBlankDollarsAreNotMath() {
        #expect(styled("costs $5 and $10").isEmpty)
        #expect(styled("$ x$ and $x $").isEmpty)
        #expect(styled("escaped \\$x$").isEmpty)
    }

    @Test func nothingElseIsMarkdownInsideMath() {
        #expect(styled("$a*b*c$") == ["$=marker", "$a*b*c$=math", "$=marker"])
        #expect(styled("$$\n- x\n$$").filter { $0.hasSuffix("=list") }.isEmpty)
    }

    @Test func mathInsideCodeStaysCode() {
        #expect(styled("`$x$`") == ["`=marker", "$x$=code", "`=marker"])
    }
}
