import AppKit
import StickyCalendarCore
import SwiftUI

/// The sticky window. Pinned (default): above other windows, on every Space and over
/// full-screen apps. Unpinned (⌃S or the header pin): an ordinary window. Never activates
/// the app when clicked; remembers its frame.
@MainActor
final class StickyPanel: NSPanel, NSWindowDelegate {
    private static let autosaveName = "StickyPanel"
    private let store: CalendarStore
    private let settings: AppSettings
    private var keyMonitor: Any?

    init(store: CalendarStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 520),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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

        applyPinned()
        let hosting = NSHostingView(rootView: StickyContentView(
            store: store,
            settings: settings,
            onTogglePin: { [weak self] in self?.togglePinned() }
        ))
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
    /// An unpinned panel is raised explicitly, since clicking it doesn't activate the app.
    func windowDidBecomeKey(_ notification: Notification) {
        store.reload()
        if !settings.isPinned { orderFrontRegardless() }
    }

    func togglePinned() {
        settings.setPinned(!settings.isPinned)
        applyPinned()
    }

    private func applyPinned() {
        isFloatingPanel = settings.isPinned
        level = settings.isPinned ? .floating : .normal
        collectionBehavior = settings.isPinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed]
    }

    private func placeTopRight() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 20, y: visible.maxY - frame.height - 20))
    }

    /// ⌫ deletes the selected event, ⌘Z / ⇧⌘Z undo and redo, ⌃S toggles pinning —
    /// unless a text field is editing.
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
        case (_, [.control], "s"):
            togglePinned()
        default:
            return false
        }
        return true
    }
}
