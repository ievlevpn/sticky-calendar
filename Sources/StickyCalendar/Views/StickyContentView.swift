import StickyCalendarCore
import SwiftUI

/// Root of the sticky window: header, all-day strip, timeline, plus dialogs and error banner.
struct StickyContentView: View {
    let store: CalendarStore
    let settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(store: store)
            switch store.access {
            case .granted:
                AllDayStrip(store: store)
                DayTimelineView(store: store)
            case .notDetermined:
                Spacer()
                Text("Waiting for Calendar access…").foregroundStyle(.secondary)
                Spacer()
            case .denied:
                AccessDeniedView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground().opacity(settings.opacity))
        .overlay(alignment: .bottom) { ErrorBanner(store: store) }
        .ignoresSafeArea()
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

    private var deleteTitle: String {
        let title = store.pendingDelete?.title ?? ""
        return title.isEmpty ? "Delete this event?" : "Delete “\(title)”?"
    }
}
