import Foundation
import Observation

/// One event before and after an edit.
public struct EventChange: Equatable, Sendable {
    public var original: EventItem
    public var updated: EventItem

    public init(original: EventItem, updated: EventItem) {
        self.original = original
        self.updated = updated
    }
}

/// An edit to a recurring event, waiting for the user to pick "this" or "future" events.
public struct PendingEdit: Equatable, Sendable {
    public var original: EventItem
    public var updated: EventItem
    /// Events moved together with this one (a multi-selection). The span choice applies to
    /// the recurring ones among them.
    public var alongside: [EventChange] = []

    /// The edited version of the event `id`, if this edit changes it.
    public func updated(id: String) -> EventItem? {
        if original.id == id { return updated }
        return alongside.first { $0.original.id == id }?.updated
    }
}

/// Where the timeline should scroll to.
public enum TimelineScrollTarget: Hashable, Sendable {
    case now
    case event(String)
    case hour(Int)
}

/// A request to scroll; a new `id` asks again even when the target is unchanged.
public struct ScrollRequest: Equatable, Sendable {
    public let id: Int
    public let target: TimelineScrollTarget
}

/// A keyboard scroll: whole hours, or screenfuls (which keep an hour of overlap).
public enum ScrollStep: Equatable, Sendable {
    case hour(Int)
    case page(Int)
}

/// One-shot commands from the keyboard to the timeline view; a new `id` repeats them.
public struct ScrollStepRequest: Equatable, Sendable {
    public let id: Int
    public let step: ScrollStep
}

public struct EventRequest: Equatable, Sendable {
    public let id: Int
    public let eventID: String
}

/// The single owner of calendar state for the UI. All reads and writes go through here.
@MainActor
@Observable
public final class CalendarStore {
    public private(set) var access: CalendarAccess = .notDetermined
    /// Start of the day being shown.
    public private(set) var day: Date
    public private(set) var timedEvents: [EventItem] = []
    public private(set) var allDayEvents: [EventItem] = []
    public private(set) var calendars: [CalendarInfo] = []
    public private(set) var scrollRequest = ScrollRequest(id: 0, target: .now)
    /// Reported by the timeline: whether the now-ruler is inside the visible area.
    public var isNowOnScreen = true
    public private(set) var scrollStepRequest: ScrollStepRequest?
    /// Scroll this block into view if it isn't (keyboard selection).
    public private(set) var revealRequest: EventRequest?
    /// Open this block's editor with the title focused (Return).
    public private(set) var editRequest: EventRequest?
    @ObservationIgnored private var requestCounter = 0
    /// The selected blocks (⌘- or ⇧-click adds and removes them).
    public private(set) var selectedIDs: Set<String> = []
    private var primarySelection: String?
    /// The selected block the keyboard acts on: the one clicked last. Setting it selects
    /// that block alone.
    public var selectedID: String? {
        get { selectedIDs.isEmpty ? nil : primarySelection }
        set {
            primarySelection = newValue
            selectedIDs = newValue.map { [$0] } ?? []
        }
    }
    public var lastError: String?
    public var pendingEdit: PendingEdit?
    public var pendingDelete: EventItem?
    /// Several selected events waiting for confirmation before deleting.
    public var pendingGroupDelete: [EventItem]?

    @ObservationIgnored public let undoManager = UndoManager()
    @ObservationIgnored private let source: EventSource
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    /// True while the user is "on today"; the view then follows midnight rollover.
    @ObservationIgnored private var followsToday = true
    /// Old → new `eventIdentifier` for events EventKit re-identified (recreated by undo,
    /// moved to another calendar), so older undo/redo steps still find them.
    @ObservationIgnored private var replacedIdentifiers: [String: String] = [:]

    public init(
        source: EventSource,
        settings: AppSettings,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.settings = settings
        self.calendar = calendar
        self.now = now
        day = calendar.startOfDay(for: now())
        source.onChange = { [weak self] in self?.reload() }
        reload()
        requestScroll()
    }

    // MARK: Reading

    public var isViewingToday: Bool { calendar.isDate(day, inSameDayAs: now()) }

    public var visibleCalendars: [CalendarInfo] {
        calendars.filter { !settings.hiddenCalendarIDs.contains($0.id) }
    }

    public func calendarInfo(id: String) -> CalendarInfo? { calendars.first { $0.id == id } }

    public var offersJumpToNow: Bool { !isViewingToday || !isNowOnScreen }

    public func reload() {
        access = source.currentAccess()
        guard access == .granted else {
            calendars = []
            timedEvents = []
            allDayEvents = []
            return
        }
        calendars = source.calendars()
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
        let hidden = settings.hiddenCalendarIDs
        let events = source.events(from: day, to: dayEnd)
            .filter { !hidden.contains($0.calendarID) }
            .sorted { $0.start < $1.start }
        timedEvents = events.filter { !$0.isAllDay }
        allDayEvents = events.filter(\.isAllDay)
        let present = Set(timedEvents.map(\.id))
        if !selectedIDs.isSubset(of: present) {
            selectedIDs.formIntersection(present)
            if let id = primarySelection, !selectedIDs.contains(id) { primarySelection = firstSelected() }
        }
    }

    /// Adds `id` to the selection, or takes it out if it's already in.
    public func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            if primarySelection == id { primarySelection = firstSelected() }
        } else {
            selectedIDs.insert(id)
            primarySelection = id
        }
    }

    private func firstSelected() -> String? {
        navigationOrder.first { selectedIDs.contains($0.id) }?.id
    }

    /// The refresh button and ⌘R: asks the calendars to sync, and shows what's there now.
    public func refresh() {
        source.refreshIfNeeded()
        reload()
    }

    public func requestAccessIfNeeded() async {
        if source.currentAccess() == .notDetermined { _ = await source.requestAccess() }
        reload()
    }

    // MARK: Keyboard

    /// Timed events in reading order: by start time, then left to right.
    public var navigationOrder: [EventItem] {
        let slots = OverlapLayout.columns(for: timedEvents)
        return timedEvents.sorted {
            ($0.start, slots[$0.id]?.column ?? 0) < ($1.start, slots[$1.id]?.column ?? 0)
        }
    }

    /// Moves the selection `step` blocks along the reading order, stopping at the ends.
    /// Returns false when nothing is selected, so the caller can scroll instead.
    @discardableResult
    public func selectAdjacent(_ step: Int) -> Bool {
        let order = navigationOrder
        guard let id = selectedID, let index = order.firstIndex(where: { $0.id == id }) else { return false }
        let target = order[min(max(index + step, 0), order.count - 1)]
        selectedID = target.id
        revealRequest = EventRequest(id: nextRequestID(), eventID: target.id)
        return true
    }

    /// Esc: returns false when nothing was selected, so the key can do its usual thing.
    @discardableResult
    public func clearSelection() -> Bool {
        guard selectedID != nil else { return false }
        selectedID = nil
        return true
    }

    public func scrollStep(_ step: ScrollStep) {
        scrollStepRequest = ScrollStepRequest(id: nextRequestID(), step: step)
    }

    public func requestEditSelected() {
        guard let id = selectedID, timedEvents.contains(where: { $0.id == id }) else { return }
        editRequest = EventRequest(id: nextRequestID(), eventID: id)
    }

    private func nextRequestID() -> Int {
        requestCounter += 1
        return requestCounter
    }

    // MARK: Navigation

    public func goToToday() {
        followsToday = true
        setDay(now())
    }

    /// Back to today, scrolled so the current time is in view (even if already on today).
    public func jumpToNow() { goToToday() }

    /// Shows `date`'s day (the month picker).
    public func goTo(_ date: Date) {
        followsToday = calendar.isDate(date, inSameDayAs: now())
        setDay(date)
    }

    public func goToDay(offset: Int) {
        let target = calendar.date(byAdding: .day, value: offset, to: day)!
        followsToday = calendar.isDate(target, inSameDayAs: now())
        setDay(target)
    }

    /// Call on midnight, wake from sleep, or time-zone change.
    public func handleClockChange() {
        let today = calendar.startOfDay(for: now())
        if followsToday && day != today { setDay(today) } else { reload() }
    }

    private func setDay(_ date: Date) {
        day = calendar.startOfDay(for: date)
        selectedID = nil
        reload()
        requestScroll()
    }

    /// Today opens at the current time; other days at their first timed event, or 08:00.
    private func requestScroll() {
        let target: TimelineScrollTarget = isViewingToday
            ? .now
            : timedEvents.first.map { .event($0.id) } ?? .hour(8)
        scrollRequest = ScrollRequest(id: scrollRequest.id + 1, target: target)
    }

    // MARK: Editing

    /// An unsaved event in the default calendar, or the first visible writable one.
    /// Nil when no visible calendar accepts new events.
    public func makeDraft(start: Date, end: Date) -> EventItem? {
        let writable = visibleCalendars.filter(\.isWritable)
        let preferred = source.defaultCalendarID()
        guard let calendarID = writable.first(where: { $0.id == preferred })?.id ?? writable.first?.id else {
            return nil
        }
        return EventItem(title: "", start: start, end: end, calendarID: calendarID)
    }

    /// Saves a draft. A draft with a blank title is discarded and nil is returned.
    @discardableResult
    public func create(_ draft: EventItem) -> EventItem? {
        let item = draft.normalized()
        guard !item.title.isEmpty else { return nil }
        return insert(item)
    }

    /// Saves `item` as a new event (also used to restore a deleted one, whatever its title).
    private func insert(_ item: EventItem) -> EventItem? {
        var fresh = item
        fresh.eventIdentifier = ""
        do {
            let saved = try source.save(fresh, span: .thisEvent)
            noteReplacement(of: item.eventIdentifier, by: saved.eventIdentifier)
            undoManager.registerUndo(withTarget: self) { store in
                MainActor.assumeIsolated { store.delete(saved, span: .thisEvent) }
            }
            undoManager.setActionName("New Event")
            reload()
            selectedID = saved.id
            return saved
        } catch {
            fail(error)
            return nil
        }
    }

    // MARK: Cut, copy and paste

    /// ⌘C: the selected events, in reading order (read-only ones too: copying leaves them be).
    public var selectedEvents: [EventItem] {
        navigationOrder.filter { selectedIDs.contains($0.id) }
    }

    /// ⌘X, once the events are copied: removes the selected ones at once when all can be
    /// restored (one Undo brings them back); otherwise asks first, as ⌫ does.
    public func deleteSelectedForCut() {
        let items = selectedEvents.filter { !$0.isReadOnly }
        guard !items.isEmpty else { return }
        guard items.allSatisfy(\.canUndoDelete) else { return requestDeleteSelected() }
        for item in items { delete(item, span: .thisEvent) }
        undoManager.setActionName(items.count > 1 ? "Cut Events" : "Cut Event")
        selectedID = nil
    }

    /// ⌘V: new copies of `items` on the day being viewed, at the same times of day (several
    /// keep their spacing, across days too), in the same calendar when it's visible and
    /// writable, else the default one. One Undo removes them all. The copies end up selected.
    @discardableResult
    public func paste(_ items: [EventItem]) -> [EventItem] {
        guard let first = items.map(\.start).min() else { return [] }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: day).day ?? 0
        let shift = { (date: Date) in self.calendar.date(byAdding: .day, value: days, to: date) ?? date }
        let writable = Set(visibleCalendars.filter(\.isWritable).map(\.id))
        var pasted: [EventItem] = []
        for item in items {
            let start = shift(item.start)
            guard let draft = makeDraft(start: start, end: shift(item.end)) else {
                lastError = "No visible calendar accepts new events."
                break
            }
            var copy = EventItem(title: item.title, start: start, end: draft.end, isAllDay: item.isAllDay,
                                 calendarID: writable.contains(item.calendarID) ? item.calendarID : draft.calendarID,
                                 location: item.location, notes: item.notes,
                                 alarmOffsets: item.alarmOffsets, url: item.url)
            copy = copy.normalized()
            if let saved = insert(copy) { pasted.append(saved) }
        }
        guard !pasted.isEmpty else { return [] }
        undoManager.setActionName(pasted.count > 1 ? "Paste Events" : "Paste Event")
        selectedIDs = Set(pasted.map(\.id))
        primarySelection = pasted.last?.id
        return pasted
    }

    /// Applies an edit, or parks it in `pendingEdit` when a recurring event needs a span choice.
    /// Only fields that actually changed are cleaned up, so re-saving an event never alters it.
    public func requestUpdate(from original: EventItem, to updated: EventItem) {
        requestUpdates([EventChange(original: original, updated: updated)])
    }

    /// Applies several edits at once (a multi-selection moved together) as one undo step.
    /// If any is recurring, asks once (`pendingEdit`); the answer applies to all recurring ones.
    public func requestUpdates(_ changes: [EventChange]) {
        let cleaned = changes.compactMap { change -> EventChange? in
            let (original, updated) = (change.original, change.updated)
            guard !original.isReadOnly, updated != original else { return nil }
            var cleaned = updated.normalized()
            if updated.title == original.title { cleaned.title = original.title }
            return cleaned == original ? nil : EventChange(original: original, updated: cleaned)
        }
        if let recurring = cleaned.firstIndex(where: \.original.isRecurring) {
            var others = cleaned
            let first = others.remove(at: recurring)
            pendingEdit = PendingEdit(original: first.original, updated: first.updated, alongside: others)
        } else {
            apply(cleaned, span: .thisEvent)
        }
    }

    /// Commits an editor that was opened on `snapshot`: applies only the fields the user
    /// changed onto the event's current state, keeping anything synced in meanwhile.
    public func requestEdit(of snapshot: EventItem, result: EventItem) {
        guard result != snapshot else { return }
        let current = timedEvents.first { $0.id == snapshot.id } ?? snapshot
        var merged = current
        if result.title != snapshot.title { merged.title = result.title }
        if result.start != snapshot.start { merged.start = result.start }
        if result.end != snapshot.end { merged.end = result.end }
        if result.calendarID != snapshot.calendarID { merged.calendarID = result.calendarID }
        if result.location != snapshot.location { merged.location = result.location }
        if result.notes != snapshot.notes { merged.notes = result.notes }
        requestUpdate(from: current, to: merged)
    }

    /// Takes the edit explicitly: a dialog may clear `pendingEdit` before its button runs.
    public func confirmEdit(_ edit: PendingEdit, span: EditSpan) {
        pendingEdit = nil
        apply([EventChange(original: edit.original, updated: edit.updated)] + edit.alongside, span: span)
    }

    /// `span` applies to recurring events; the others are always saved as single events.
    /// The undo manager groups by event, so the whole batch undoes in one step.
    private func apply(_ changes: [EventChange], span: EditSpan) {
        for change in changes {
            update(from: change.original, to: change.updated, span: change.original.isRecurring ? span : .thisEvent)
        }
        if changes.count > 1 { undoManager.setActionName("Move Events") }
    }

    public func cancelPendingEdit() { pendingEdit = nil }

    /// Asks for confirmation (via `pendingDelete`) before deleting.
    public func requestDelete(_ item: EventItem) {
        guard !item.isReadOnly else { return }
        pendingDelete = item
    }

    /// ⌫: asks to delete the selected blocks (read-only ones are left alone).
    public func requestDeleteSelected() {
        let items = navigationOrder.filter { selectedIDs.contains($0.id) && !$0.isReadOnly }
        if items.count > 1 {
            pendingGroupDelete = items
        } else if let item = items.first {
            requestDelete(item)
        }
    }

    /// `span` applies to recurring events; the others are deleted as single events. The undo
    /// manager groups by event, so one Undo restores every event that can be restored.
    public func confirmGroupDelete(_ items: [EventItem], span: EditSpan) {
        pendingGroupDelete = nil
        for item in items { delete(item, span: item.isRecurring ? span : .thisEvent) }
        if items.filter(\.canUndoDelete).count > 1 { undoManager.setActionName("Delete Events") }
    }

    public func cancelPendingGroupDelete() { pendingGroupDelete = nil }

    /// Takes the item explicitly: a dialog may clear `pendingDelete` before its button runs.
    public func confirmDelete(_ item: EventItem, span: EditSpan) {
        pendingDelete = nil
        delete(item, span: span)
    }

    public func cancelPendingDelete() { pendingDelete = nil }

    func update(from original: EventItem, to updated: EventItem, span: EditSpan) {
        let target = resolve(updated)
        do {
            let saved = try source.save(target, span: span)
            noteReplacement(of: target.eventIdentifier, by: saved.eventIdentifier)
            undoManager.registerUndo(withTarget: self) { store in
                MainActor.assumeIsolated {
                    store.update(from: saved, to: saved.withContent(of: original), span: span)
                }
            }
            undoManager.setActionName("Edit Event")
            reload()
        } catch {
            fail(error)
        }
    }

    /// Only single events without attendees are undoable (see `EventItem.canUndoDelete`).
    func delete(_ item: EventItem, span: EditSpan) {
        let target = resolve(item)
        do {
            try source.remove(target, span: span)
            if target.canUndoDelete {
                undoManager.registerUndo(withTarget: self) { store in
                    MainActor.assumeIsolated { _ = store.insert(target) }
                }
                undoManager.setActionName("Delete Event")
            }
            reload()
        } catch {
            fail(error)
        }
    }

    private func noteReplacement(of old: String, by new: String) {
        if !old.isEmpty && old != new { replacedIdentifiers[old] = new }
    }

    /// `item` with its identifier brought up to date through any replacements.
    private func resolve(_ item: EventItem) -> EventItem {
        var resolved = item
        var hops = 0
        while let next = replacedIdentifiers[resolved.eventIdentifier], hops < 100 {
            resolved.eventIdentifier = next
            hops += 1
        }
        return resolved
    }

    private func fail(_ error: Error) {
        lastError = error.localizedDescription
        reload()
    }
}
