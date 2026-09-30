import AppKit
import StickyCalendarCore

/// The menu-bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggleItem = NSMenuItem(title: "Hide Sticky", action: #selector(toggle), keyEquivalent: "")
    private let remindersItem = NSMenuItem(title: "Show Reminders", action: #selector(toggleReminders), keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "", action: #selector(getUpdate), keyEquivalent: "")
    private let isPanelVisible: () -> Bool
    private let areRemindersOpen: () -> Bool
    /// Reminders have their own window (not a tab of the sticky), so they get a Show/Hide item.
    private let remindersHaveOwnWindow: () -> Bool
    private let onToggle: () -> Void
    private let onToggleReminders: () -> Void
    private let onSettings: () -> Void
    private let onAbout: () -> Void
    private let updateChecker: UpdateChecker

    init(
        isPanelVisible: @escaping () -> Bool,
        areRemindersOpen: @escaping () -> Bool,
        remindersHaveOwnWindow: @escaping () -> Bool,
        onToggle: @escaping () -> Void,
        onToggleReminders: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onAbout: @escaping () -> Void,
        updateChecker: UpdateChecker
    ) {
        self.isPanelVisible = isPanelVisible
        self.areRemindersOpen = areRemindersOpen
        self.remindersHaveOwnWindow = remindersHaveOwnWindow
        self.onToggle = onToggle
        self.onToggleReminders = onToggleReminders
        self.onSettings = onSettings
        self.onAbout = onAbout
        self.updateChecker = updateChecker
        super.init()

        item.button?.image = NSImage(systemSymbolName: "calendar.day.timeline.left", accessibilityDescription: "Sticky Calendar")

        let menu = NSMenu()
        menu.delegate = self
        let aboutItem = NSMenuItem(title: "About Sticky Calendar", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())
        updateItem.target = self
        updateItem.isHidden = true
        menu.addItem(updateItem)
        toggleItem.target = self
        menu.addItem(toggleItem)
        remindersItem.target = self
        menu.addItem(remindersItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let checkItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sticky Calendar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = isPanelVisible() ? "Hide Sticky" : "Show Sticky"
        remindersItem.title = areRemindersOpen() ? "Hide Reminders" : "Show Reminders"
        remindersItem.isHidden = !remindersHaveOwnWindow()
        if case .available(let info) = updateChecker.status {
            updateItem.title = "Update Available: v\(info.version)…"
            updateItem.isHidden = false
        } else {
            updateItem.isHidden = true
        }
    }

    @objc private func toggle() { onToggle() }
    @objc private func toggleReminders() { onToggleReminders() }
    @objc private func openSettings() { onSettings() }
    @objc private func openAbout() { onAbout() }
    @objc private func checkForUpdates() { UpdateActions.checkFromMenu(updateChecker) }

    @objc private func getUpdate() {
        if case .available(let info) = updateChecker.status { UpdateActions.getUpdate(info) }
    }
}
