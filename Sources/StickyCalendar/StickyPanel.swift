import AppKit
import StickyCalendarCore
import SwiftUI

/// The calendar sticky: timeline, note and (as a tab) reminders. Pinned by default
/// (⌃S or the header pin toggles it).
@MainActor
final class StickyPanel: FloatingPanel {
    private let store: CalendarStore
    private let settings: AppSettings
    private let notepad: Notepad
    private let noteEditor: NoteEditorController
    private let reminderStore: ReminderStore
    private let reminderSettings: ReminderSettings
    private let onSettings: () -> Void
    private var keyMonitor: Any?
    /// Events copied with ⌘C or ⌘X, and the pasteboard's change count when they were, so
    /// ⌘V pastes them only while nothing else has been copied since.
    private var copiedEvents: [EventItem] = []
    private var copiedChangeCount = -1

    init(store: CalendarStore, settings: AppSettings, notepad: Notepad,
         reminderStore: ReminderStore, reminderSettings: ReminderSettings,
         onToggleReminders: @escaping () -> Void, onToggleNoteWindow: @escaping () -> Void,
         onMoveNote: @escaping (NotePlacement) -> Void,
         onChooseReminderPlacement: @escaping (ReminderPlacement) -> Void,
         onSettings: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.notepad = notepad
        self.reminderStore = reminderStore
        self.reminderSettings = reminderSettings
        noteEditor = NoteEditorController(notepad: notepad)
        self.onSettings = onSettings
        super.init(autosaveName: "StickyPanel", size: NSSize(width: Self.defaultWidth, height: 560),
                   minSize: Self.minimumSize, isPinned: { settings.isPinned })
        setContent(StickyContentView(
            store: store,
            settings: settings,
            notepad: notepad,
            noteEditor: noteEditor,
            reminderStore: reminderStore,
            reminderSettings: reminderSettings,
            onToggleReminders: onToggleReminders,
            onToggleNoteWindow: onToggleNoteWindow,
            onMoveNote: onMoveNote,
            onChooseReminderPlacement: onChooseReminderPlacement,
            onTogglePin: { [weak self] in self?.togglePinned() },
            onToggleCompact: { [weak self] in self?.toggleCompact() },
            onRemindersCompactHeight: { [weak self] height in self?.setRemindersCompactHeight(height) },
            onSettings: onSettings
        ))
        widenOnceForTheFullHeader()
        // Compact at launch: the height to restore was saved when it was made compact.
        appliedCompact = isCompact
        if isCompact { applyCompactSize(animate: false) }
        followCompactChanges()
        fadeWhenIdle(following: settings)
        installKeyMonitor()
    }

    /// Showing the Reminders tab instead of the timeline.
    private var showsReminders: Bool {
        reminderSettings.placement == .tab && reminderSettings.isVisible
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        showsReminders ? reminderStore.undoManager : store.undoManager
    }

    /// Picks up changes made while we were in the background (e.g. access granted in Settings).
    override func windowDidBecomeKey(_ notification: Notification) {
        super.windowDidBecomeKey(notification)
        store.reload()
        if showsReminders { Task { await reminderStore.reload() } }
    }

    func togglePinned() {
        settings.setPinned(!settings.isPinned)
        applyPinned()
    }

    private static let minimumSize = NSSize(width: 220, height: 300)
    /// Wide enough for the full date and every header button, with room for longer names.
    private static let defaultWidth: CGFloat = 360

    /// Windows saved by earlier versions (280 wide) cut the header short: widen them once,
    /// keeping the right edge. A width chosen after that is kept.
    private func widenOnceForTheFullHeader() {
        let key = "didWidenForFullHeader"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard frame.width < Self.defaultWidth else { return }
        var rect = frame
        rect.origin.x = rect.maxX - Self.defaultWidth
        rect.size.width = Self.defaultWidth
        setFrame(rect, display: false)
    }
    /// Header plus the up-next line.
    private static let calendarCompactHeight: CGFloat = 32 + 40
    /// Reported by the compact reminders, whose height depends on what they show.
    private var remindersCompactHeight: CGFloat = 32 + 40
    /// Whether the window is currently sized as compact.
    private var appliedCompact = false

    private var isCompact: Bool { settings.isCompact }

    private var compactHeight: CGFloat {
        showsReminders ? remindersCompactHeight : Self.calendarCompactHeight
    }

    /// Collapses (the calendar to what's on next, reminders to one at a time), or expands
    /// back. Switching between the calendar and the Reminders tab keeps it.
    func toggleCompact() {
        settings.setCompact(!settings.isCompact)
    }

    /// Resizes on toggling compact, and on switching tabs while compact (the two differ in height).
    private func followCompactChanges() {
        withObservationTracking {
            _ = (isCompact, showsReminders)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyCompactState()
                self?.followCompactChanges()
            }
        }
    }

    private func applyCompactState() {
        let compact = isCompact
        if compact && !appliedCompact {
            settings.setExpandedHeight(Double(frame.height)) // to restore
            store.goToToday()
        }
        if compact {
            applyCompactSize(animate: true)
        } else if appliedCompact {
            minSize = Self.minimumSize
            maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            resize(toHeight: max(CGFloat(settings.expandedHeight ?? 520), Self.minimumSize.height), animate: true)
        }
        appliedCompact = compact
    }

    private func setRemindersCompactHeight(_ height: CGFloat) {
        guard height != remindersCompactHeight else { return }
        remindersCompactHeight = height
        if appliedCompact && showsReminders { applyCompactSize(animate: true) }
    }

    private func applyCompactSize(animate: Bool) {
        let height = compactHeight
        minSize = NSSize(width: Self.minimumSize.width, height: height)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: height)
        resize(toHeight: height, animate: animate)
    }

    /// Copies the selected events for ⌘V, and as text ("09:00–10:00 Standup") for other apps.
    /// False when nothing is selected.
    private func copySelectedEvents() -> Bool {
        let events = store.selectedEvents
        guard !events.isEmpty else { return false }
        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        let text = events.map { "\(time($0.start))–\(time($0.end)) \($0.title)" }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copiedEvents = events
        copiedChangeCount = pasteboard.changeCount
        return true
    }

    /// ⌘C / ⌘X / ⌘V copy, cut and paste the selected events,
    /// ⌫ deletes the selected event, ⌘Z / ⇧⌘Z undo and redo, ⌃S toggles pinning,
    /// ⌘O opens Calendar, ←/→ change day, ↑/↓ move the selection (or scroll), Page Up/Down
    /// scroll, Return edits the selection, Esc deselects —
    /// unless a text field is editing. ⌘, opens Settings, ⌘R refreshes, ⌘M toggles compact mode and
    /// ⌘= / ⌘- / ⌘0 zoom, even from the note.
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
        guard window == ObjectIdentifier(self) else { return false }
        // Arrow, page, keypad and forward-delete keys carry these flags even with no modifier held.
        let flags = flags.subtracting([.numericPad, .function])
        switch (flags, key) {
        case ([.command], ","):
            onSettings()
            return true
        case ([.command], "r"):
            if showsReminders { Task { await reminderStore.refresh() } } else { store.refresh() }
            return true
        case ([.command], "f") where showsReminders:
            reminderStore.requestSearch()
            return true
        case ([.command], "m"):
            toggleCompact()
            return true
        case ([.command], "="), ([.command], "+"), ([.command, .shift], "+"), ([.command, .shift], "="):
            settings.zoomIn()
            return true
        case ([.command], "-"):
            settings.zoomOut()
            return true
        case ([.command], "0"):
            settings.resetZoom()
            return true
        default:
            break
        }
        guard !(firstResponder is NSTextView) else { return false }
        // The Reminders tab has its own undo; the timeline's keys don't apply to it.
        if showsReminders {
            switch (flags, key) {
            case ([.command], "z"): reminderStore.undoManager.undo()
            case ([.command, .shift], "z"): reminderStore.undoManager.redo()
            case ([.control], "s"): togglePinned()
            case ([.command], "o"): SystemLinks.openReminderSource(reminderSettings)
            default: return false
            }
            return true
        }
        switch (keyCode, flags, key) {
        case (51, [], _), (117, [], _): // delete, forward delete
            store.requestDeleteSelected()
        case (123, [], _): // ←
            store.goToDay(offset: -1)
        case (124, [], _): // →
            store.goToDay(offset: 1)
        case (126, [], _): // ↑: previous block, or scroll up when nothing is selected
            if !store.selectAdjacent(-1) { store.scrollStep(.hour(-1)) }
        case (125, [], _): // ↓
            if !store.selectAdjacent(1) { store.scrollStep(.hour(1)) }
        case (116, [], _): // Page Up
            store.scrollStep(.page(-1))
        case (121, [], _): // Page Down
            store.scrollStep(.page(1))
        case (36, [], _), (76, [], _): // Return, keypad Enter
            guard store.selectedID != nil else { return false }
            store.requestEditSelected()
        case (53, [], _): // Esc: drop the selection; otherwise let Esc through
            return store.clearSelection()
        case (_, [.command], "c"):
            return copySelectedEvents()
        case (_, [.command], "x"):
            guard copySelectedEvents() else { return false }
            store.deleteSelectedForCut()
        case (_, [.command], "v"):
            guard NSPasteboard.general.changeCount == copiedChangeCount, !copiedEvents.isEmpty else { return false }
            store.paste(copiedEvents)
        case (_, [.command], "z"):
            store.undoManager.undo()
        case (_, [.command, .shift], "z"):
            store.undoManager.redo()
        case (_, [.control], "s"):
            togglePinned()
        case (_, [.command], "o"):
            CalendarJump.perform(day: store.day, settings: settings, store: store)
        default:
            return false
        }
        return true
    }
}
