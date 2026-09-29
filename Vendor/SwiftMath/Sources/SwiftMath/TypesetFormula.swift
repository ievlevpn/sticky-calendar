// Sticky Calendar: a public entry point for typesetting and drawing a formula
// (not part of upstream SwiftMath, whose typesetter is internal).
import CoreGraphics
import Foundation

public final class TypesetFormula {
    private let display: MTMathListDisplay

    public var width: CGFloat { display.width }
    /// Above the baseline.
    public var ascent: CGFloat { display.ascent }
    /// Below the baseline.
    public var descent: CGFloat { display.descent }

    /// nil when the TeX doesn't parse or the fonts are missing.
    public init?(latex: String, fontSize: CGFloat, display isDisplay: Bool) {
        guard SwiftMathFonts.isAvailable else { return nil }
        var error: NSError?
        guard let list = MTMathListBuilder.build(fromString: latex, error: &error), error == nil,
              let line = MTTypesetter.createLineForMathList(
                  list, font: MathFont.latinModernFont.mtfont(size: fontSize), style: isDisplay ? .display : .text
              ),
              line.width > 0
        else { return nil }
        display = line
    }

    /// Draws with the left end of the baseline at `origin`, in a context whose y axis points
    /// down (a flipped view).
    public func draw(in context: CGContext, baselineOrigin origin: CGPoint, color: MTColor) {
        // Flipped views also flip the text matrix; it isn't part of the graphics state.
        let textMatrix = context.textMatrix
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        display.position = .zero
        display.textColor = color
        display.draw(context)
        context.restoreGState()
        context.textMatrix = textMatrix
    }
}
