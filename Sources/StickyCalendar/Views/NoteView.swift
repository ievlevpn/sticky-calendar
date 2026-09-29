import AppKit
import StickyCalendarCore
import SwiftUI

/// The scratch note under the timeline: a bar (drag to resize, Clear) above the note. Text is the event-title size.
struct NotePane: View {
    let notepad: Notepad
    let editor: NoteEditorController
    /// The most the window can give the note while leaving the timeline usable.
    let maxHeight: CGFloat

    @State private var dragStartHeight: CGFloat?

    var body: some View {
        let height = min(CGFloat(notepad.height), max(maxHeight, CGFloat(Notepad.minHeight)))
        VStack(spacing: 0) {
            bar(height: height)
            NoteEditor(notepad: notepad, controller: editor)
        }
        .frame(height: height)
    }

    private func bar(height: CGFloat) -> some View {
        HStack(spacing: 8) {
            Text("Note")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") { editor.clear() }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .disabled(notepad.text.isEmpty)
                .help("Clear the note (⌘Z to undo)")
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .overlay { Capsule().fill(.tertiary).frame(width: 28, height: 3) }
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
        /// Spans of the text last styled, reused while only the selection moves.
        private var styled: (text: String, spans: [MarkdownSpan])?

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

        /// Restyles after an edit and re-hides syntax for the lines now being edited.
        func refresh(_ textView: NSTextView) {
            // Restyling mid-composition would break input methods; the commit restyles.
            guard !textView.hasMarkedText() else { return }
            let text = textView.string
            if styled?.text != text {
                let spans = MarkdownStyler.spans(in: text)
                styled = (text, spans)
                NoteStyle.apply(spans, to: textView)
            }
            let editing = textView.window?.firstResponder === textView
            layout.update(LivePreview(
                text: text, spans: styled?.spans ?? [],
                selection: editing ? textView.selectedRanges.map(\.rangeValue) : nil
            ), in: textView)
        }
    }
}

/// Applies a `LivePreview` through TextKit 1: hidden characters get null glyphs, and each
/// decorated marker becomes a fixed-width blank that `NoteTextView` draws into.
@MainActor
final class LivePreviewLayout: NSObject, @preconcurrency NSLayoutManagerDelegate {
    private(set) var preview = LivePreview(text: "", spans: [], selection: nil)

    static func width(of decoration: LivePreview.Decoration) -> CGFloat {
        switch decoration {
        case .bullet: 12
        case .task: 17
        case .quote: 9
        }
    }

    func update(_ newValue: LivePreview, in textView: NSTextView) {
        guard newValue != preview, let layoutManager = textView.layoutManager else { return }
        preview = newValue
        let all = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.invalidateGlyphs(forCharacterRange: all, changeInLength: 0, actualCharacterRange: nil)
        layoutManager.invalidateLayout(forCharacterRange: all, actualCharacterRange: nil)
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
        var props = (0..<glyphRange.length).map { i -> NSLayoutManager.GlyphProperty in
            let index = characterIndexes[i]
            if preview.hidden.contains(index) { changed = true; return .null }
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
        preview.decorations[charIndex] != nil ? .whitespace : action
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        boundingBoxForControlGlyphAt glyphIndex: Int,
        for textContainer: NSTextContainer,
        proposedLineFragment proposedRect: NSRect,
        glyphPosition: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        let width = preview.decorations[charIndex].map(Self.width(of:)) ?? 0
        return NSRect(x: glyphPosition.x, y: 0, width: width, height: proposedRect.height)
    }
}

/// The note's text view: keeps its own undo history (separate from event edits), gives up
/// focus on Esc, shows a placeholder when empty, and draws live-preview decorations —
/// clicking a checkbox ticks it.
final class NoteTextView: NSTextView {
    weak var live: LivePreviewLayout?
    var onFocusChange: (() -> Void)?
    var onToggleTask: ((_ mark: NSRange, _ checked: Bool) -> Void)?
    private let noteUndoManager = UndoManager()

    override var undoManager: UndoManager? { noteUndoManager }

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
            NSAttributedString(string: "Jot something down — Markdown works", attributes: [
                .font: NoteStyle.font,
                .foregroundColor: NSColor.placeholderTextColor,
            ]).draw(at: NSPoint(x: textContainerInset.width + padding, y: textContainerInset.height))
        }
        for (index, decoration) in live?.preview.decorations ?? [:] {
            guard let rect = decorationRect(at: index), rect.intersects(dirtyRect) else { continue }
            draw(decoration, in: rect)
        }
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

    private func draw(_ decoration: LivePreview.Decoration, in rect: NSRect) {
        let midY = rect.midY
        switch decoration {
        case .bullet:
            NSColor.secondaryLabelColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 2, y: midY - 2, width: 4, height: 4)).fill()
        case .quote:
            NSColor.tertiaryLabelColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX + 1, y: rect.minY, width: 2.5, height: rect.height),
                         xRadius: 1.25, yRadius: 1.25).fill()
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
    /// Same as event titles on the timeline.
    static let size: CGFloat = 11
    static let font = NSFont.systemFont(ofSize: size)
    static let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]

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
