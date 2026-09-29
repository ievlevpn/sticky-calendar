import StickyCalendarCore
import SwiftUI

/// Root of the sticky window: header, all-day strip, timeline, optional note (or, compact,
/// just what's on next), plus dialogs and error banner.
struct StickyContentView: View {
    let store: CalendarStore
    let settings: AppSettings
    let notepad: Notepad
    let noteEditor: NoteEditorController
    let onTogglePin: () -> Void
    let onToggleCompact: () -> Void
    let onSettings: () -> Void

    @State private var contentHeight: CGFloat = 0
    /// Header plus the least timeline worth keeping when the note grows.
    private let reservedHeight: CGFloat = 32 + 140

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                store: store, settings: settings,
                isNoteVisible: notepad.isVisible, onToggleNote: toggleNote,
                onTogglePin: onTogglePin, onToggleCompact: onToggleCompact, onSettings: onSettings
            )
            if settings.isCompact, store.access == .granted {
                UpNextRow(store: store, onExpand: onToggleCompact)
            } else {
                fullContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        // Per-day notes follow the day being viewed.
        .onAppear { notepad.setDay(store.day) }
        .onChange(of: store.day) { _, day in notepad.setDay(day) }
        .background(VisualEffectBackground().opacity(settings.opacity))
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
        if notepad.isVisible {
            NotePane(notepad: notepad, editor: noteEditor, zoom: settings.zoom, maxHeight: contentHeight - reservedHeight)
        }
    }

    private func toggleNote() {
        if notepad.isVisible { noteEditor.resignFocus() } else { noteEditor.requestFocus() }
        notepad.setVisible(!notepad.isVisible)
    }

    private var deleteTitle: String {
        let title = store.pendingDelete?.title ?? ""
        return title.isEmpty ? "Delete this event?" : "Delete “\(title)”?"
    }
}
