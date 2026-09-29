import Foundation
import Testing
@testable import StickyCalendarCore

struct LivePreviewTests {
    private func preview(_ text: String, cursor: Int?) -> LivePreview {
        LivePreview(text: text, spans: MarkdownStyler.spans(in: text),
                    selection: cursor.map { [NSRange(location: $0, length: 0)] })
    }

    /// The text as drawn: hidden characters dropped, decorations as •, ☐/☑, ┃.
    private func drawn(_ text: String, cursor: Int?) -> String {
        let p = preview(text, cursor: cursor)
        let ns = text as NSString
        return (0..<ns.length).compactMap { i -> String? in
            if p.hidden.contains(i) { return nil }
            switch p.decorations[i] {
            case .bullet: return "•"
            case .task(let checked, _): return checked ? "☑" : "☐"
            case .quote: return "┃"
            case .math(let tex, let display, _): return display ? "[[\(tex)]]" : "[\(tex)]"
            case nil: return ns.substring(with: NSRange(location: i, length: 1))
            }
        }.joined()
    }

    @Test func rendersEverythingWhenNotEditing() {
        #expect(drawn("## Plan\n**bold** and [docs](https://a.b)", cursor: nil) == "Plan\nbold and docs")
    }

    @Test func showsTheSourceOfTheLineBeingEdited() {
        let text = "**a**\n**b**\n**c**"
        #expect(drawn(text, cursor: 7) == "a\n**b**\nc")
        #expect(drawn(text, cursor: 0) == "**a**\nb\nc")
        #expect(drawn(text, cursor: 17) == "a\nb\n**c**") // at the very end
    }

    @Test func aSelectionRevealsEveryLineItTouches() {
        let text = "*a*\n*b*\n*c*"
        let p = LivePreview(text: text, spans: MarkdownStyler.spans(in: text), selection: [NSRange(location: 1, length: 5)])
        #expect(p.hidden == IndexSet([8, 10]))
    }

    @Test func listMarkersBecomeBulletsKeepingIndentation() {
        #expect(drawn("- a\n  * b\n3. c", cursor: nil) == "•a\n  •b\n3. c") // the gap after a marker is part of its drawn width
    }

    @Test func tasksBecomeBoxesThatKnowTheirMark() {
        let text = "- [ ] open\n- [x] shut"
        #expect(drawn(text, cursor: nil) == "☐open\n☑shut")
        let p = preview(text, cursor: nil)
        #expect(p.decorations[0] == .task(checked: false, mark: NSRange(location: 3, length: 1)))
        #expect(p.decorations[11] == .task(checked: true, mark: NSRange(location: 14, length: 1)))
    }

    @Test func quotesGetABar() {
        #expect(drawn("> hm", cursor: nil) == "┃hm")
    }

    @Test func plainTextIsUntouched() {
        let p = preview("2 * 3 = 6\nsnake_case", cursor: nil)
        #expect(p.hidden.isEmpty && p.decorations.isEmpty)
    }

    @Test func mathIsDrawnInPlaceOfItsSource() {
        #expect(drawn("area $\\pi r^2$ ok", cursor: nil) == "area [\\pi r^2] ok")
        #expect(drawn("a\n$$\nx^2\n$$\nb", cursor: nil) == "a\n[[x^2]]\nb")
    }

    @Test func editingAnyLineOfADisplayBlockShowsItsSource() {
        let text = "a\n$$\nx^2\n$$\nb"
        #expect(drawn(text, cursor: 5) == text)          // on the `x^2` line
        #expect(drawn(text, cursor: 0) == "a\n[[x^2]]\nb")
    }

    @Test func mathThatCantBeDrawnShowsItsSource() {
        let text = "$\\bogus$"
        let p = LivePreview(text: text, spans: MarkdownStyler.spans(in: text), selection: nil) { _, _ in false }
        #expect(p.decorations.isEmpty)
        #expect(p.hidden == IndexSet([0, 7]))            // just the dollars, like other syntax
    }
}
