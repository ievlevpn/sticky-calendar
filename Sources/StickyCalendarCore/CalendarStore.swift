import Foundation
import Observation

/// An edit to a recurring event, waiting for the user to pick "this" or "future" events.
public struct PendingEdit: Equatable, Sendable {
    public var original: EventItem
    public var updated: EventItem
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
    public var selectedID: String?
    public var lastError: String?
    public var pendingEdit: PendingEdit?
    public var pendingDelete: EventItem?

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
        if let id = selectedID, !timedEvents.contains(where: { $0.id == id }) { selectedID = nil }
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

    /// Applies an edit, or parks it in `pendingEdit` when a recurring event needs a span choice.
    /// Only fields that actually changed are cleaned up, so re-saving an event never alters it.
    public func requestUpdate(from original: EventItem, to updated: EventItem) {
        guard !original.isReadOnly, updated != original else { return }
        var cleaned = updated.normalized()
        if updated.title == original.title { cleaned.title = original.title }
        guard cleaned != original else { return }
        if original.isRecurring {
            pendingEdit = PendingEdit(original: original, updated: cleaned)
        } else {
            update(from: original, to: cleaned, span: .thisEvent)
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
        update(from: edit.original, to: edit.updated, span: span)
    }

    public func cancelPendingEdit() { pendingEdit = nil }

    /// Asks for confirmation (via `pendingDelete`) before deleting.
    public func requestDelete(_ item: EventItem) {
        guard !item.isReadOnly else { return }
        pendingDelete = item
    }

    public func requestDeleteSelected() {
        guard let id = selectedID, let item = timedEvents.first(where: { $0.id == id }) else { return }
        requestDelete(item)
    }

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
