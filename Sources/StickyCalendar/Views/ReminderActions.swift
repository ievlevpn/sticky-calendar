import AppKit
import StickyCalendarCore
import SwiftUI

/// A reminder's right-click menu, shared by the list and the compact row.
struct ReminderMenu: View {
    let item: ReminderItem
    let store: ReminderStore
    let settings: ReminderSettings
    let isWritable: Bool
    let onEdit: () -> Void

    var body: some View {
        Button("Edit…", action: onEdit).disabled(!isWritable)
        Button(item.isCompleted ? "Mark as Not Done" : "Mark as Done") { Task { await store.toggle(item) } }
            .disabled(!isWritable)
        Menu("Postpone") {
            ForEach(Postpone.allCases.filter { (store.source?.supportsTime ?? true) || !$0.isHours }, id: \.self) { option in
                Button(option.title) { Task { await store.postpone(item, option) } }
            }
        }
        .disabled(!isWritable || item.isCompleted)
        Divider()
        Button("Delete", role: .destructive) { Task { await store.delete(item) } }.disabled(!isWritable)
        Divider()
        Button("Open in \(settings.provider?.name ?? "Reminders")") {
            if let url = store.link(for: item) { NSWorkspace.shared.open(url) }
        }
    }
}

extension View {
    /// The reminder's editor in a popover; saves (or deletes) through the store.
    func reminderEditor(_ item: ReminderItem, store: ReminderStore, isPresented: Binding<Bool>,
                        arrowEdge: Edge) -> some View {
        popover(isPresented: isPresented, arrowEdge: arrowEdge) {
            ReminderEditor(item: item, listTitle: store.listInfo(id: item.listID)?.title ?? "",
                           canEditNotes: store.canEditNotes,
                           supportsTime: store.source?.supportsTime ?? true,
                           supportsPriority: store.source?.supportsPriority ?? true) { result in
                Task {
                    await store.edit(item, title: result.title, due: result.due, dueHasTime: result.hasTime,
                                     priority: result.priority, notes: result.notes)
                }
            } onDelete: {
                isPresented.wrappedValue = false
                Task { await store.delete(item) }
            }
        }
    }
}
