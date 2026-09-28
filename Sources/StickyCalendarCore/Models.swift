import Foundation

/// Shortest event the UI will create or resize to.
public let minimumEventDuration: TimeInterval = 15 * 60

/// A colour in sRGB components, so the core stays free of AppKit/SwiftUI types.
public struct RGBA: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let fallback = RGBA(red: 0.23, green: 0.51, blue: 0.96)
}

public struct CalendarInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var color: RGBA
    public var isWritable: Bool

    public init(id: String, title: String, color: RGBA = .fallback, isWritable: Bool = true) {
        self.id = id
        self.title = title
        self.color = color
        self.isWritable = isWritable
    }
}

/// A value-type snapshot of one calendar event (or one occurrence of a recurring event).
public struct EventItem: Identifiable, Equatable, Sendable {
    /// EventKit `eventIdentifier`; empty for a draft that has not been saved yet.
    public var eventIdentifier: String
    /// EventKit `calendarItemExternalIdentifier`, used to open the event in Calendar.app.
    public var externalIdentifier: String?
    /// Original start of this occurrence; together with `eventIdentifier` it pins one occurrence.
    public var occurrenceDate: Date
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var location: String?
    public var notes: String?
    public var isRecurring: Bool
    public var isReadOnly: Bool

    public init(
        eventIdentifier: String = "",
        externalIdentifier: String? = nil,
        occurrenceDate: Date? = nil,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarID: String,
        location: String? = nil,
        notes: String? = nil,
        isRecurring: Bool = false,
        isReadOnly: Bool = false
    ) {
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.occurrenceDate = occurrenceDate ?? start
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.location = location
        self.notes = notes
        self.isRecurring = isRecurring
        self.isReadOnly = isReadOnly
    }

    /// Stable across moves: a non-recurring event keeps its identifier, and a recurring
    /// occurrence keeps its original occurrence date even when rescheduled.
    public var id: String {
        isRecurring ? "\(eventIdentifier)|\(occurrenceDate.timeIntervalSinceReferenceDate)" : eventIdentifier
    }

    public var isNew: Bool { eventIdentifier.isEmpty }
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// This item's identity with `other`'s user-editable fields.
    public func withContent(of other: EventItem) -> EventItem {
        var copy = self
        copy.title = other.title
        copy.start = other.start
        copy.end = other.end
        copy.calendarID = other.calendarID
        copy.location = other.location
        copy.notes = other.notes
        return copy
    }

    /// Trims the title and guarantees `end` is at least `minimumDuration` after `start`.
    public func normalized(minimumDuration: TimeInterval = minimumEventDuration) -> EventItem {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.end < copy.start.addingTimeInterval(minimumDuration), !isAllDay {
            copy.end = copy.start.addingTimeInterval(minimumDuration)
        }
        return copy
    }
}
