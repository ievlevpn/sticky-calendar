import Foundation

/// Where the math fonts live. Upstream SwiftMath uses SwiftPM's `Bundle.module`, whose
/// generated accessor only looks at the .app's root (which code signing forbids) and at an
/// absolute build path — so a shipped app would crash. Instead: the app's
/// Contents/Resources/mathFonts.bundle, or, when running an unbundled development build,
/// the copy in the source tree. nil when neither exists; callers check `isAvailable`
/// before typesetting, since SwiftMath force-unwraps its fonts.
public enum SwiftMathFonts {
    public static let bundle: Bundle? = {
        if let url = Bundle.main.url(forResource: "mathFonts", withExtension: "bundle"), let bundle = Bundle(url: url) {
            return bundle
        }
        let source = URL(fileURLWithPath: #filePath) // Vendor/SwiftMath/Sources/SwiftMath/SwiftMathFonts.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("mathFonts.bundle")
        return Bundle(url: source)
    }()

    public static var isAvailable: Bool {
        bundle?.path(forResource: "latinmodern-math", ofType: "otf") != nil
    }
}
