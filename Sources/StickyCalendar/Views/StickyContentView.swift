import StickyCalendarCore
import SwiftUI

/// Root of the sticky window: header, all-day strip, timeline, optional note (or, compact,
/// just what's on next), or the Reminders tab (or, compact, one reminder at a time), plus
/// dialogs and error banner.
struct StickyContentView: View {
    let store: CalendarStore
    let settings: AppSettings
    let notepad: Notepad
    let noteEditor: NoteEditorController
    let reminderStore: ReminderStore
    let reminderSettings: ReminderSettings
    let onToggleReminders: () -> Void
    /// Opens or closes the note's own sticky (when the note has one).
    let onToggleNoteWindow: () -> Void
    /// Moves the note between under the timeline and its own sticky, keeping it open.
    let onMoveNote: (NotePlacement) -> Void
    let onChooseReminderPlacement: (ReminderPlacement) -> Void
    let onTogglePin: () -> Void
    let onToggleCompact: () -> Void
    /// The compact reminders' height, which changes with what they show.
    let onRemindersCompactHeight: (CGFloat) -> Void
    let onSettings: () -> Void

    @State private var contentHeight: CGFloat = 0
    /// Header plus the least timeline worth keeping when the note grows.
    private let reservedHeight: CGFloat = 32 + 140

    var body: some View {
        Group {
            if showsRemindersTab, settings.isCompact {
                RemindersCompactView(store: reminderStore, calendarStore: store, settings: reminderSettings,
                                     opacity: settings.opacity, header: header, onExpand: onToggleCompact,
                                     onHeightChange: onRemindersCompactHeight)
            } else {
                VStack(spacing: 0) {
                    header
                    if showsRemindersTab {
                        RemindersView(store: reminderStore, settings: reminderSettings, zoom: settings.zoom,
                                      onChoosePlacement: onChooseReminderPlacement)
                    } else if settings.isCompact, store.access == .granted {
                        UpNextRow(store: store, onExpand: onToggleCompact)
                    } else {
                        fullContent
                    }
                }
                .background(VisualEffectBackground().opacity(settings.opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        // Per-day notes follow the day being viewed.
        .onAppear { notepad.setDay(store.day) }
        .onChange(of: store.day) { _, day in notepad.setDay(day) }
        .overlay(alignment: .bottom) { ErrorBanner(store: store) }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { store.pendingDelete != nil }, set: { if !$0 { store.cancelPendingDelete() } }),
            titleVisibility: .visible,
            presenting: store.pendingDelete
        ) { item in
            if item.isRecurring {
                Button("Delete This Event Only", role: .destructive) { store.confirmDelete(item, span: .thisEvent) }
                Button("Delete All Future Events", role: .destructive) { store.confirmDelete(item, span: .futureEvents) }
            } else {
                Button("Delete", role: .destructive) { store.confirmDelete(item, span: .thisEvent) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            if !item.canUndoDelete { Text("This can't be undone.") }
        }
        .confirmationDialog(
            "Delete \(store.pendingGroupDelete?.count ?? 0) events?",
            isPresented: Binding(get: { store.pendingGroupDelete != nil },
                                 set: { if !$0 { store.cancelPendingGroupDelete() } }),
            titleVisibility: .visible,
            presenting: store.pendingGroupDelete
        ) { items in
            if items.contains(where: \.isRecurring) {
                Button("Delete These Events Only", role: .destructive) { store.confirmGroupDelete(items, span: .thisEvent) }
                Button("Also Delete Future Repeats", role: .destructive) {
                    store.confirmGroupDelete(items, span: .futureEvents)
                }
            } else {
                Button("Delete", role: .destructive) { store.confirmGroupDelete(items, span: .thisEvent) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { items in
            if items.allSatisfy({ !$0.canUndoDelete }) {
                Text("This can't be undone.")
            } else if items.contains(where: { !$0.canUndoDelete }) {
                Text("Undo won't bring back the repeating events or meetings.")
            }
        }
        .confirmationDialog(
            "This is a repeating event.",
            isPresented: Binding(get: { store.pendingEdit != nil }, set: { if !$0 { store.cancelPendingEdit() } }),
            titleVisibility: .visible,
            presenting: store.pendingEdit
        ) { edit in
            Button("Change This Event Only") { store.confirmEdit(edit, span: .thisEvent) }
            Button("Change All Future Events") { store.confirmEdit(edit, span: .futureEvents) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HeaderView(
            store: store, settings: settings, reminderSettings: reminderSettings,
            compactReminderCount: reminderStore.openItems.count,
            isNoteVisible: notepad.isVisible, onToggleNote: toggleNote, onToggleReminders: onToggleReminders,
            onRefresh: refresh, isRefreshing: showsRemindersTab && reminderStore.isLoading,
            onTogglePin: onTogglePin, onToggleCompact: onToggleCompact, onSettings: onSettings
        )
        .zIndex(1) // its menu's label hangs over the content below
    }

    /// Everything below the header when not compact.
    @ViewBuilder
    private var fullContent: some View {
        switch store.access {
        case .granted:
            AllDayStrip(store: store, zoom: settings.zoom)
            DayTimelineView(store: store, zoom: settings.zoom)
        case .notDetermined:
            Spacer()
            Text("Waiting for Calendar access…").foregroundStyle(.secondary)
            Spacer()
        case .denied:
            AccessDeniedView()
        }
        if notepad.placement == .pane, notepad.isVisible {
            NotePane(notepad: notepad, editor: noteEditor, zoom: settings.zoom, maxHeight: contentHeight - reservedHeight,
                     onDetach: { onMoveNote(.window) })
        }
    }

    private var showsRemindersTab: Bool {
        reminderSettings.placement == .tab && reminderSettings.isVisible
    }

    private func refresh() {
        if showsRemindersTab { Task { await reminderStore.refresh() } } else { store.refresh() }
    }

    private func toggleNote() {
        guard notepad.placement == .pane else { return onToggleNoteWindow() }
        if notepad.isVisible { noteEditor.resignFocus() } else { noteEditor.requestFocus() }
        notepad.setVisible(!notepad.isVisible)
    }

    private var deleteTitle: String {
        let title = store.pendingDelete?.title ?? ""
        return title.isEmpty ? "Delete this event?" : "Delete “\(title)”?"
    }
}
