import AppKit
import StickyCalendarCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let notepad = Notepad()
    private let source = EventKitSource()
    private lazy var store = CalendarStore(source: source, settings: settings)
    private let reminderSettings = ReminderSettings()
    private lazy var reminderStore = ReminderStore(source: ReminderSources.make(reminderSettings), settings: reminderSettings)
    private var reminderRefresh: Timer?
    private var remindersPanel: RemindersPanel?
    private let updateChecker = UpdateChecker(currentVersion: AppVersion.short)
    private var updateTimer: Timer?
    private lazy var hotKey = GlobalHotKey { [weak self] in self?.toggleFromHotKey() }
    private lazy var remindersHotKey = GlobalHotKey { [weak self] in self?.toggleRemindersFromHotKey() }
    private var panel: StickyPanel?
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()

        let panel = StickyPanel(
            store: store, settings: settings, notepad: notepad,
            reminderStore: reminderStore, reminderSettings: reminderSettings,
            onToggleReminders: { [weak self] in self?.toggleReminders() },
            onSettings: { [weak self] in self?.showSettings() }
        )
        self.panel = panel
        statusItem = StatusItemController(
            isPanelVisible: { [weak panel] in panel?.isVisible ?? false },
            areRemindersOpen: { [weak self] in self?.reminderSettings.isVisible ?? false },
            onToggle: { [weak self] in self?.togglePanel() },
            onToggleReminders: { [weak self] in self?.toggleReminders() },
            onSettings: { [weak self] in self?.showSettings() },
            updateChecker: updateChecker
        )
        panel.orderFrontRegardless()
        if reminderSettings.placement == .window, reminderSettings.isVisible { showRemindersWindow() }
        hotKey.apply(settings.globalHotKey.carbonKey)
        remindersHotKey.apply(reminderSettings.hotKey.carbonKey)
        scheduleReminderRefresh()

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

    /// The global shortcut: brings the sticky forward and focuses it, or hides it if it
    /// already has focus.
    private func toggleFromHotKey() {
        guard let panel else { return }
        if panel.isVisible && panel.isKeyWindow {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    // MARK: Reminders

    /// The header button and menu item: opens or closes the reminders window, or switches
    /// the calendar sticky to its Reminders tab and back.
    private func toggleReminders() {
        switch reminderSettings.placement {
        case .window:
            if reminderSettings.isVisible { hideRemindersWindow() } else { showRemindersWindow() }
        case .tab:
            if settings.isCompact { panel?.toggleCompact() }
            reminderSettings.setVisible(!reminderSettings.isVisible)
            panel?.orderFrontRegardless()
        }
    }

    /// The reminders' global shortcut: like the sticky's, shows and focuses them, or hides
    /// them when they already have focus.
    private func toggleRemindersFromHotKey() {
        switch reminderSettings.placement {
        case .window:
            if let window = remindersPanel, window.isVisible, window.isKeyWindow {
                hideRemindersWindow()
            } else {
                showRemindersWindow()
                remindersPanel?.makeKey()
            }
        case .tab:
            guard let panel else { return }
            let showing = reminderSettings.isVisible && panel.isVisible && panel.isKeyWindow
            if showing {
                reminderSettings.setVisible(false)
            } else {
                if settings.isCompact { panel.toggleCompact() }
                reminderSettings.setVisible(true)
                panel.orderFrontRegardless()
                panel.makeKey()
            }
        }
    }

    private func showRemindersWindow() {
        if remindersPanel == nil {
            remindersPanel = RemindersPanel(
                store: reminderStore, settings: reminderSettings, appSettings: settings, beside: panel,
                onSettings: { [weak self] in self?.showSettings() },
                onClose: { [weak self] in self?.hideRemindersWindow() }
            )
        }
        reminderSettings.setVisible(true)
        remindersPanel?.orderFrontRegardless()
    }

    private func hideRemindersWindow() {
        reminderSettings.setVisible(false)
        remindersPanel?.orderOut(nil)
    }

    /// Settings → Reminders → Change Source: forget the source and show the chooser.
    private func changeReminderSource() {
        reminderSettings.setProvider(nil)
        reminderStore.use(nil)
        if !reminderSettings.isVisible { toggleReminders() }
    }

    /// Todoist and TickTick don't announce changes: look again every few minutes.
    private func scheduleReminderRefresh() {
        reminderRefresh = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.reminderSettings.isVisible else { return }
                Task { await self.reminderStore.reload() }
            }
        }
    }

    /// Settings → Reminders: a new placement starts closed, and the other one's window goes.
    private func setReminderPlacement(_ placement: ReminderPlacement) {
        guard placement != reminderSettings.placement else { return }
        hideRemindersWindow()
        reminderSettings.setPlacement(placement)
    }

    private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(
                    store: store, settings: settings, notepad: notepad, hotKey: hotKey,
                    reminderStore: reminderStore, reminderSettings: reminderSettings, remindersHotKey: remindersHotKey,
                    onReminderPlacement: { [weak self] in self?.setReminderPlacement($0) },
                    onChangeReminderSource: { [weak self] in self?.changeReminderSource() },
                    updateChecker: updateChecker
                )
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
            MainActor.assumeIsolated {
                self?.store.handleClockChange()
                self?.reminderStore.handleDayChange()
            }
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
