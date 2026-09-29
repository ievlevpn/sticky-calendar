import StickyCalendarCore
import SwiftUI

/// A reminder's editor popover: title, due date (and optionally a time), importance and
/// notes. Changes are saved when it closes, however it closes; ⌘Z undoes them.
struct ReminderEditor: View {
    struct Result {
        let title: String
        let due: Date?
        let hasTime: Bool
        let priority: ReminderPriority
        let notes: String?
    }

    let item: ReminderItem
    let listTitle: String
    /// Obsidian's notes are shown but edited in Obsidian.
    let canEditNotes: Bool
    let onSave: (Result) -> Void
    let onDelete: () -> Void

    @State private var title: String
    @State private var hasDate: Bool
    @State private var hasTime: Bool
    @State private var date: Date
    @State private var priority: ReminderPriority
    @State private var notes: String
    @State private var isDeleting = false
    @Environment(\.dismiss) private var dismiss

    init(item: ReminderItem, listTitle: String, canEditNotes: Bool,
         onSave: @escaping (Result) -> Void, onDelete: @escaping () -> Void) {
        self.item = item
        self.listTitle = listTitle
        self.canEditNotes = canEditNotes
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: item.title)
        _hasDate = State(initialValue: item.due != nil)
        _hasTime = State(initialValue: item.due != nil && item.dueHasTime)
        _date = State(initialValue: item.due ?? Self.nextFullHour())
        _priority = State(initialValue: item.priority)
        _notes = State(initialValue: item.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.headline)
            if !listTitle.isEmpty {
                Text(listTitle).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Toggle("Date", isOn: $hasDate.animation())
                Spacer()
                if hasDate {
                    DatePicker("", selection: $date, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
            }
            if hasDate {
                Toggle("Time", isOn: $hasTime.animation())
            }
            HStack {
                Text("Importance").lineLimit(1).fixedSize()
                Spacer(minLength: 8)
                Picker("", selection: $priority) {
                    Text("None").tag(ReminderPriority.none)
                    Text("!").tag(ReminderPriority.low)
                    Text("!!").tag(ReminderPriority.medium)
                    Text("!!!").tag(ReminderPriority.high)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            Text("Notes").font(.caption).foregroundStyle(.secondary)
            if canEditNotes {
                TextEditor(text: $notes)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                    .frame(height: 80)
            } else {
                ScrollView {
                    Text(notes.isEmpty ? "No notes." : notes)
                        .font(.system(size: 12))
                        .foregroundStyle(notes.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 80)
                Text("Notes are the indented lines under the task; edit them in Obsidian.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            HStack {
                Button("Delete", role: .destructive) {
                    isDeleting = true
                    onDelete()
                    dismiss()
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 290)
        .onDisappear(perform: save)
    }

    private func save() {
        guard !isDeleting else { return }
        let due: Date? = hasDate ? (hasTime ? date : Calendar.current.startOfDay(for: date)) : nil
        onSave(Result(title: title, due: due, hasTime: hasDate && hasTime, priority: priority,
                      notes: canEditNotes ? notes : item.notes))
    }

    private static func nextFullHour() -> Date {
        let calendar = Calendar.current
        let hour = calendar.dateInterval(of: .hour, for: Date())?.start ?? Date()
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? Date()
    }
}
