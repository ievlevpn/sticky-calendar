# SwiftMath (vendored)

[SwiftMath](https://github.com/mgriebling/SwiftMath) 1.7.3 (`fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7`), MIT licensed
(`LICENSE`), trimmed and patched for Sticky Calendar:

- Only the Latin Modern math font is kept (`mathFonts.bundle`: GUST Font License, see
  `mathFonts.bundle/GUST-FONT-LICENSE.txt`); upstream ships fourteen (7 MB).
- Fonts are found through `SwiftMathFonts` (`Sources/SwiftMath/SwiftMathFonts.swift`)
  instead of SwiftPM's `Bundle.module`, whose accessor only looks at the .app's root —
  which code signing forbids — and at an absolute build path, so a shipped app would crash.
  `scripts/build-app.sh` copies the bundle into `Contents/Resources`.
  Changed lines are marked `Sticky Calendar:`.
- `Sources/SwiftMath/TypesetFormula.swift` (new) exposes typesetting and drawing, which
  upstream keeps internal.

To update: copy `Sources/SwiftMath/{MathRender,MathBundle}` from a new release over
`Sources/SwiftMath/`, and reapply the marked changes.
