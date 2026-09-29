import Foundation

/// What compact mode shows: the event going on now, or else the next one to start.
public struct UpNext: Equatable, Sendable {
    public let item: EventItem
    public let isOngoing: Bool

    /// Among timed events: an ongoing one (the first to end, if several), else the next
    /// to start; nil when nothing is left.
    public static func pick(from events: [EventItem], now: Date) -> UpNext? {
        let timed = events.filter { !$0.isAllDay }
        if let ongoing = timed.filter({ $0.start <= now && now < $0.end }).min(by: { $0.end < $1.end }) {
            return UpNext(item: ongoing, isOngoing: true)
        }
        if let next = timed.filter({ $0.start > now }).min(by: { $0.start < $1.start }) {
            return UpNext(item: next, isOngoing: false)
        }
        return nil
    }
}
