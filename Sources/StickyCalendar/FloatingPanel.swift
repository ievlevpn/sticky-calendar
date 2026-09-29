import AppKit
import SwiftUI

/// A sticky's window. Pinned: above other windows, on every Space and over full-screen
/// apps. Unpinned: an ordinary window. Never activates the app when clicked; remembers its
/// frame. Subclasses supply the content and their keys.
@MainActor
class FloatingPanel: NSPanel, NSWindowDelegate {
    private let autosaveName: String
    private let isPinned: () -> Bool

    init(autosaveName: String, size: NSSize, minSize: NSSize, isPinned: @escaping () -> Bool) {
        self.autosaveName = autosaveName
        self.isPinned = isPinned
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false // dragging inside edits things
        backgroundColor = .clear
        isOpaque = false
        self.minSize = minSize
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        delegate = self
        applyPinned()
    }

    /// Hosts `view` as the whole window, then restores the saved frame or places the window
    /// `placement` (top-right by default).
    func setContent<Content: View>(_ view: Content, defaultPlacement placement: ((FloatingPanel) -> Void)? = nil) {
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [] // let the user resize freely
        // Our header replaces the (transparent) title bar. Without this, SwiftUI treats the
        // title-bar strip as a safe area and extends scroll views up under the header,
        // where they draw over it and swallow clicks on its buttons.
        hosting.safeAreaRegions = []
        contentView = hosting
        if !setFrameUsingName(autosaveName) { (placement ?? { $0.placeTopRight() })(self) }
        setFrameAutosaveName(autosaveName)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// A click outside the text being edited ends editing, so the window's own keys (⌫,
    /// arrows, ⌘Z) act on its content again rather than on that text.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           let editor = firstResponder as? NSTextView,
           let hit = contentView?.superview?.hitTest(event.locationInWindow),
           !hit.isDescendant(of: editor.enclosingScrollView ?? editor) {
            makeFirstResponder(nil)
        }
        super.sendEvent(event)
    }

    /// An unpinned panel is raised explicitly, since clicking it doesn't activate the app.
    func windowDidBecomeKey(_ notification: Notification) {
        if !isPinned() { orderFrontRegardless() }
    }

    func applyPinned() {
        let pinned = isPinned()
        isFloatingPanel = pinned
        level = pinned ? .floating : .normal
        collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed]
    }

    /// Keeps the top edge where it is, as a window does when its content changes height.
    func resize(toHeight height: CGFloat, animate: Bool) {
        var rect = frame
        rect.origin.y += rect.height - height
        rect.size.height = height
        setFrame(rect, display: true, animate: animate)
    }

    func placeTopRight(inset: CGFloat = 20) {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: visible.maxX - frame.width - inset, y: visible.maxY - frame.height - 20))
    }
}
