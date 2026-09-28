import AppKit
import StickyCalendarCore
import SwiftUI

/// Quick editor for one event. Commits on close; Esc cancels.
struct EventEditPopover: View {
    let calendars: [CalendarInfo]
    /// Called exactly once when the popover goes away with the item as it was when the
    /// editor opened, and the edited item (nil if cancelled).
    let onFinish: (_ snapshot: EventItem, _ result: EventItem?) -> Void
    let onDelete: (() -> Void)?
    let onOpenInCalendar: (() -> Void)?

    @State private var item: EventItem
    /// Frozen at open; the view is rebuilt when the store reloads, but @State is not reset.
    @State private var snapshot: EventItem
    @State private var cancelled = false
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        item: EventItem,
        calendars: [CalendarInfo],
        onFinish: @escaping (_ snapshot: EventItem, _ result: EventItem?) -> Void,
        onDelete: (() -> Void)? = nil,
        onOpenInCalendar: (() -> Void)? = nil
    ) {
        _item = State(initialValue: item)
        _snapshot = State(initialValue: item)
        self.calendars = calendars
        self.onFinish = onFinish
        self.onDelete = onDelete
        self.onOpenInCalendar = onOpenInCalendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                TextField("New Event", text: $item.title)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .focused($titleFocused)
                    .onSubmit { dismiss() }
                HStack(spacing: 6) {
                    DatePicker("Start", selection: $item.start, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("–")
                    DatePicker("End", selection: $item.end, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                Picker("Calendar", selection: $item.calendarID) {
                    ForEach(calendars) { calendar in
                        Text(calendar.title).tag(calendar.id)
                    }
                }
                TextField("Location", text: optionalText($item.location))
                TextField("Notes", text: optionalText($item.notes), axis: .vertical)
                    .lineLimit(2...5)
            }
            .disabled(item.isReadOnly)

            HStack {
                if let onOpenInCalendar {
                    Button("Open in Calendar") {
                        dismiss()
                        onOpenInCalendar()
                    }
                }
                Spacer()
                if let onDelete, !item.isReadOnly {
                    Button("Delete", role: .destructive) {
                        cancelled = true
                        dismiss()
                        onDelete()
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 270)
        .onAppear {
            // The sticky never activates the app; typing in the popover needs it active,
            // or keystrokes go to the app in front.
            NSApp.activate()
            titleFocused = item.isNew
        }
        .onExitCommand {
            cancelled = true
            dismiss()
        }
        .onDisappear { onFinish(snapshot, cancelled ? nil : item) }
    }

    private func optionalText(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
