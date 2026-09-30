import AppKit
import StickyCalendarCore
import SwiftUI

/// The scratch note under the timeline: a bar (drag to resize, Clear) above the note. Text is the event-title size.
struct NotePane: View {
    let notepad: Notepad
    let editor: NoteEditorController
    let zoom: CGFloat
    /// The most the window can give the note while leaving the timeline usable.
    let maxHeight: CGFloat
    /// Moves the note into its own sticky.
    let onDetach: () -> Void

    @State private var dragStartHeight: CGFloat?

    var body: some View {
        let height = min(CGFloat(notepad.height), max(maxHeight, CGFloat(Notepad.minHeight)))
        VStack(spacing: 0) {
            bar(height: height)
            NoteEditor(notepad: notepad, controller: editor, zoom: zoom)
        }
        .frame(height: height)
    }

    private func bar(height: CGFloat) -> some View {
        HStack(spacing: 8) {
            NoteTitle(notepad: notepad, size: 10)
            Spacer(minLength: 8)
            Capsule().fill(.tertiary).frame(width: 28, height: 3)
            Spacer(minLength: 8)
            Button(action: onDetach) { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(.borderless)
                .focusable(false)
                .font(.system(size: 11))
                .help("Move the note into its own sticky")
            Button("Clear") { editor.clear() }
                .buttonStyle(.borderless)
                .focusable(false)
                .font(.system(size: 10))
                .disabled(notepad.text.isEmpty)
                .help("Clear the note (⌘Z to undo)")
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .contentShape(Rectangle())
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .onHover { inside in
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        // Global space: the bar moves as the note grows, which would skew a local translation.
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStartHeight ?? height
                dragStartHeight = start
                notepad.setHeight(Double(min(start - value.translation.height, maxHeight)))
            }
            .onEnded { _ in dragStartHeight = nil })
    }
}

/// "Note · Tue, 29 Sep" for per-day notes, else "Note"; shortens rather than crowding
/// what's next to it in a narrow window.
struct NoteTitle: View {
    let notepad: Notepad
    let size: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            title(.dateTime.weekday(.abbreviated).day().month(.abbreviated), prefix: true)
            title(.dateTime.day().month(.abbreviated), prefix: true)
            title(.dateTime.day().month(.abbreviated), prefix: false)
        }
    }

    private func title(_ format: Date.FormatStyle, prefix: Bool) -> some View {
        let day = notepad.day.formatted(format)
        return Text(!notepad.isPerDay ? "Note" : prefix ? "Note · \(day)" : day)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(size < 12 ? .secondary : .primary)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Lets SwiftUI buttons and the panel reach the note's text view: focus it once it's on
/// screen, and change the text undoably.
@MainActor
final class NoteEditorController {
    let notepad: Notepad
    weak var textView: NoteTextView? {
        didSet { focusIfRequested() }
    }
    private var focusRequested = false

    init(notepad: Notepad) { self.notepad = notepad }

    func requestFocus() {
        focusRequested = true
        focusIfRequested()
    }

    func resignFocus() {
        guard let textView, textView.window?.firstResponder === textView else { return }
        textView.window?.makeFirstResponder(nil)
    }

    /// Empties the note; ⌘Z brings the text back.
    func clear() {
        guard let textView else { return }
        replace(NSRange(location: 0, length: (textView.string as NSString).length), with: "")
        requestFocus()
    }

    /// Goes through the text view so the change lands in its undo history.
    func replace(_ range: NSRange, with string: String) {
        guard let textView else { return }
        textView.breakUndoCoalescing()
        if textView.shouldChangeText(in: range, replacementString: string) {
            textView.replaceCharacters(in: range, with: string)
            textView.didChangeText()
        }
    }

    private func focusIfRequested() {
        guard focusRequested, let textView else { return }
        focusRequested = false
        // The view may not be in the window yet during SwiftUI's update pass.
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
    }
}

/// The note editor with Obsidian-style live preview: styled Markdown whose syntax shows
/// only on the lines being edited.
struct NoteEditor: NSViewRepresentable {
    let notepad: Notepad
    let controller: NoteEditorController
    let zoom: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(notepad: notepad) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1: hiding characters relies on its glyph-generation delegate.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        layoutManager.delegate = context.coordinator.layout

        let textView = NoteTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.live = context.coordinator.layout
        textView.onFocusChange = { [weak coordinator = context.coordinator, weak textView] in
            if let textView { coordinator?.refresh(textView) }
        }
        textView.onToggleTask = { [weak controller] mark, checked in
            controller?.replace(mark, with: checked ? " " : "x")
        }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        NoteStyle.zoom = zoom
        textView.font = NoteStyle.font
        textView.textContainerInset = NSSize(width: 7, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false // keep Markdown's straight quotes
        textView.isAutomaticDashSubstitutionEnabled = false  // and "--"
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.string = notepad.text
        context.coordinator.refresh(textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NoteTextView else { return }
        if controller.textView !== textView { controller.textView = textView }
        if NoteStyle.zoom != zoom {
            NoteStyle.zoom = zoom
            textView.font = NoteStyle.font
            context.coordinator.refresh(textView, force: true)
        }
        if textView.string != notepad.text, !textView.hasMarkedText() {
            textView.string = notepad.text
            textView.undoManager?.removeAllActions() // its ranges refer to the old text
            context.coordinator.refresh(textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let notepad: Notepad
        let layout = LivePreviewLayout()

        init(notepad: Notepad) { self.notepad = notepad }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            refresh(textView)
            notepad.setText(textView.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            refresh(textView)
        }

        func refresh(_ textView: NSTextView, force: Bool = false) { layout.refresh(textView, force: force) }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            MarkdownLinks.open(link)
        }
    }
}

/// Applies a `LivePreview` through TextKit 1: hidden characters get null glyphs (hidden
/// line breaks, zero width, so a display-math block folds onto one line), each decorated
/// marker becomes a blank that `NoteTextView` draws into, and lines holding math grow to
/// fit it.
@MainActor
final class LivePreviewLayout: NSObject, @preconcurrency NSLayoutManagerDelegate {
    private(set) var preview = LivePreview(text: "", spans: [], selection: nil)
    /// Spans of the text last styled, reused while only the selection moves.
    private var styled: (text: String, spans: [MarkdownSpan])?

    /// Restyles after an edit and re-hides syntax for the lines now being edited.
    /// `force` redoes both after a zoom change, when neither the text nor the syntax moved.
    func refresh(_ textView: NSTextView, force: Bool = false) {
        // Restyling mid-composition would break input methods; the commit restyles.
        guard !textView.hasMarkedText() else { return }
        let text = textView.string
        if force || styled?.text != text {
            let spans = MarkdownStyler.spans(in: text)
            styled = (text, spans)
            NoteStyle.apply(spans, to: textView)
        }
        let editing = textView.window?.firstResponder === textView
        update(LivePreview(
            text: text, spans: styled?.spans ?? [],
            selection: editing ? textView.selectedRanges.map(\.rangeValue) : nil,
            canDraw: { MathRenderer.shared.formula($0, display: $1) != nil }
        ), in: textView, force: force)
    }
    /// Blank space above and below display math.
    static let displayMathPadding: CGFloat = 5

    /// How wide a decoration's blank is; display math takes the rest of its line.
    private func width(of decoration: LivePreview.Decoration, from x: CGFloat, in line: NSRect) -> CGFloat {
        let zoom = NoteStyle.zoom
        return switch decoration {
        case .bullet: 12 * zoom
        case .task: 17 * zoom
        case .quote: 9 * zoom
        case .math(let tex, let display, _):
            display ? max(line.maxX - x, 0) : (MathRenderer.shared.formula(tex, display: false)?.width ?? 0) + 2
        }
    }

    func update(_ newValue: LivePreview, in textView: NSTextView, force: Bool = false) {
        guard force || newValue != preview, let layoutManager = textView.layoutManager else { return }
        preview = newValue
        let all = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.invalidateGlyphs(forCharacterRange: all, changeInLength: 0, actualCharacterRange: nil)
        layoutManager.invalidateLayout(forCharacterRange: all, actualCharacterRange: nil)
        layoutManager.invalidateDisplay(forCharacterRange: all)
        textView.needsDisplay = true
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        var changed = false
        let text = (layoutManager.textStorage?.string ?? "") as NSString
        var props = (0..<glyphRange.length).map { i -> NSLayoutManager.GlyphProperty in
            let index = characterIndexes[i]
            if preview.hidden.contains(index) {
                changed = true
                // A null line break still breaks the line; a control character can be told not to.
                let isBreak = index < text.length && CharacterSet.newlines.contains(UnicodeScalar(text.character(at: index)) ?? " ")
                return isBreak ? .controlCharacter : .null
            }
            if preview.decorations[index] != nil { changed = true; return .controlCharacter }
            return properties[i]
        }
        guard changed else { return 0 }
        props.withUnsafeMutableBufferPointer { buffer in
            layoutManager.setGlyphs(glyphs, properties: buffer.baseAddress!, characterIndexes: characterIndexes,
                                    font: font, forGlyphRange: glyphRange)
        }
        return glyphRange.length
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        if preview.decorations[charIndex] != nil { return .whitespace }
        if preview.hidden.contains(charIndex) { return .zeroAdvancement } // a hidden line break
        return action
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        boundingBoxForControlGlyphAt glyphIndex: Int,
        for textContainer: NSTextContainer,
        proposedLineFragment proposedRect: NSRect,
        glyphPosition: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        let blank = preview.decorations[charIndex].map { width(of: $0, from: glyphPosition.x, in: proposedRect) } ?? 0
        return NSRect(x: glyphPosition.x, y: 0, width: blank, height: proposedRect.height)
    }

    /// Makes a line holding math tall enough for it: room above the baseline for the
    /// tallest formula's ascent and below it for the deepest descent.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        let characters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        for (index, decoration) in preview.decorations where NSLocationInRange(index, characters) {
            guard case .math(let tex, let display, _) = decoration,
                  let formula = MathRenderer.shared.formula(tex, display: display) else { continue }
            let padding = (display ? Self.displayMathPadding : 1) * NoteStyle.zoom
            ascent = max(ascent, formula.ascent + padding)
            descent = max(descent, formula.descent + padding)
        }
        guard ascent > 0 else { return false }
        let baseline = max(baselineOffset.pointee, ascent)
        let height = baseline + max(lineFragmentRect.pointee.height - baselineOffset.pointee, descent)
        baselineOffset.pointee = baseline
        lineFragmentRect.pointee.size.height = height
        lineFragmentUsedRect.pointee.size.height = height
        return true
    }
}

/// The note's text view: keeps its own undo history (separate from event edits), gives up
/// focus on Esc, shows a placeholder when empty, and draws live-preview decorations —
/// clicking a checkbox ticks it.
final class NoteTextView: NSTextView {
    weak var live: LivePreviewLayout?
    var placeholder = "Jot something down…"
    var onFocusChange: (() -> Void)?
    var onToggleTask: ((_ mark: NSRange, _ checked: Bool) -> Void)?
    private let noteUndoManager = UndoManager()

    override var undoManager: UndoManager? { noteUndoManager }

    /// Out of the key-view loop, so the window doesn't hand it focus on its own at launch
    /// (the timeline's keys would then type into the note). Clicking still focuses it.
    override var canBecomeKeyView: Bool { false }

    @objc func undo(_ sender: Any?) { noteUndoManager.undo() }
    @objc func redo(_ sender: Any?) { noteUndoManager.redo() }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): noteUndoManager.canUndo
        case #selector(redo(_:)): noteUndoManager.canRedo
        default: super.validateUserInterfaceItem(item)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        window?.makeFirstResponder(nil)
    }

    override func becomeFirstResponder() -> Bool {
        defer { onFocusChange?() }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { DispatchQueue.main.async { [weak self] in self?.onFocusChange?() } }
        return resigned
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, decoration) in live?.preview.decorations ?? [:] {
            if case .task(let checked, let mark) = decoration, decorationRect(at: index)?.contains(point) == true {
                onToggleTask?(mark, checked)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            let padding = textContainer?.lineFragmentPadding ?? 0
            NSAttributedString(string: placeholder, attributes: [
                .font: NoteStyle.font,
                .foregroundColor: NSColor.placeholderTextColor,
            ]).draw(at: NSPoint(x: textContainerInset.width + padding, y: textContainerInset.height))
        }
        for (index, decoration) in live?.preview.decorations ?? [:] {
            guard let rect = decorationRect(at: index), rect.intersects(dirtyRect) else { continue }
            draw(decoration, at: index, in: rect)
        }
    }

    /// The baseline of the line holding a character, in view coordinates.
    private func baseline(at index: Int) -> CGFloat? {
        guard let layoutManager else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return textContainerOrigin.y + line.minY + layoutManager.location(forGlyphAt: glyph).y
    }

    /// Where a decorated marker was laid out, in view coordinates.
    private func decorationRect(at index: Int) -> NSRect? {
        guard let layoutManager, let textContainer, index < (string as NSString).length else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        var rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.width > 0 else { return nil }
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return rect
    }

    private func draw(_ decoration: LivePreview.Decoration, at index: Int, in rect: NSRect) {
        let midY = rect.midY
        switch decoration {
        case .math(let tex, let display, _):
            guard let formula = MathRenderer.shared.formula(tex, display: display),
                  let context = NSGraphicsContext.current?.cgContext,
                  let baseline = baseline(at: index) else { return }
            let x = display ? max(rect.midX - formula.width / 2, rect.minX) : rect.minX + 1
            formula.draw(in: context, baselineOrigin: CGPoint(x: x, y: baseline), color: .labelColor)
        case .bullet:
            NSColor.secondaryLabelColor.setFill()
            let dot = 4 * NoteStyle.zoom
            NSBezierPath(ovalIn: NSRect(x: rect.minX + dot / 2, y: midY - dot / 2, width: dot, height: dot)).fill()
        case .quote:
            NSColor.tertiaryLabelColor.setFill()
            let bar = 2.5 * NoteStyle.zoom
            NSBezierPath(roundedRect: NSRect(x: rect.minX + 1, y: rect.minY, width: bar, height: rect.height),
                         xRadius: bar / 2, yRadius: bar / 2).fill()
        case .task(let checked, _):
            let name = checked ? "checkmark.square.fill" : "square"
            let config = NSImage.SymbolConfiguration(pointSize: NoteStyle.size, weight: .regular)
                .applying(.init(paletteColors: [checked ? .secondaryLabelColor : .controlAccentColor]))
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: checked ? "Done" : "To do")?
                .withSymbolConfiguration(config) else { return }
            let size = image.size
            image.draw(in: NSRect(x: rect.minX + 1, y: midY - size.height / 2, width: size.width, height: size.height))
        }
    }
}

/// Markdown styling at a single size; syntax that's showing is dimmed.
@MainActor
enum NoteStyle {
    /// The app's zoom (Settings → Zoom); every size in the note, math included, follows it.
    /// Set by `NoteEditor`, which restyles when it changes.
    static var zoom: CGFloat = 1
    /// Same as event titles on the timeline.
    static var size: CGFloat { 11 * zoom }
    static var font: NSFont { NSFont.systemFont(ofSize: size) }
    static var base: [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: NSColor.labelColor] }

    static func apply(_ spans: [MarkdownSpan], to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: storage.length))
        for span in spans where span.range.length > 0 {
            let range = span.range
            switch span.style {
            case .marker, .listMarker, .taskMarker, .quoteMarker:
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            case .heading, .bold:
                addTraits(.bold, to: storage, in: range)
            case .italic:
                addTraits(.italic, to: storage, in: range)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .done:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            case .quote:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                addTraits(.italic, to: storage, in: range)
            case .code:
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: .regular), range: range)
                storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: range)
            case .link(let url):
                storage.addAttribute(.link, value: url, range: range)
            case .tag:
                storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
            case .math(let display):
                // Source that won't typeset is flagged; its delimiters are dimmed like other syntax.
                let tex = MarkdownStyler.tex(of: span, in: storage.string) ?? ""
                let color = MathRenderer.shared.formula(tex, display: display) == nil ? NSColor.systemRed : .secondaryLabelColor
                storage.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
        storage.endEditing()
        textView.typingAttributes = base
    }

    private static func addTraits(_ traits: NSFontDescriptor.SymbolicTraits, to storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
            storage.addAttribute(.font, value: NSFont(descriptor: descriptor, size: font.pointSize) ?? font, range: subrange)
        }
    }
}
