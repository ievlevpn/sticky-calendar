import Foundation
import Observation

/// The scratch note under the timeline: its text, whether it's shown and how tall it is,
/// persisted in UserDefaults on every change.
@MainActor
@Observable
public final class Notepad {
    private enum Key {
        static let text = "noteText"
        static let isVisible = "isNoteVisible"
        static let height = "noteHeight"
    }

    public static let minHeight: Double = 60
    public static let defaultHeight: Double = 140

    @ObservationIgnored private let defaults: UserDefaults

    public private(set) var text: String
    /// Hidden until the user opens it from the header.
    public private(set) var isVisible: Bool
    /// Preferred height; the view may show less when the window is short.
    public private(set) var height: Double

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        text = defaults.string(forKey: Key.text) ?? ""
        isVisible = defaults.object(forKey: Key.isVisible) as? Bool ?? false
        height = max(defaults.object(forKey: Key.height) as? Double ?? Self.defaultHeight, Self.minHeight)
    }

    public func setText(_ value: String) {
        guard value != text else { return }
        text = value
        defaults.set(value, forKey: Key.text)
    }

    public func setVisible(_ visible: Bool) {
        isVisible = visible
        defaults.set(visible, forKey: Key.isVisible)
    }

    public func setHeight(_ value: Double) {
        height = max(value, Self.minHeight)
        defaults.set(height, forKey: Key.height)
    }
}
