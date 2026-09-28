import Foundation

/// Whole hours of the day shown on the timeline. `end` is exclusive and may be 24.
public struct HourRange: Equatable, Sendable {
    public let start: Int
    public let end: Int

    /// Clamps to 0...23 for `start` and `start+1...24` for `end`.
    public init(start: Int, end: Int) {
        let s = min(max(start, 0), 23)
        self.start = s
        self.end = min(max(end, s + 1), 24)
    }

    public static let standard = HourRange(start: 8, end: 20)

    /// Keeps `end`, pushing it later only if the new start would pass it.
    public func withStart(_ hour: Int) -> HourRange { HourRange(start: hour, end: max(end, hour + 1)) }

    /// Keeps `start`, pulling it earlier only if the new end would pass it.
    public func withEnd(_ hour: Int) -> HourRange { HourRange(start: min(start, hour - 1), end: hour) }

    public func dates(on dayStart: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let s = calendar.date(bySettingHour: start, minute: 0, second: 0, of: dayStart) ?? dayStart
        let e = end == 24
            ? calendar.date(byAdding: .day, value: 1, to: dayStart)!
            : calendar.date(bySettingHour: end, minute: 0, second: 0, of: dayStart)!
        return (s, e)
    }

    /// The smallest range containing `self` and the parts of `events` that fall on this day.
    public func expanded(toInclude events: [EventItem], dayStart: Date, calendar: Calendar) -> HourRange {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        var lo = start
        var hi = end
        for event in events where event.end > dayStart && event.start < dayEnd {
            let s = max(event.start, dayStart)
            let e = min(event.end, dayEnd)
            lo = min(lo, calendar.component(.hour, from: s))
            if e >= dayEnd {
                hi = 24
            } else {
                let parts = calendar.dateComponents([.hour, .minute, .second], from: e)
                let roundUp = (parts.minute ?? 0) > 0 || (parts.second ?? 0) > 0
                hi = max(hi, (parts.hour ?? 0) + (roundUp ? 1 : 0))
            }
        }
        return HourRange(start: lo, end: hi)
    }
}

/// Maps between time and vertical position for one day's visible range.
/// Uses real elapsed time, so a DST day's range is 23 or 25 hours tall without gaps.
public struct TimelineGeometry: Sendable {
    public let dayStart: Date
    public let range: HourRange
    public let rangeStart: Date
    public let rangeEnd: Date
    public let height: Double
    private let calendar: Calendar

    public init(dayStart: Date, range: HourRange, height: Double, calendar: Calendar = .autoupdatingCurrent) {
        self.dayStart = dayStart
        self.range = range
        self.height = height
        self.calendar = calendar
        (rangeStart, rangeEnd) = range.dates(on: dayStart, calendar: calendar)
    }

    public var pointsPerSecond: Double { height / rangeEnd.timeIntervalSince(rangeStart) }

    public func y(for date: Date) -> Double { date.timeIntervalSince(rangeStart) * pointsPerSecond }

    public func date(forY y: Double) -> Date { rangeStart.addingTimeInterval(y / pointsPerSecond) }

    public func y(forHour hour: Int) -> Double {
        if hour >= 24 { return y(for: calendar.date(byAdding: .day, value: 1, to: dayStart)!) }
        return y(for: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) ?? dayStart)
    }

    /// Vertical extent of `event`, clipped to the visible range, never shorter than `minHeight`.
    public func frame(for event: EventItem, minHeight: Double = 14) -> (top: Double, height: Double) {
        let top = y(for: max(event.start, rangeStart))
        let bottom = y(for: min(event.end, rangeEnd))
        return (top, max(bottom - top, minHeight))
    }

    public func partition(_ events: [EventItem]) -> RangePartition {
        var result = RangePartition()
        for event in events {
            if event.end <= rangeStart && event.start < rangeStart {
                result.earlier.append(event)
            } else if event.start >= rangeEnd {
                result.later.append(event)
            } else {
                result.visible.append(event)
            }
        }
        return result
    }
}

public struct RangePartition: Equatable, Sendable {
    public var visible: [EventItem] = []
    public var earlier: [EventItem] = []
    public var later: [EventItem] = []
    public init() {}
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
