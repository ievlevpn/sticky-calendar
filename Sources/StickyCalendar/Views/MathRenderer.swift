import AppKit
import SwiftMath

/// A typeset formula the note can lay out and draw.
@MainActor
protocol RenderedMath: AnyObject {
    var width: CGFloat { get }
    /// Above the baseline.
    var ascent: CGFloat { get }
    /// Below the baseline.
    var descent: CGFloat { get }
    /// Draws with the left end of the baseline at `origin` in a flipped view's context.
    func draw(in context: CGContext, baselineOrigin origin: CGPoint, color: NSColor)
}

extension TypesetFormula: RenderedMath {}

/// Typesets the note's LaTeX. The only code that knows the math engine (SwiftMath, drawing
/// natively): swap it here, e.g. for MathJax, without touching the editor.
@MainActor
final class MathRenderer {
    static let shared = MathRenderer()

    /// Latin Modern at 13 pt has about the x-height of the note's 11 pt system text.
    static let fontSize: CGFloat = 13

    private struct Key: Hashable {
        let tex: String
        let display: Bool
    }

    /// Formulas by source, including the ones that failed (nil), so typing doesn't
    /// re-typeset every formula in the note.
    private var cache: [Key: RenderedMath?] = [:]

    func formula(_ tex: String, display: Bool) -> RenderedMath? {
        let key = Key(tex: tex, display: display)
        if let cached = cache[key] { return cached }
        if cache.count > 500 { cache.removeAll() } // edits leave old versions behind
        let formula = TypesetFormula(latex: tex, fontSize: Self.fontSize, display: display)
        cache[key] = formula
        return formula
    }
}
