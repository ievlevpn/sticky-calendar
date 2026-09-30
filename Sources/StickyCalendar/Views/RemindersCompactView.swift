import StickyCalendarCore
import SwiftUI

/// The Reminders tab in compact mode (design 3c): the header, then one reminder at a time.
/// Scroll over the reminder, or use the arrows that appear on hover, to flip through them;
/// tick it off and the next slides in. While an event is on, it sits above the reminder as
/// in compact calendar (design 3d). Clicking the row expands the tab again.
struct RemindersCompactView<Header: View>: View {
    let store: ReminderStore
    let calendarStore: CalendarStore
    let settings: ReminderSettings
    let appSettings: AppSettings
    let header: Header
    let onExpand: () -> Void
    /// The window's height for what's showing: header, event if any, reminder.
    let onHeightChange: (CGFloat) -> Void

    /// The reminder showing; nil to show the one at `lastIndex`.
    @State private var currentID: String?
    /// Where the reminder showing was, so ticking it off shows the one that came after it.
    @State private var lastIndex = 0
    @State private var isHovering = false

    private let rowHeight: CGFloat = 40
    private let headerHeight: CGFloat = 32

    var body: some View {
        // Every 15 s, so the event row appears when it starts and goes when it ends.
        SwiftUI.TimelineView(.periodic(from: .now, by: 15)) { context in
            let showsEvent = hasOngoingEvent(at: context.date)
            let items = isReady ? store.openItems : []
            let height = headerHeight + (showsEvent ? rowHeight : 0) + rowHeight
            VStack(spacing: 0) {
                header
                if showsEvent {
                    UpNextRow(store: calendarStore, onExpand: onExpand)
                        .frame(height: rowHeight)
                        .overlay(alignment: .bottom) { Divider() }
                }
                reminderRow(items)
                Spacer(minLength: 0)
            }
            .background(StickyBackground(settings: appSettings))
            .onChange(of: height, initial: true) { _, height in onHeightChange(height) }
        }
        .task(id: settings.isPlacementChosen) {
            if settings.isPlacementChosen { await store.requestAccessIfNeeded() }
        }
    }

    /// Reminders can be listed: placed, with a source that lets us read them.
    private var isReady: Bool {
        settings.isPlacementChosen && store.hasSource && settings.provider != nil && store.access == .granted
    }

    private func hasOngoingEvent(at now: Date) -> Bool {
        guard calendarStore.access == .granted, calendarStore.isViewingToday else { return false }
        return UpNext.pick(from: calendarStore.timedEvents, now: now)?.isOngoing ?? false
    }

    // MARK: The reminder

    private func currentIndex(_ items: [ReminderItem]) -> Int? {
        guard !items.isEmpty else { return nil }
        if let currentID, let index = items.firstIndex(where: { $0.id == currentID }) { return index }
        return min(lastIndex, items.count - 1)
    }

    private func show(_ index: Int, of items: [ReminderItem]) {
        let index = min(max(index, 0), items.count - 1)
        guard index >= 0 else { return }
        currentID = items[index].id
        lastIndex = index
    }

    private func reminderRow(_ items: [ReminderItem]) -> some View {
        let index = currentIndex(items)
        return HStack(spacing: 10) {
            if let index {
                reminder(items[index])
                Spacer(minLength: 0)
                if isHovering && items.count > 1 {
                    arrows(index: index, of: items)
                }
            } else {
                placeholder
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onExpand)
        .onHover { isHovering = $0 }
        .overlay(ScrollWheelCatcher { steps in
            if let index { withAnimation(.easeOut(duration: 0.15)) { show(index + steps, of: items) } }
        })
        .help("Scroll to flip through reminders. Click to expand (⌘M).")
    }

    private func reminder(_ item: ReminderItem) -> some View {
        let list = store.listInfo(id: item.listID)
        let color = Color(rgba: list?.color ?? .fallback)
        let due = dueText(item)
        return HStack(spacing: 10) {
            Button {
                currentID = nil // the next one takes its place
                Task { await store.toggle(item) }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(color)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(!(list?.isWritable ?? false))
            .help("Mark as done")
            VStack(alignment: .leading, spacing: 1) {
                (item.priority == .none ? Text("") : Text(item.priority.marks + " ").foregroundColor(.orange))
                    + Text(item.title)
                Text([due?.text, list?.title].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(due?.isLate ?? false ? Color.red : Color.secondary)
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
        }
        .id(item.id)
        .transition(.opacity)
    }

    private func arrows(index: Int, of items: [ReminderItem]) -> some View {
        HStack(spacing: 2) {
            arrow("chevron.up", help: "Previous reminder", enabled: index > 0) { show(index - 1, of: items) }
            arrow("chevron.down", help: "Next reminder", enabled: index < items.count - 1) { show(index + 1, of: items) }
        }
    }

    private func arrow(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15), action) } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(enabled ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.5))
        .disabled(!enabled)
        .help(help)
    }

    @ViewBuilder
    private var placeholder: some View {
        if !isReady {
            Text("Set up reminders").font(.system(size: 12)).foregroundStyle(.secondary)
        } else if store.isLoading && store.items.isEmpty {
            Text("Loading…").font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(.green)
            Text(settings.mode == .today ? "All done for today" : "No reminders")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    /// "Due 17:00", "Overdue · 14:00", "Today", "Tomorrow", "Mon", "26 Sep"; late in red.
    private func dueText(_ item: ReminderItem) -> (text: String, isLate: Bool)? {
        guard let due = item.due else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let time = due.formatted(date: .omitted, time: .shortened)
        let isLate = item.dueHasTime ? due < now : due < calendar.startOfDay(for: now)
        if calendar.isDateInToday(due) {
            guard item.dueHasTime else { return ("Today", false) }
            return isLate ? ("Overdue · \(time)", true) : ("Due \(time)", false)
        }
        let day: String
        if calendar.isDateInTomorrow(due) { day = "Tomorrow" }
        else if calendar.isDateInYesterday(due) { day = "Yesterday" }
        else if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: due).day,
                (0..<7).contains(days) {
            day = due.formatted(.dateTime.weekday(.abbreviated))
        } else {
            day = due.formatted(.dateTime.day().month(.abbreviated))
        }
        return (isLate ? "Overdue · \(day)" : day, isLate)
    }
}
