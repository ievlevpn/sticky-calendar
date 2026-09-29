import AppKit
import StickyCalendarCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let source = EventKitSource()
    private lazy var store = CalendarStore(source: source, settings: settings)
    private let updateChecker = UpdateChecker(currentVersion: AppVersion.short)
    private var updateTimer: Timer?
    private var panel: StickyPanel?
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()

        let panel = StickyPanel(store: store, settings: settings)
        self.panel = panel
        statusItem = StatusItemController(
            isPanelVisible: { [weak panel] in panel?.isVisible ?? false },
            onToggle: { [weak self] in self?.togglePanel() },
            onSettings: { [weak self] in self?.showSettings() },
            updateChecker: updateChecker
        )
        panel.orderFrontRegardless()

        observeClock()
        Task { await store.requestAccessIfNeeded() }
        scheduleUpdateChecks()
    }

    /// Checks at launch, then hourly asks whether a (daily) check is due.
    private func scheduleUpdateChecks() {
        let checker = updateChecker
        Task { await checker.checkIfDue() }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            Task { @MainActor in await checker.checkIfDue() }
        }
    }

    private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(store: store, settings: settings, updateChecker: updateChecker)
            ))
            window.title = "Sticky Calendar Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func observeClock() {
        let onClockChange: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.store.handleClockChange() }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: onClockChange))
        observers.append(center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: onClockChange))
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: onClockChange
        ))
    }

    /// Accessory apps show no menu bar, but key equivalents still route through the
    /// main menu — without an Edit menu, ⌘C/⌘V/⌘Z would not work in text fields.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Sticky Calendar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)

        return main
    }
}

enum AppVersion {
    static let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0-dev"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
}
