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
    /// A fetch is under way (for the refresh button's spinner).
    public private(set) var isLoading = false
    /// Bumped by ⌘F; the reminders view opens and focuses its search field.
    public private(set) var searchRequest = 0
    /// Whether a source is chosen; without one, the view asks where reminders come from.
    public private(set) var hasSource = false

    @ObservationIgnored public let undoManager = UndoManager()
    @ObservationIgnored public private(set) var source: ReminderSource?
    @ObservationIgnored private let settings: ReminderSettings
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    /// Ticked here since the last day change: they stay in view, struck through, so a
    /// mis-click can be seen and undone.
    private var recentlyCompleted: Set<String> = []
    /// Bumped on every reload and source change; an older fetch must not overwrite a newer one.
    @ObservationIgnored private var generation = 0
    /// Changes still being saved (undo and redo run as tasks); see `idle()`.
    @ObservationIgnored private var work: [Task<Void, Never>] = []

    public init(source: ReminderSource?, settings: ReminderSettings,
                calendar: Calendar = .autoupdatingCurrent, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.calendar = calendar
        self.now = now
        use(source, reload: false)
    }

    /// Switches to another source (or none), dropping what the old one showed.
    public func use(_ source: ReminderSource?, reload shouldReload: Bool = true) {
        self.source?.onChange = nil
        self.source = source
        hasSource = source != nil
        generation += 1
        items = []
        lists = []
        recentlyCompleted = []
        undoManager.removeAllActions()
        access = source?.currentAccess() ?? .notDetermined
        source?.onChange = { [weak self] in self?.reloadSoon() }
        if shouldReload { reloadSoon() }
    }

    // MARK: Loading

    /// Asks for access the first time the reminders view is shown, not at launch.
    public func requestAccessIfNeeded() async {
        guard let source else { return }
        if source.currentAccess() == .notDetermined { _ = await source.requestAccess() }
        await reload()
    }

    public func reload() async {
        guard let source else { return }
        access = source.currentAccess()
        guard access == .granted else {
            lists = []
            items = []
            return
        }
        generation += 1
        let mine = generation
        isLoading = true
        defer { if mine == generation { isLoading = false } }
        do {
            let fetched = try await source.reminders(completedSince: calendar.startOfDay(for: now()))
            guard mine == generation else { return }
            lists = source.lists()
            items = fetched
            access = source.currentAccess()
        } catch {
            guard mine == generation else { return }
            access = source.currentAccess()
            lastError = error.localizedDescription
        }
    }

    public func requestSearch() { searchRequest += 1 }

    /// The refresh button and ⌘R: syncs the source with its server if it can, then reloads.
    public func refresh() async {
        source?.refreshIfNeeded()
        await reload()
    }

    private func reloadSoon() {
        run { await self.reload() }
    }

    /// Waits until changes in progress (including undo and redo) are saved.
    public func idle() async {
        while !work.isEmpty {
            let pending = work
            work = []
            for task in pending { await task.value }
        }
    }

    private func run(_ body: @escaping @MainActor () async -> Void) {
        work.append(Task { await body() })
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

    /// What compact mode flips through: the open reminders of the current mode, in order.
    public var openItems: [ReminderItem] {
        sections.flatMap(\.items).filter { !$0.isCompleted }
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
    /// one on the same day, then by importance, then by title.
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
            if a.priority != b.priority { return a.priority > b.priority }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    // MARK: Changes

    /// Ticks or unticks.
    public func toggle(_ item: ReminderItem) async {
        let original = current(item)
        var changed = original
        changed.isCompleted.toggle()
        changed.completionDate = changed.isCompleted ? now() : nil
        if changed.isCompleted { recentlyCompleted.insert(item.id) }
        await save(changed, undo: original, actionName: changed.isCompleted ? "Complete Reminder" : "Uncomplete Reminder")
    }

    /// The editor's changes: title, due date and time, importance, notes.
    public func edit(_ item: ReminderItem, title: String, due: Date?, dueHasTime: Bool,
                     priority: ReminderPriority, notes: String?) async {
        let original = current(item)
        var changed = original
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { changed.title = trimmed }
        changed.due = due
        changed.dueHasTime = due != nil && dueHasTime
        changed.priority = priority
        if source?.canEditNotes ?? false {
            let text = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            changed.notes = text.isEmpty ? nil : text
        }
        guard changed != original else { return }
        await save(changed, undo: original, actionName: "Edit Reminder")
    }

    /// Reminders matching `query` loosely, across every visible list (whatever the mode),
    /// best first; titles count more than notes. Completed ones only if they'd be shown.
    public func search(_ query: String) -> [ReminderItem] {
        shownItems
            .compactMap { item -> (ReminderItem, Int)? in
                let inTitle = FuzzyMatch.score(query, in: item.title).map { $0 * 2 }
                let inNotes = item.notes.flatMap { FuzzyMatch.score(query, in: $0) }
                guard let best = [inTitle, inNotes].compactMap({ $0 }).max() else { return nil }
                return (item, best)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : !$0.0.isCompleted && $1.0.isCompleted }
            .map(\.0)
    }

    /// Whether the source can write notes (the editor shows them read-only otherwise).
    public var canEditNotes: Bool { source?.canEditNotes ?? false }

    public func rename(_ item: ReminderItem, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = current(item)
        guard !trimmed.isEmpty, trimmed != original.title else { return }
        var changed = original
        changed.title = trimmed
        await save(changed, undo: original, actionName: "Rename Reminder")
    }

    /// Adds a reminder from typed text (a date in it becomes the due date). In Today mode
    /// an undated one is due today. Goes to `listID`, or the default list.
    @discardableResult
    public func add(_ text: String, listID: String? = nil) async -> ReminderItem? {
        var input = ReminderInput.parse(text)
        guard !input.title.isEmpty else { return nil }
        if input.due == nil, settings.mode == .today {
            input.due = calendar.startOfDay(for: now())
        }
        guard let list = listID ?? defaultWritableListID() else {
            lastError = "There's no list to add to."
            return nil
        }
        return await insert(ReminderItem(title: input.title, listID: list, due: input.due, dueHasTime: input.dueHasTime))
    }

    public func delete(_ item: ReminderItem) async {
        guard let source else { return }
        let target = current(item)
        items.removeAll { $0.id == target.id }
        do {
            try await source.remove(target)
            undoManager.registerUndo(withTarget: self) { store in
                MainActor.assumeIsolated { store.run { _ = await store.insert(target) } }
            }
            undoManager.setActionName("Delete Reminder")
            reloadSoon()
        } catch {
            fail(error)
        }
    }

    /// The list new reminders go to: the source's default if it's visible and writable,
    /// else the first visible writable list.
    public func defaultWritableListID() -> String? {
        let writable = visibleLists.filter(\.isWritable)
        if let id = source?.defaultListID(), writable.contains(where: { $0.id == id }) { return id }
        return writable.first?.id
    }

    /// Opens `item` in its source's app.
    public func link(for item: ReminderItem) -> URL? { source?.link(for: item) }

    /// Saves as new (also restores a deleted one, which gets a new identifier).
    private func insert(_ item: ReminderItem) async -> ReminderItem? {
        guard let source else { return nil }
        var fresh = item
        fresh.id = ""
        do {
            let saved = try await source.save(fresh)
            undoManager.registerUndo(withTarget: self) { store in
                MainActor.assumeIsolated { store.run { await store.delete(saved) } }
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

    /// Shows the change at once, then saves it; puts the original back if saving fails.
    private func save(_ changed: ReminderItem, undo original: ReminderItem, actionName: String) async {
        guard let source else { return }
        replace(changed)
        do {
            let saved = try await source.save(changed)
            replace(saved)
            undoManager.registerUndo(withTarget: self) { store in
                MainActor.assumeIsolated {
                    store.run {
                        if original.isCompleted != saved.isCompleted {
                            await store.toggle(saved)
                        } else {
                            await store.save(original, undo: saved, actionName: actionName)
                        }
                    }
                }
            }
            undoManager.setActionName(actionName)
            reloadSoon()
        } catch {
            replace(original)
            fail(error)
        }
    }

    private func replace(_ item: ReminderItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
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

/// A failure a network source can report in plain words.
public struct ReminderSourceError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }

}
