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
        static let calendarJumpMode = "calendarJumpMode"
        static let zoom = "zoom"
        static let isCompact = "isCompact"
        static let expandedHeight = "expandedHeight"
        static let globalHotKey = "globalHotKey"
        static let hidesFromCapture = "hidesFromScreenCapture"
    }

    public static let opacityRange: ClosedRange<Double> = 0.5...1.0
    /// Zoom levels for ⌘= / ⌘-, like a browser's.
    public static let zoomSteps: [Double] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]

    @ObservationIgnored private let defaults: UserDefaults

    /// Pinned: floats above other windows on every Space. Unpinned: an ordinary window.
    public private(set) var isPinned: Bool
    public private(set) var hiddenCalendarIDs: Set<String>
    public private(set) var opacity: Double
    /// nil until the user has been asked (on the first click of the calendar button).
    public private(set) var calendarJumpMode: CalendarJumpMode?
    /// Scales the timeline and the note (text and spacing together); the header stays put.
    public private(set) var zoom: Double
    /// Collapsed to the header and the current or next event.
    public private(set) var isCompact: Bool
    /// The window's height before it was made compact, to restore.
    public private(set) var expandedHeight: Double?
    /// The system-wide shortcut that shows or hides the sticky.
    public private(set) var globalHotKey: GlobalHotKeyChoice
    /// Marks the app's windows as not to be captured, so screen sharing and screenshots
    /// leave them out (where the capturing app honours it). Off by default.
    public private(set) var hidesFromScreenCapture: Bool

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPinned = defaults.object(forKey: Key.isPinned) as? Bool ?? true
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: Key.hiddenCalendarIDs) ?? [])
        opacity = Self.clampOpacity(defaults.object(forKey: Key.opacity) as? Double ?? 0.92)
        calendarJumpMode = defaults.string(forKey: Key.calendarJumpMode).flatMap(CalendarJumpMode.init(rawValue:))
        zoom = Self.nearestZoomStep(defaults.object(forKey: Key.zoom) as? Double ?? 1)
        isCompact = defaults.bool(forKey: Key.isCompact)
        expandedHeight = defaults.object(forKey: Key.expandedHeight) as? Double
        globalHotKey = defaults.string(forKey: Key.globalHotKey).flatMap(GlobalHotKeyChoice.init(rawValue:)) ?? .controlOptionS
        hidesFromScreenCapture = defaults.bool(forKey: Key.hidesFromCapture)
    }

    public func setHidesFromScreenCapture(_ hides: Bool) {
        hidesFromScreenCapture = hides
        defaults.set(hides, forKey: Key.hidesFromCapture)
    }

    /// `expandedHeight` is the window height to restore when leaving compact mode.
    public func setCompact(_ compact: Bool, expandedHeight height: Double? = nil) {
        isCompact = compact
        defaults.set(compact, forKey: Key.isCompact)
        if let height {
            expandedHeight = height
            defaults.set(height, forKey: Key.expandedHeight)
        }
    }

    public func setGlobalHotKey(_ choice: GlobalHotKeyChoice) {
        globalHotKey = choice
        defaults.set(choice.rawValue, forKey: Key.globalHotKey)
    }

    /// Snaps to the nearest step.
    public func setZoom(_ value: Double) {
        zoom = Self.nearestZoomStep(value)
        defaults.set(zoom, forKey: Key.zoom)
    }

    public func zoomIn() {
        setZoom(Self.zoomSteps.first { $0 > zoom } ?? zoom)
    }

    public func zoomOut() {
        setZoom(Self.zoomSteps.last { $0 < zoom } ?? zoom)
    }

    public func resetZoom() { setZoom(1) }

    public var canZoomIn: Bool { zoom < Self.zoomSteps.last! }
    public var canZoomOut: Bool { zoom > Self.zoomSteps.first! }

    private static func nearestZoomStep(_ value: Double) -> Double {
        zoomSteps.min { abs($0 - value) < abs($1 - value) }!
    }

    public func setCalendarJumpMode(_ mode: CalendarJumpMode) {
        calendarJumpMode = mode
        defaults.set(mode.rawValue, forKey: Key.calendarJumpMode)
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

/// The system-wide show/hide shortcut, from a few presets that other apps rarely use.
public enum GlobalHotKeyChoice: String, Sendable, CaseIterable {
    case off
    case controlOptionS
    case controlOptionCommandS
    case controlOptionSpace

    /// As shown in menus.
    public var symbol: String {
        switch self {
        case .off: "Off"
        case .controlOptionS: "⌃⌥S"
        case .controlOptionCommandS: "⌃⌥⌘S"
        case .controlOptionSpace: "⌃⌥Space"
        }
    }
}
