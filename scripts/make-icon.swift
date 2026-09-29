// Draws the app icon and writes Resources/AppIcon.icns:
//     swift scripts/make-icon.swift
// A yellow sticky note pinned on top, holding a day's timeline: hour lines, three events
// and the red now-line.
import AppKit

func drawIcon(in ctx: CGContext, size: CGFloat) {
    let s = size / 1024 // design on a 1024 grid
    ctx.scaleBy(x: s, y: s)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    // The note: macOS icon grid (824 pt body, 100 pt margin), a folded bottom-right corner.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let radius: CGFloat = 185, fold: CGFloat = 170
    let note = CGMutablePath()
    note.move(to: CGPoint(x: body.minX + radius, y: body.maxY))
    note.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.maxX, y: body.minY), radius: radius)
    note.addLine(to: CGPoint(x: body.maxX, y: body.minY + fold))
    note.addLine(to: CGPoint(x: body.maxX - fold, y: body.minY))
    note.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.minX, y: body.maxY), radius: radius)
    note.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.maxX, y: body.maxY), radius: radius)
    note.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x000000, 0.28))
    ctx.addPath(note)
    ctx.setFillColor(color(0xFFD84D))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(note)
    ctx.clip()
    let paper = CGGradient(colorsSpace: space, colors: [color(0xFFF1A6), color(0xFFD43B)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(paper, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    // Hour lines with their gutter ticks.
    let left: CGFloat = 250, right: CGFloat = 850
    for i in 0..<6 {
        let y = 770 - CGFloat(i) * 115
        ctx.setFillColor(color(0x8A6A00, 0.22))
        ctx.fill(CGRect(x: left, y: y - 2, width: right - left, height: 4))
        ctx.setFillColor(color(0x8A6A00, 0.45))
        ctx.fill(CGRect(x: 170, y: y - 4, width: 50, height: 8))
    }

    /// `hex` mixed three parts white.
    func tint(_ hex: UInt32) -> CGColor {
        func mix(_ c: UInt32) -> CGFloat { (CGFloat(c & 0xFF) / 255) * 0.3 + 0.7 }
        return CGColor(srgbRed: mix(hex >> 16), green: mix(hex >> 8), blue: mix(hex), alpha: 1)
    }

    // Events: light fill, solid leading bar — as on the timeline.
    func event(_ rect: CGRect, _ hex: UInt32) {
        let shape = CGPath(roundedRect: rect, cornerWidth: 26, cornerHeight: 26, transform: nil)
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.setFillColor(tint(hex)) // opaque: a see-through fill turns muddy on yellow
        ctx.fill(rect)
        ctx.setFillColor(color(hex))
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: 22, height: rect.height))
        // A title line.
        ctx.setFillColor(color(hex, 0.85))
        let title = CGRect(x: rect.minX + 50, y: rect.maxY - 58, width: min(rect.width - 90, 230), height: 26)
        ctx.addPath(CGPath(roundedRect: title, cornerWidth: 13, cornerHeight: 13, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
    }
    event(CGRect(x: left + 18, y: 548, width: 560, height: 200), 0x2F7CF6)
    event(CGRect(x: left + 18, y: 322, width: 330, height: 150), 0x34B35A)
    event(CGRect(x: left + 366, y: 300, width: 212, height: 172), 0xA25DDC)
    ctx.restoreGState()

    // The folded corner: a dog-ear lying on the note, its tip rounded.
    let tip = CGPoint(x: body.maxX - fold + 10, y: body.minY + fold - 10)
    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: body.maxX - fold, y: body.minY))
    flap.addLine(to: CGPoint(x: tip.x - 4, y: tip.y - 40))
    flap.addQuadCurve(to: CGPoint(x: tip.x + 40, y: tip.y + 4), control: CGPoint(x: tip.x - 6, y: tip.y + 6))
    flap.addLine(to: CGPoint(x: body.maxX, y: body.minY + fold))
    flap.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -4, height: 8), blur: 18, color: color(0x6B4E00, 0.40))
    ctx.addPath(flap)
    ctx.setFillColor(color(0xF5C73A))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(flap)
    ctx.clip()
    let flapShade = CGGradient(colorsSpace: space, colors: [color(0xFFF3B8), color(0xEDB82A)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(flapShade, start: tip,
                           end: CGPoint(x: body.maxX - fold / 2, y: body.minY + fold / 2), options: [])
    ctx.restoreGState()

    // The now-line.
    let nowY: CGFloat = 505
    ctx.setFillColor(color(0xFF3B30))
    ctx.fill(CGRect(x: 205, y: nowY - 5, width: 660, height: 10))
    ctx.fillEllipse(in: CGRect(x: 180, y: nowY - 24, width: 48, height: 48))

    // The pin that keeps it on top.
    let head = CGRect(x: 452, y: 812, width: 120, height: 120)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 10, height: -18), blur: 22, color: color(0x000000, 0.35))
    ctx.setFillColor(color(0xE0261B))
    ctx.fillEllipse(in: head)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: head)
    ctx.clip()
    let shine = CGGradient(colorsSpace: space, colors: [color(0xFF8A7A), color(0xE0261B), color(0xA3140C)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawRadialGradient(shine, startCenter: CGPoint(x: head.midX - 22, y: head.midY + 24), startRadius: 4,
                           endCenter: CGPoint(x: head.midX, y: head.midY), endRadius: 64, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    ctx.setFillColor(color(0xFFFFFF, 0.75))
    ctx.fillEllipse(in: CGRect(x: head.midX - 40, y: head.midY + 14, width: 30, height: 22))
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    drawIcon(in: context.cgContext, size: CGFloat(size))
    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
if CommandLine.arguments.count > 2 { // optional preview PNG
    try! png(size: 1024).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
print("Wrote Resources/AppIcon.icns")
