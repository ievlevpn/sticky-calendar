import Foundation
import Observation

/// User preferences, persisted in UserDefaults on every change.
@MainActor
@Observable
public final class AppSettings {
    private enum Key {
        static let isPinned = "isPinned"
        static let hiddenCalendarIDs = "hiddenCalendarIDs"
        static let opacity = "opacity"
    }

    public static let opacityRange: ClosedRange<Double> = 0.5...1.0

    @ObservationIgnored private let defaults: UserDefaults

    /// Pinned: floats above other windows on every Space. Unpinned: an ordinary window.
    public private(set) var isPinned: Bool
    public private(set) var hiddenCalendarIDs: Set<String>
    public private(set) var opacity: Double

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPinned = defaults.object(forKey: Key.isPinned) as? Bool ?? true
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: Key.hiddenCalendarIDs) ?? [])
        opacity = Self.clampOpacity(defaults.object(forKey: Key.opacity) as? Double ?? 0.92)
    }

    public func setPinned(_ pinned: Bool) {
        isPinned = pinned
        defaults.set(pinned, forKey: Key.isPinned)
    }

    public func setCalendar(_ id: String, visible: Bool) {
        if visible { hiddenCalendarIDs.remove(id) } else { hiddenCalendarIDs.insert(id) }
        defaults.set(hiddenCalendarIDs.sorted(), forKey: Key.hiddenCalendarIDs)
    }

    public func setOpacity(_ value: Double) {
        opacity = Self.clampOpacity(value)
        defaults.set(opacity, forKey: Key.opacity)
    }

    private static func clampOpacity(_ value: Double) -> Double {
        min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }
}
