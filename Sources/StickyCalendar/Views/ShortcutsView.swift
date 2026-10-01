import StickyCalendarCore
import SwiftUI

/// The keyboard shortcuts cheat sheet (? in a sticky, or the menu bar icon's menu).
struct ShortcutsView: View {
    let settings: AppSettings
    let reminderSettings: ReminderSettings

    private struct Section: Identifiable {
        let title: String
        let rows: [(keys: String, action: String)]
        var id: String { title }
    }

    private var calendar: [Section] {
        [
            Section(title: "Calendar", rows: [
                ("← →", "Previous or next day"),
                ("↑ ↓", "Select the previous or next event (or scroll)"),
                ("Page Up / Down", "Scroll a screenful"),
                ("Return", "Edit the selected event"),
                ("⌫", "Delete the selected events"),
                ("Esc", "Deselect"),
                ("⌘- or ⇧-click", "Select several events"),
                ("⌘X  ⌘C  ⌘V", "Cut, copy, paste events"),
                ("⌘O", "Open Calendar on this day"),
                ("⌘M", "Compact: just what's on now or next"),
            ]),
            Section(title: "Every sticky", rows: [
                ("⌘Z  ⇧⌘Z", "Undo, redo"),
                ("⌃S", "Keep on top of other windows, or not"),
                ("⌘R", "Refresh"),
                ("⌘=  ⌘-  ⌘0", "Zoom in, out, reset"),
                ("⌘W", "Close a reminders or note sticky"),
                ("⌘,", "Settings"),
                ("?", "This list"),
            ]),
        ]
    }

    private var others: [Section] {
        [
            Section(title: "Reminders", rows: [
                ("⌘F", "Search all reminders"),
                ("⌘O", "Open \(reminderSettings.provider?.name ?? "the reminders app")"),
                ("Return", "Add the reminder typed (a date in it becomes its due date)"),
            ]),
            Section(title: "From any app", rows: [
                (settings.globalHotKey.symbol, "Show or hide the calendar sticky"),
                (reminderSettings.hotKey.symbol, "Show or hide the reminders"),
            ]),
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            column(calendar)
                .frame(width: 330, alignment: .leading)
            VStack(alignment: .leading, spacing: 18) {
                column(others)
                Text("Change the ones from any app in Settings → Shortcuts. Esc or ? closes this.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 280, alignment: .leading)
        }
        .padding(22)
        .fixedSize()
    }

    private func column(_ sections: [Section]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title).font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                        ForEach(section.rows, id: \.action) { row in
                            GridRow {
                                Text(row.keys)
                                    .font(.system(.callout, design: .rounded).weight(.medium))
                                    .fixedSize()
                                    .foregroundStyle(row.keys == "Off" ? .tertiary : .primary)
                                    .gridColumnAlignment(.trailing)
                                Text(row.action).font(.callout).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }
}
