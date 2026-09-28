import Foundation

/// Maps between time and vertical position on a day's timeline at a fixed scale.
/// The timeline covers the whole day; the window scrolls over it. Uses real elapsed time,
/// so a DST day is 23 or 25 hours tall without gaps.
public struct TimelineGeometry: Sendable {
    public static let defaultPointsPerHour: Double = 48

    public let dayStart: Date
    public let dayEnd: Date
    public let pointsPerHour: Double
    private let calendar: Calendar

    public init(dayStart: Date, pointsPerHour: Double = defaultPointsPerHour, calendar: Calendar = .autoupdatingCurrent) {
        self.dayStart = dayStart
        self.pointsPerHour = pointsPerHour
        self.calendar = calendar
        dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
    }

    public var pointsPerSecond: Double { pointsPerHour / 3600 }

    public var height: Double { y(for: dayEnd) }

    public func y(for date: Date) -> Double { date.timeIntervalSince(dayStart) * pointsPerSecond }

    public func date(forY y: Double) -> Date { dayStart.addingTimeInterval(y / pointsPerSecond) }

    public func y(forHour hour: Int) -> Double {
        if hour >= 24 { return height }
        return y(for: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) ?? dayStart)
    }

    /// Vertical extent of `event`, clipped to the day, never shorter than `minHeight`.
    public func frame(for event: EventItem, minHeight: Double = 14) -> (top: Double, height: Double) {
        let top = y(for: max(event.start, dayStart))
        let bottom = y(for: min(event.end, dayEnd))
        return (top, max(bottom - top, minHeight))
    }

    /// Position of a scroll target; an event that no longer exists falls back to 08:00.
    public func y(for target: TimelineScrollTarget, events: [EventItem], now: Date) -> Double {
        switch target {
        case .now:
            return y(for: now)
        case .hour(let hour):
            return y(forHour: hour)
        case .event(let id):
            return events.first { $0.id == id }.map { frame(for: $0).top } ?? y(forHour: 8)
        }
    }

    /// Scroll offset that places timeline position `y` at `fraction` of the viewport's
    /// height, clamped to what can actually be scrolled. `padding` is extra space above
    /// 00:00 and below 24:00 in the scrolled content.
    public func scrollOffset(showing y: Double, at fraction: Double, viewportHeight: Double, padding: Double = 0) -> Double {
        let maxOffset = max(0, height + 2 * padding - viewportHeight)
        return min(max(y + padding - fraction * viewportHeight, 0), maxOffset)
    }

    /// Whether `date` lies within a viewport scrolled down by `scrollOffset` points.
    public func isVisible(_ date: Date, scrollOffset: Double, viewportHeight: Double) -> Bool {
        let y = y(for: date)
        return y >= scrollOffset && y <= scrollOffset + viewportHeight
    }
}

public enum Snap {
    public static let step: TimeInterval = 15 * 60

    /// Rounds to the nearest quarter hour. Absolute-time rounding is correct in every
    /// time zone because all UTC offsets are multiples of 15 minutes.
    public static func nearest(_ date: Date, step: TimeInterval = step) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / step).rounded() * step)
    }
}

public enum DragKind: Sendable {
    case move, resizeStart, resizeEnd
}

public enum EventDrag {
    public static let minimumDuration = minimumEventDuration

    /// The event after dragging by `delta` seconds, snapped to 15 minutes.
    public static func apply(_ kind: DragKind, to event: EventItem, delta: TimeInterval) -> EventItem {
        var e = event
        switch kind {
        case .move:
            e.start = Snap.nearest(event.start.addingTimeInterval(delta))
            e.end = e.start.addingTimeInterval(event.duration)
        case .resizeStart:
            e.start = min(Snap.nearest(event.start.addingTimeInterval(delta)),
                          event.end.addingTimeInterval(-minimumDuration))
        case .resizeEnd:
            e.end = max(Snap.nearest(event.end.addingTimeInterval(delta)),
                        event.start.addingTimeInterval(minimumDuration))
        }
        return e
    }

    /// Start and end for a new event dragged out between two points in time (either order).
    public static func newInterval(from a: Date, to b: Date) -> (start: Date, end: Date) {
        let s = Snap.nearest(min(a, b))
        let e = max(Snap.nearest(max(a, b)), s.addingTimeInterval(minimumDuration))
        return (s, e)
    }
}

public struct ColumnSlot: Equatable, Sendable {
    public var column: Int
    public var count: Int
    public init(column: Int, count: Int) {
        self.column = column
        self.count = count
    }
}

public enum OverlapLayout {
    /// Calendar.app-style side-by-side layout: events that transitively overlap form a
    /// cluster; each takes the first free column; all share the cluster's column count.
    public static func columns(for events: [EventItem]) -> [String: ColumnSlot] {
        let sorted = events.sorted { ($0.start, $1.end) < ($1.start, $0.end) }
        var result: [String: ColumnSlot] = [:]
        var cluster: [(id: String, column: Int)] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            for entry in cluster {
                result[entry.id] = ColumnSlot(column: entry.column, count: columnEnds.count)
            }
            cluster = []
            columnEnds = []
        }

        for event in sorted {
            if !cluster.isEmpty && event.start >= clusterEnd { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= event.start }) {
                columnEnds[free] = event.end
                cluster.append((event.id, free))
            } else {
                columnEnds.append(event.end)
                cluster.append((event.id, columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, event.end)
        }
        flush()
        return result
    }
}
