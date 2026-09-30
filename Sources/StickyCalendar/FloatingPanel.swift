import AppKit
import StickyCalendarCore
import SwiftUI

/// A sticky's window. Pinned: above other windows, on every Space and over full-screen
/// apps. Unpinned: an ordinary window. Never activates the app when clicked; remembers its
/// frame; optionally fades when left alone (Settings → Appearance). Subclasses supply the
/// content and their keys.
@MainActor
class FloatingPanel: NSPanel, NSWindowDelegate {
    private let autosaveName: String
    private let isPinned: () -> Bool
    /// Set by `fadeWhenIdle(following:)`.
    private var fadeSettings: AppSettings?
    private var fadeTimer: Timer?
    private var isPointerInside = false

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
        // Wrapped, so the pointer entering and leaving can be tracked (for fading).
        let container = PointerTrackingView()
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        container.onPointer = { [weak self] inside in
            self?.isPointerInside = inside
            self?.wake()
        }
        contentView = container
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
        if event.type == .keyDown { wake() } // typing with the pointer elsewhere
        super.sendEvent(event)
    }

    /// An unpinned panel is raised explicitly, since clicking it doesn't activate the app.
    func windowDidBecomeKey(_ notification: Notification) {
        if !isPinned() { orderFrontRegardless() }
        wake()
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        wake()
    }

    // MARK: Fading when idle

    /// Fades after `settings.idleFadeDelay` seconds without the pointer over the window or
    /// typing in it, by `settings.idleFadeAmount`; back at once when the pointer returns.
    func fadeWhenIdle(following settings: AppSettings) {
        fadeSettings = settings
        isPointerInside = frame.contains(NSEvent.mouseLocation)
        followFadeSettings()
        wake()
    }

    private func followFadeSettings() {
        guard let settings = fadeSettings else { return }
        withObservationTracking {
            _ = (settings.fadesWhenIdle, settings.idleFadeDelay, settings.idleFadeAmount)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.wake()
                self?.followFadeSettings()
            }
        }
    }

    /// Fully visible again; then, when fading is on and the pointer isn't over it, counts down.
    private func wake() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        if alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                animator().alphaValue = 1
            }
        }
        guard let settings = fadeSettings, settings.fadesWhenIdle, !isPointerInside else { return }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: settings.idleFadeDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fade() }
        }
    }

    private func fade() {
        guard let settings = fadeSettings, settings.fadesWhenIdle,
              !frame.contains(NSEvent.mouseLocation) else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.5
            animator().alphaValue = settings.idleAlpha
        }
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

/// The window's content view: tells when the pointer enters or leaves it, even while the
/// app is in the background.
private final class PointerTrackingView: NSView {
    var onPointer: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseEntered(with event: NSEvent) { onPointer?(true) }
    override func mouseExited(with event: NSEvent) { onPointer?(false) }
}
