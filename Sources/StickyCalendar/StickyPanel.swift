import AppKit
import StickyCalendarCore
import SwiftUI

/// The floating sticky window: above other windows, on every Space and over full-screen
/// apps, never activates the app when clicked, remembers its frame.
@MainActor
final class StickyPanel: NSPanel, NSWindowDelegate {
    private static let autosaveName = "StickyPanel"
    private let store: CalendarStore
    private var keyMonitor: Any?

    init(store: CalendarStore, settings: AppSettings) {
        self.store = store
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 520),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false // dragging on the timeline edits events
        backgroundColor = .clear
        isOpaque = false
        minSize = NSSize(width: 220, height: 300)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }

        let hosting = NSHostingView(rootView: StickyContentView(store: store, settings: settings))
        hosting.sizingOptions = [] // let the user resize freely
        contentView = hosting
        delegate = self

        if !setFrameUsingName(Self.autosaveName) { placeTopRight() }
        setFrameAutosaveName(Self.autosaveName)
        installKeyMonitor()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { store.undoManager }

    /// Picks up changes made while we were in the background (e.g. access granted in Settings).
    func windowDidBecomeKey(_ notification: Notification) { store.reload() }

    private func placeTopRight() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 20, y: visible.maxY - frame.height - 20))
    }

    /// ⌫ deletes the selected event, ⌘Z / ⇧⌘Z undo and redo — unless a text field is editing.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.charactersIgnoringModifiers?.lowercased()
            let window = event.window.map(ObjectIdentifier.init)
            let handled = MainActor.assumeIsolated {
                self?.handleKey(keyCode: keyCode, flags: flags, key: key, window: window) ?? false
            }
            return handled ? nil : event
        }
    }

    private func handleKey(keyCode: UInt16, flags: NSEvent.ModifierFlags, key: String?, window: ObjectIdentifier?) -> Bool {
        guard window == ObjectIdentifier(self), !(firstResponder is NSTextView) else { return false }
        switch (keyCode, flags, key) {
        case (51, [], _), (117, [], _), (117, [.function], _): // delete, forward delete
            store.requestDeleteSelected()
        case (_, [.command], "z"):
            store.undoManager.undo()
        case (_, [.command, .shift], "z"):
            store.undoManager.redo()
        default:
            return false
        }
        return true
    }
}
