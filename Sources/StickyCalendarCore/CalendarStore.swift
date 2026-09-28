import Foundation
import Observation

/// An edit to a recurring event, waiting for the user to pick "this" or "future" events.
public struct PendingEdit: Equatable, Sendable {
    public var original: EventItem
    public var updated: EventItem
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
    /// Set by "+N earlier/later"; cleared when the day changes.
    public private(set) var rangeOverride: HourRange?
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
    }

    // MARK: Reading

    public var isViewingToday: Bool { calendar.isDate(day, inSameDayAs: now()) }

    public var visibleCalendars: [CalendarInfo] {
        calendars.filter { !settings.hiddenCalendarIDs.contains($0.id) }
    }

    public func calendarInfo(id: String) -> CalendarInfo? { calendars.first { $0.id == id } }

    public var effectiveRange: HourRange { rangeOverride ?? settings.hourRange }

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

    public func requestAccessIfNeeded() async {
        if source.currentAccess() == .notDetermined { _ = await source.requestAccess() }
        reload()
    }

    // MARK: Navigation

    public func goToToday() {
        followsToday = true
        setDay(now())
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

    public func expandRangeToFitAll() {
        rangeOverride = effectiveRange.expanded(toInclude: timedEvents, dayStart: day, calendar: calendar)
    }

    private func setDay(_ date: Date) {
        day = calendar.startOfDay(for: date)
        rangeOverride = nil
        selectedID = nil
        reload()
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
        var item = draft.normalized()
        guard !item.title.isEmpty else { return nil }
        item.eventIdentifier = ""
        do {
            let saved = try source.save(item, span: .thisEvent)
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
    public func requestUpdate(from original: EventItem, to updated: EventItem) {
        let updated = updated.normalized()
        guard !original.isReadOnly, updated != original else { return }
        if original.isRecurring {
            pendingEdit = PendingEdit(original: original, updated: updated)
        } else {
            update(from: original, to: updated, span: .thisEvent)
        }
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
        do {
            let saved = try source.save(updated, span: span)
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

    /// Deleting a recurring event is not undoable: EventKit cannot recreate the series.
    func delete(_ item: EventItem, span: EditSpan) {
        do {
            try source.remove(item, span: span)
            if !item.isRecurring {
                undoManager.registerUndo(withTarget: self) { store in
                    MainActor.assumeIsolated { _ = store.create(item) }
                }
                undoManager.setActionName("Delete Event")
            }
            reload()
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        lastError = error.localizedDescription
        reload()
    }
}
