import Carbon.HIToolbox
import Observation
import StickyCalendarCore

/// A system-wide shortcut, through Carbon's hot-key API (no Accessibility permission
/// needed). Each instance holds one; `failed` is set when another app already owns it.
@MainActor
@Observable
final class GlobalHotKey {
    private(set) var failed = false
    @ObservationIgnored private var ref: EventHotKeyRef?
    @ObservationIgnored private let id: UInt32
    @ObservationIgnored private let action: () -> Void

    /// Carbon calls back through a C function, which can't capture: route by id.
    @ObservationIgnored private static var registered: [UInt32: GlobalHotKey] = [:]
    @ObservationIgnored private static var handlerInstalled = false
    @ObservationIgnored private static var nextID: UInt32 = 1

    init(action: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        self.action = action
    }

    /// Registers `keyCode` with Carbon `modifiers`, or nothing for nil (off).
    func apply(_ key: (keyCode: UInt32, modifiers: UInt32)?) {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        failed = false
        Self.registered[id] = nil
        guard let key else { return }
        Self.registered[id] = self
        Self.installHandler()
        let hotKeyID = EventHotKeyID(signature: OSType(0x5354_4B59), id: id) // 'STKY'
        let status = RegisterEventHotKey(key.keyCode, key.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        failed = status != noErr
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            // Carbon delivers hot keys on the main thread's run loop.
            MainActor.assumeIsolated { GlobalHotKey.registered[hotKeyID.id]?.action() }
            return noErr
        }, 1, &pressed, nil, nil)
    }
}

private let controlOption = UInt32(controlKey | optionKey)

extension GlobalHotKeyChoice {
    /// The calendar sticky's shortcut, for Carbon.
    var carbonKey: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .off: nil
        case .controlOptionS: (UInt32(kVK_ANSI_S), controlOption)
        case .controlOptionCommandS: (UInt32(kVK_ANSI_S), controlOption | UInt32(cmdKey))
        case .controlOptionSpace: (UInt32(kVK_Space), controlOption)
        }
    }
}

extension RemindersHotKeyChoice {
    /// The reminders' shortcut, for Carbon.
    var carbonKey: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .off: nil
        case .controlOptionR: (UInt32(kVK_ANSI_R), controlOption)
        case .controlOptionCommandR: (UInt32(kVK_ANSI_R), controlOption | UInt32(cmdKey))
        }
    }
}
