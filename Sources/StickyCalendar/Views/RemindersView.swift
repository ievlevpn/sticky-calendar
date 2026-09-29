import StickyCalendarCore
import SwiftUI

/// The reminders: a Today / Lists switch, the sections, and a field to add one. Shared by
/// the reminders window and the calendar sticky's Reminders tab. Asks for Reminders access
/// the first time it appears.
struct RemindersView: View {
    let store: ReminderStore
    let settings: ReminderSettings
    let zoom: CGFloat
    /// The first-open question: stay a tab, or get their own window.
    let onChoosePlacement: (ReminderPlacement) -> Void

    @State private var newText = ""
    @State private var addListID: String?
    @State private var renamingID: String?
    @State private var renameText = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable { case add, rename }

    var body: some View {
        VStack(spacing: 0) {
            if !settings.isPlacementChosen {
                placementQuestion
            } else if !store.hasSource || settings.provider == nil {
                ReminderSourceChooser(store: store, settings: settings)
            } else {
                switch (store.access, settings.provider) {
                case (.granted, _):
                    modeBar
                    Divider()
                    list
                    addBar
                case (.notDetermined, .appleReminders?):
                    prompt("Your reminders appear here once Sticky Calendar may read them.",
                           button: "Allow Access to Reminders") { Task { await store.requestAccessIfNeeded() } }
                case (.denied, .appleReminders?):
                    prompt("Sticky Calendar isn't allowed to see your reminders.",
                           button: "Open Privacy Settings") { SystemLinks.openRemindersPrivacySettings() }
                case (_, let provider):
                    // A missing or rejected token, or a vault that can't be read: set it up again.
                    ReminderSourceChooser(store: store, settings: settings, initial: provider)
                }
            }
        }
        .task(id: settings.isPlacementChosen) {
            if settings.isPlacementChosen { await store.requestAccessIfNeeded() }
        }
        .overlay(alignment: .bottom) {
            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
                    .padding(.bottom, 40)
                    .onTapGesture { store.lastError = nil }
                    .task { try? await Task.sleep(for: .seconds(5)); store.lastError = nil }
            }
        }
    }

    // MARK: Parts

    private var placementQuestion: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where should reminders appear?").font(.headline)
            placementOption(.tab, icon: "rectangle.on.rectangle", title: "In this sticky",
                            detail: "The checklist button switches between your calendar and reminders.",
                            recommended: true)
            placementOption(.window, icon: "rectangle.split.2x1", title: "In their own sticky",
                            detail: "A second floating window next to this one, so you see both at once.",
                            recommended: false)
            Text("You can change this later in Settings → Reminders.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func placementOption(_ placement: ReminderPlacement, icon: String, title: String,
                                 detail: String, recommended: Bool) -> some View {
        Button { onChoosePlacement(placement) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Color.accentColor).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(title).font(.system(size: 12.5, weight: .semibold))
                        if recommended {
                            Text("Default").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                    }
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var modeBar: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(get: { settings.mode }, set: settings.setMode)) {
                Text("Today").tag(ReminderMode.today)
                Text("Lists").tag(ReminderMode.lists)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            Spacer(minLength: 0)
            Button { settings.setShowsCompleted(!settings.showsCompleted) } label: {
                Image(systemName: settings.showsCompleted ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .buttonStyle(.borderless)
            .help(settings.showsCompleted ? "Hide completed" : "Show completed today")
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private var list: some View {
        let sections = store.sections
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if sections.isEmpty {
                    Text(settings.mode == .today ? "Nothing due today." : "No reminders.")
                        .font(.system(size: 12 * zoom))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24 * zoom)
                }
                ForEach(sections) { section in
                    header(section)
                    ForEach(section.items) { item in row(item, in: section) }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func header(_ section: ReminderSection) -> some View {
        HStack(spacing: 6 * zoom) {
            if let color = section.color {
                Circle().fill(Color(rgba: color)).frame(width: 7 * zoom, height: 7 * zoom)
            }
            Text(section.title)
                .font(.system(size: 11 * zoom, weight: .bold))
                .foregroundStyle(section.kind == .overdue ? Color.red : Color.secondary)
            Spacer()
            Text("\(section.items.filter { !$0.isCompleted }.count)")
                .font(.system(size: 10 * zoom).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10 * zoom)
        .padding(.bottom, 3 * zoom)
    }

    private func row(_ item: ReminderItem, in section: ReminderSection) -> some View {
        let list = store.listInfo(id: item.listID)
        let color = Color(rgba: list?.color ?? .fallback)
        let writable = list?.isWritable ?? false
        return HStack(alignment: .firstTextBaseline, spacing: 7 * zoom) {
            Button { Task { await store.toggle(item) } } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13 * zoom))
                    .foregroundStyle(item.isCompleted ? color.opacity(0.6) : color)
            }
            .buttonStyle(.plain)
            .disabled(!writable)
            .help(item.isCompleted ? "Mark as not done" : "Mark as done")
            if renamingID == item.id {
                TextField("Title", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12 * zoom))
                    .focused($focus, equals: .rename)
                    .onSubmit { commitRename(item) }
                    .onExitCommand { renamingID = nil }
                    .onChange(of: focus) { _, now in if now != .rename { commitRename(item) } }
            } else {
                Text(item.title)
                    .font(.system(size: 12 * zoom))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { if writable { startRename(item) } }
            }
            if let due = dueLabel(item, in: section) {
                Text(due.text)
                    .font(.system(size: 10.5 * zoom).monospacedDigit())
                    .foregroundStyle(due.isLate ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3 * zoom)
        .contextMenu {
            Button("Rename") { startRename(item) }.disabled(!writable)
            Button(item.isCompleted ? "Mark as Not Done" : "Mark as Done") { Task { await store.toggle(item) } }.disabled(!writable)
            Divider()
            Button("Delete", role: .destructive) { Task { await store.delete(item) } }.disabled(!writable)
            Divider()
            Button("Open in \(settings.provider?.name ?? "Reminders")") {
                if let url = store.link(for: item) { NSWorkspace.shared.open(url) }
            }
        }
    }

    private var addBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
            TextField("New reminder", text: $newText)
                .textFieldStyle(.plain)
                .font(.system(size: 12 * zoom))
                .focused($focus, equals: .add)
                .onSubmit(add)
                .help("Type a reminder and press Return. A date in it becomes the due date: “Call Sam tomorrow 10am”.")
            if settings.mode == .lists, store.visibleLists.filter(\.isWritable).count > 1 {
                Menu {
                    ForEach(store.visibleLists.filter(\.isWritable)) { list in
                        Button(list.title) { addListID = list.id }
                    }
                } label: {
                    Text(store.listInfo(id: addListID ?? store.defaultWritableListID() ?? "")?.title ?? "List")
                        .font(.system(size: 10.5))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("List for new reminders")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func prompt(_ message: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checklist").font(.system(size: 26)).foregroundStyle(.secondary)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(button, action: action)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func add() {
        let listID = settings.mode == .lists ? addListID : nil
        let text = newText
        newText = ""
        focus = .add
        Task {
            // Put the text back if it couldn't be added, so nothing typed is lost.
            if await store.add(text, listID: listID) == nil, newText.isEmpty { newText = text }
        }
    }

    private func startRename(_ item: ReminderItem) {
        renameText = item.title
        renamingID = item.id
        focus = .rename
    }

    private func commitRename(_ item: ReminderItem) {
        guard renamingID == item.id else { return }
        renamingID = nil
        let title = renameText
        Task { await store.rename(item, to: title) }
    }

    /// The time for today's timed ones; the day for others ("Tomorrow", "Mon", "26 Sep");
    /// nothing for an untimed one in Today. Late when overdue (or past its time today).
    private func dueLabel(_ item: ReminderItem, in section: ReminderSection) -> (text: String, isLate: Bool)? {
        guard let due = item.due else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let isLate = !item.isCompleted && (item.dueHasTime ? due < now : due < calendar.startOfDay(for: now))
        let time = due.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(due) {
            return item.dueHasTime ? (time, isLate) : (section.kind == .today ? nil : ("Today", false))
        }
        let day: String
        if calendar.isDateInTomorrow(due) { day = "Tomorrow" }
        else if calendar.isDateInYesterday(due) { day = "Yesterday" }
        else if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: due).day, (0..<7).contains(days) {
            day = due.formatted(.dateTime.weekday(.abbreviated))
        } else {
            day = due.formatted(.dateTime.day().month(.abbreviated))
        }
        return (item.dueHasTime ? "\(day) \(time)" : day, isLate)
    }
}

/// The reminders window's header: its title, refresh, pin and settings.
struct RemindersHeader: View {
    let settings: ReminderSettings
    let isRefreshing: Bool
    let onTogglePin: () -> Void
    let onRefresh: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Reminders").font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer()
            if isRefreshing {
                ProgressView().controlSize(.small).frame(width: 16, height: 16)
            } else {
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh (⌘R)")
            }
            Button(action: onTogglePin) { Image(systemName: settings.isPinned ? "pin.fill" : "pin.slash") }
                .buttonStyle(.borderless)
                .help(settings.isPinned ? "Unpin: behave like a normal window (⌃S)" : "Pin: keep on top of other windows (⌃S)")
            Button(action: onSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings (⌘,)")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}
