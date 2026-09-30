import AppKit
import StickyCalendarCore
import SwiftUI

/// The note in its own sticky (Settings → Note). Pinned by default, independently of the
/// calendar sticky; first placed to its left. Per-day notes still follow the calendar's day.
@MainActor
final class NotesPanel: FloatingPanel {
    private let notepad: Notepad
    private let appSettings: AppSettings
    let editor: NoteEditorController
    private let onSettings: () -> Void
    private let onClose: () -> Void
    private var keyMonitor: Any?

    init(notepad: Notepad, appSettings: AppSettings, beside neighbour: NSWindow?,
         onSettings: @escaping () -> Void, onClose: @escaping () -> Void, onAttach: @escaping () -> Void) {
        self.notepad = notepad
        self.appSettings = appSettings
        editor = NoteEditorController(notepad: notepad)
        self.onSettings = onSettings
        self.onClose = onClose
        super.init(autosaveName: "NotesPanel", size: NSSize(width: 280, height: 320),
                   minSize: NSSize(width: 200, height: 140), isPinned: { notepad.isWindowPinned })
        setContent(NoteWindowContent(
            notepad: notepad, editor: editor, appSettings: appSettings,
            onTogglePin: { [weak self] in self?.togglePinned() },
            onAttach: onAttach,
            onSettings: onSettings,
            onHide: onClose
        ), defaultPlacement: { panel in
            guard let neighbour else { return panel.placeTopRight() }
            panel.setFrameOrigin(NSPoint(x: neighbour.frame.minX - panel.frame.width - 12, y: neighbour.frame.minY))
        })
        fadeWhenIdle(following: appSettings)
        installKeyMonitor()
    }

    func togglePinned() {
        notepad.setWindowPinned(!notepad.isWindowPinned)
        applyPinned()
    }

    /// ⌘W hides, ⌘, opens Settings, ⌃S pins, ⌘= / ⌘- / ⌘0 zoom (the note handles ⌘Z itself).
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
            let key = event.charactersIgnoringModifiers?.lowercased()
            let window = event.window.map(ObjectIdentifier.init)
            let handled = MainActor.assumeIsolated {
                self?.handleKey(flags: flags, key: key, window: window) ?? false
            }
            return handled ? nil : event
        }
    }

    private func handleKey(flags: NSEvent.ModifierFlags, key: String?, window: ObjectIdentifier?) -> Bool {
        guard window == ObjectIdentifier(self) else { return false }
        switch (flags, key) {
        case ([.command], ","): onSettings()
        case ([.command], "w"): onClose()
        case ([.command], "="), ([.command], "+"), ([.command, .shift], "+"), ([.command, .shift], "="): appSettings.zoomIn()
        case ([.command], "-"): appSettings.zoomOut()
        case ([.command], "0"): appSettings.resetZoom()
        case ([.control], "s"): togglePinned()
        default: return false
        }
        return true
    }
}

struct NoteWindowContent: View {
    let notepad: Notepad
    let editor: NoteEditorController
    let appSettings: AppSettings
    let onTogglePin: () -> Void
    /// Puts the note back under the timeline.
    let onAttach: () -> Void
    let onSettings: () -> Void
    let onHide: () -> Void

    @State private var isMenuOpen = false
    @State private var width: CGFloat = 280

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                NoteTitle(notepad: notepad, size: 13).fadedWhileMenuOpen(isMenuOpen)
                Spacer(minLength: 0)
                UnfurlMenu(items: [
                    UnfurlItem(id: "clear", symbol: "eraser", name: "Clear the note (⌘Z undoes)", action: editor.clear),
                    UnfurlItem(id: "attach", symbol: "arrow.down.left.square", name: "Put back under the timeline",
                               action: onAttach),
                    UnfurlItem(id: "pin", symbol: notepad.isWindowPinned ? "pin.fill" : "pin.slash",
                               isActive: notepad.isWindowPinned, name: notepad.isWindowPinned ? "Unpin" : "Pin on top",
                               shortcut: "⌃S", action: onTogglePin),
                    UnfurlItem(id: "settings", symbol: "gearshape", name: "Settings", shortcut: "⌘,", action: onSettings),
                    UnfurlItem(id: "hide", symbol: "xmark", name: "Hide note", shortcut: "⌘W", action: onHide),
                ], availableWidth: width, isOpen: $isMenuOpen)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            .zIndex(1) // its menu's label hangs over the note
            NoteEditor(notepad: notepad, controller: editor, zoom: appSettings.zoom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StickyBackground(settings: appSettings))
    }
}
