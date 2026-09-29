import AppKit
import StickyCalendarCore
import SwiftUI

/// A Markdown text box with the note's live preview, bound to a string: formatting shows
/// as you type, links open when clicked, checkboxes tick. Used for reminders' notes; read-only
/// when `isEditable` is false (links still work).
struct MarkdownField: NSViewRepresentable {
    @Binding var text: String
    var isEditable = true
    var placeholder = ""

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1, as in the note: hiding syntax relies on its glyph-generation delegate.
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
        textView.placeholder = placeholder
        textView.onFocusChange = { [weak coordinator = context.coordinator, weak textView] in
            if let textView { coordinator?.layout.refresh(textView) }
        }
        textView.onToggleTask = { [weak textView] mark, checked in
            guard let textView, textView.isEditable else { return }
            let replacement = checked ? " " : "x"
            if textView.shouldChangeText(in: mark, replacementString: replacement) {
                textView.replaceCharacters(in: mark, with: replacement)
                textView.didChangeText()
            }
        }
        textView.isEditable = isEditable
        textView.isSelectable = true // links need it, even read-only
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = NoteStyle.font
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.string = text
        context.coordinator.layout.refresh(textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NoteTextView else { return }
        textView.isEditable = isEditable
        if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
            context.coordinator.layout.refresh(textView, force: true)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let layout = LivePreviewLayout()

        init(text: Binding<String>) { _text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            layout.refresh(textView)
            text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            layout.refresh(textView)
        }
    }
}
