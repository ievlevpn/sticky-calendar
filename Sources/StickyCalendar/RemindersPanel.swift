import AppKit
import StickyCalendarCore
import SwiftUI

/// The reminders sticky (when reminders get their own window). Pinned by default,
/// independently of the calendar sticky; first placed to the calendar sticky's left.
@MainActor
final class RemindersPanel: FloatingPanel {
    private let store: ReminderStore
    private let settings: ReminderSettings
    private let appSettings: AppSettings
    private let onSettings: () -> Void
    private let onClose: () -> Void
    private var keyMonitor: Any?

    init(store: ReminderStore, settings: ReminderSettings, appSettings: AppSettings, beside neighbour: NSWindow?,
         onSettings: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.appSettings = appSettings
        self.onSettings = onSettings
        self.onClose = onClose
        super.init(autosaveName: "RemindersPanel", size: NSSize(width: 260, height: 420),
                   minSize: NSSize(width: 200, height: 200), isPinned: { settings.isPinned })
        setContent(RemindersWindowContent(
            store: store, settings: settings, appSettings: appSettings,
            onTogglePin: { [weak self] in self?.togglePinned() },
            onSettings: onSettings
        ), defaultPlacement: { panel in
            guard let neighbour else { return panel.placeTopRight() }
            panel.setFrameOrigin(NSPoint(x: neighbour.frame.minX - panel.frame.width - 12,
                                         y: neighbour.frame.maxY - panel.frame.height))
        })
        installKeyMonitor()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { store.undoManager }

    /// Picks up changes made elsewhere (e.g. in Reminders.app) while in the background.
    override func windowDidBecomeKey(_ notification: Notification) {
        super.windowDidBecomeKey(notification)
        Task { await store.reload() }
    }

    func togglePinned() {
        settings.setPinned(!settings.isPinned)
        applyPinned()
    }

    /// ⌘Z / ⇧⌘Z undo and redo (unless a text field is editing), ⌃S pins, ⌘W hides,
    /// ⌘, opens Settings, ⌘= / ⌘- / ⌘0 zoom.
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
        case ([.command], "z") where !(firstResponder is NSTextView): store.undoManager.undo()
        case ([.command, .shift], "z") where !(firstResponder is NSTextView): store.undoManager.redo()
        default: return false
        }
        return true
    }
}

struct RemindersWindowContent: View {
    let store: ReminderStore
    let settings: ReminderSettings
    let appSettings: AppSettings
    let onTogglePin: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RemindersHeader(settings: settings, onTogglePin: onTogglePin, onSettings: onSettings)
            RemindersView(store: store, settings: settings, zoom: appSettings.zoom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground().opacity(appSettings.opacity))
    }
}
