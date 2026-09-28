import Foundation
import Observation

/// User preferences, persisted in UserDefaults on every change.
@MainActor
@Observable
public final class AppSettings {
    private enum Key {
        static let startHour = "startHour"
        static let endHour = "endHour"
        static let hiddenCalendarIDs = "hiddenCalendarIDs"
        static let opacity = "opacity"
    }

    public static let opacityRange: ClosedRange<Double> = 0.5...1.0

    @ObservationIgnored private let defaults: UserDefaults

    public private(set) var hourRange: HourRange
    public private(set) var hiddenCalendarIDs: Set<String>
    public private(set) var opacity: Double

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hourRange = HourRange(
            start: defaults.object(forKey: Key.startHour) as? Int ?? HourRange.standard.start,
            end: defaults.object(forKey: Key.endHour) as? Int ?? HourRange.standard.end
        )
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: Key.hiddenCalendarIDs) ?? [])
        opacity = Self.clampOpacity(defaults.object(forKey: Key.opacity) as? Double ?? 0.92)
    }

    public func setStartHour(_ hour: Int) { store(hourRange.withStart(hour)) }

    public func setEndHour(_ hour: Int) { store(hourRange.withEnd(hour)) }

    public func setCalendar(_ id: String, visible: Bool) {
        if visible { hiddenCalendarIDs.remove(id) } else { hiddenCalendarIDs.insert(id) }
        defaults.set(hiddenCalendarIDs.sorted(), forKey: Key.hiddenCalendarIDs)
    }

    public func setOpacity(_ value: Double) {
        opacity = Self.clampOpacity(value)
        defaults.set(opacity, forKey: Key.opacity)
    }

    private func store(_ range: HourRange) {
        hourRange = range
        defaults.set(range.start, forKey: Key.startHour)
        defaults.set(range.end, forKey: Key.endHour)
    }

    private static func clampOpacity(_ value: Double) -> Double {
        min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }
}
