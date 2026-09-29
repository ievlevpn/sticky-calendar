import Foundation
import Observation

/// The single owner of reminder state for the UI: loads reminders, arranges them into
/// Today or list sections, and makes every change (undoably).
@MainActor
@Observable
public final class ReminderStore {
    public private(set) var access: CalendarAccess = .notDetermined
    public private(set) var lists: [ReminderListInfo] = []
    public private(set) var items: [ReminderItem] = []
    public var lastError: String?

    @ObservationIgnored public let undoManager = UndoManager()
    @ObservationIgnored private let source: ReminderSource
    @ObservationIgnored private let settings: ReminderSettings
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    /// Ticked here since the last day change: they stay in view, struck through, so a
    /// mis-click can be seen and undone.
    private var recentlyCompleted: Set<String> = []
    /// Bumped on every reload; a slower, older fetch must not overwrite a newer one.
    @ObservationIgnored private var generation = 0

    public init(source: ReminderSource, settings: ReminderSettings,
                calendar: Calendar = .autoupdatingCurrent, now: @escaping () -> Date = Date.init) {
        self.source = source
        self.settings = settings
        self.calendar = calendar
        self.now = now
        access = source.currentAccess()
        source.onChange = { [weak self] in self?.reloadSoon() }
    }

    // MARK: Loading

    /// Asks for access the first time the reminders view is shown, not at launch.
    public func requestAccessIfNeeded() async {
        if source.currentAccess() == .notDetermined { _ = await source.requestAccess() }
        await reload()
    }

    public func reload() async {
        access = source.currentAccess()
        guard access == .granted else {
            lists = []
            items = []
            return
        }
        generation += 1
        let mine = generation
        let startOfToday = calendar.startOfDay(for: now())
        let fetched = await source.reminders(completedSince: startOfToday)
        guard mine == generation else { return }
        lists = source.lists()
        items = fetched
    }

    private func reloadSoon() {
        Task { await reload() }
    }

    /// A new day: yesterday's ticks no longer need to linger.
    public func handleDayChange() {
        recentlyCompleted = []
        reloadSoon()
    }

    // MARK: Sections

    public var visibleLists: [ReminderListInfo] {
        lists.filter { !settings.hiddenListIDs.contains($0.id) }
    }

    public func listInfo(id: String) -> ReminderListInfo? { lists.first { $0.id == id } }

    /// The sections for the current mode.
    public var sections: [ReminderSection] {
        settings.mode == .today ? todaySections : listSections
    }

    /// Overdue (due before today), then due today; ticked ones last.
    public var todaySections: [ReminderSection] {
        let startOfToday = calendar.startOfDay(for: now())
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        let shown = shownItems
        let overdue = shown.filter { !$0.isCompleted && ($0.due.map { $0 < startOfToday } ?? false) }
        let today = shown.filter { item in
            guard let due = item.due else { return false }
            return due >= startOfToday && due < startOfTomorrow
                // Ticked overdue ones stay in view here rather than vanishing from Overdue.
                || item.isCompleted && due < startOfToday
        }
        return [
            ReminderSection(id: "overdue", title: "Overdue", kind: .overdue, color: nil, items: sorted(overdue)),
            ReminderSection(id: "today", title: "Today", kind: .today, color: nil, items: sorted(today)),
        ].filter { !$0.items.isEmpty }
    }

    /// Each visible list with its reminders, in the lists' order; empty lists left out.
    public var listSections: [ReminderSection] {
        let shown = shownItems
        return visibleLists.compactMap { list in
            let items = shown.filter { $0.listID == list.id }
            guard !items.isEmpty else { return nil }
            return ReminderSection(id: list.id, title: list.title, kind: .list, color: list.color, items: sorted(items))
        }
    }

    /// Reminders in visible lists: incomplete ones, and completed ones when asked for or
    /// ticked just now.
    private var shownItems: [ReminderItem] {
        let hidden = settings.hiddenListIDs
        return items.filter { item in
            !hidden.contains(item.listID)
                && (!item.isCompleted || settings.showsCompleted || recentlyCompleted.contains(item.id))
        }
    }

    /// Open before done; then by due date (undated last), a timed one before an untimed
    /// one on the same day, then by title.
    private func sorted(_ items: [ReminderItem]) -> [ReminderItem] {
        items.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            switch (a.due, b.due) {
            case (nil, nil): break
            case (nil, _): return false
            case (_, nil): return true
            case let (da?, db?):
                let dayA = calendar.startOfDay(for: da), dayB = calendar.startOfDay(for: db)
                if dayA != dayB { return dayA < dayB }
                if a.dueHasTime != b.dueHasTime { return a.dueHasTime }
                if a.dueHasTime, da != db { return da < db }
            }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    // MARK: Changes

    /// Ticks or unticks.
    public func toggle(_ item: ReminderItem) {
        var changed = current(item)
        changed.isCompleted.toggle()
        changed.completionDate = changed.isCompleted ? now() : nil
        if changed.isCompleted { recentlyCompleted.insert(item.id) }
        save(changed, undo: current(item), actionName: changed.isCompleted ? "Complete Reminder" : "Uncomplete Reminder")
    }

    public func rename(_ item: ReminderItem, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = current(item)
        guard !trimmed.isEmpty, trimmed != original.title else { return }
        var changed = original
        changed.title = trimmed
        save(changed, undo: original, actionName: "Rename Reminder")
    }

    /// Adds a reminder from typed text (a date in it becomes the due date). In Today mode
    /// an undated one is due today. Goes to `listID`, or the default list.
    @discardableResult
    public func add(_ text: String, listID: String? = nil) -> ReminderItem? {
        var input = ReminderInput.parse(text)
        guard !input.title.isEmpty else { return nil }
        if input.due == nil, settings.mode == .today {
            input.due = calendar.startOfDay(for: now())
        }
        guard let list = listID ?? defaultWritableListID() else {
            lastError = "There's no reminders list to add to."
            return nil
        }
        return insert(ReminderItem(title: input.title, listID: list, due: input.due, dueHasTime: input.dueHasTime))
    }

    public func delete(_ item: ReminderItem) {
        let target = current(item)
        do {
            try source.remove(target)
            undoManager.registerUndo(withTarget: self) { store in
                MainActor.assumeIsolated { _ = store.insert(target) }
            }
            undoManager.setActionName("Delete Reminder")
            items.removeAll { $0.id == target.id }
            reloadSoon()
        } catch {
            fail(error)
        }
    }

    /// The list new reminders go to: the system default if it's visible and writable,
    /// else the first visible writable list.
    public func defaultWritableListID() -> String? {
        let writable = visibleLists.filter(\.isWritable)
        if let id = source.defaultListID(), writable.contains(where: { $0.id == id }) { return id }
        return writable.first?.id
    }

    /// Saves as new (also restores a deleted one, which gets a new identifier).
    private func insert(_ item: ReminderItem) -> ReminderItem? {
        var fresh = item
        fresh.id = ""
        do {
            let saved = try source.save(fresh)
            undoManager.registerUndo(withTarget: self) { store in
                MainActor.assumeIsolated { store.delete(saved) }
            }
            undoManager.setActionName("New Reminder")
            items.append(saved)
            reloadSoon()
            return saved
        } catch {
            fail(error)
            return nil
        }
    }

    private func save(_ changed: ReminderItem, undo original: ReminderItem, actionName: String) {
        do {
            let saved = try source.save(changed)
            undoManager.registerUndo(withTarget: self) { store in
                MainActor.assumeIsolated {
                    if original.isCompleted != saved.isCompleted {
                        store.toggle(saved)
                    } else {
                        store.save(original, undo: saved, actionName: actionName)
                    }
                }
            }
            undoManager.setActionName(actionName)
            if let i = items.firstIndex(where: { $0.id == saved.id }) { items[i] = saved }
            reloadSoon()
        } catch {
            fail(error)
        }
    }

    /// The latest known state of `item` (a view may hold an older copy).
    private func current(_ item: ReminderItem) -> ReminderItem {
        items.first { $0.id == item.id } ?? item
    }

    private func fail(_ error: Error) {
        lastError = error.localizedDescription
        reloadSoon()
    }
}
