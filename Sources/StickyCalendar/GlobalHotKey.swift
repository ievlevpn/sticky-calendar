import Carbon.HIToolbox
import Observation
import StickyCalendarCore

/// The system-wide show/hide shortcut, through Carbon's hot-key API (no Accessibility
/// permission needed). One at a time; `failed` is set when another app already owns it.
@MainActor
@Observable
final class GlobalHotKey {
    private(set) var failed = false
    @ObservationIgnored private var ref: EventHotKeyRef?
    @ObservationIgnored private let action: () -> Void

    /// Carbon calls back through a C function, which can't capture: route via this.
    @ObservationIgnored private static var current: GlobalHotKey?
    @ObservationIgnored private static var handlerInstalled = false

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func apply(_ choice: GlobalHotKeyChoice) {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        failed = false
        guard let (keyCode, modifiers) = Self.carbonKey(for: choice) else { return }
        Self.current = self
        Self.installHandler()
        let id = EventHotKeyID(signature: OSType(0x5354_4B59), id: 1) // 'STKY'
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        failed = status != noErr
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon delivers hot keys on the main thread's run loop.
            MainActor.assumeIsolated { GlobalHotKey.current?.action() }
            return noErr
        }, 1, &pressed, nil, nil)
    }

    private static func carbonKey(for choice: GlobalHotKeyChoice) -> (UInt32, UInt32)? {
        let controlOption = UInt32(controlKey | optionKey)
        return switch choice {
        case .off: nil
        case .controlOptionS: (UInt32(kVK_ANSI_S), controlOption)
        case .controlOptionCommandS: (UInt32(kVK_ANSI_S), controlOption | UInt32(cmdKey))
        case .controlOptionSpace: (UInt32(kVK_Space), controlOption)
        }
    }
}
