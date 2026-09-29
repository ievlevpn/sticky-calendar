import AppKit
import StickyCalendarCore

/// The menu-bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggleItem = NSMenuItem(title: "Hide Sticky", action: #selector(toggle), keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "", action: #selector(getUpdate), keyEquivalent: "")
    private let isPanelVisible: () -> Bool
    private let onToggle: () -> Void
    private let onSettings: () -> Void
    private let updateChecker: UpdateChecker

    init(
        isPanelVisible: @escaping () -> Bool,
        onToggle: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        updateChecker: UpdateChecker
    ) {
        self.isPanelVisible = isPanelVisible
        self.onToggle = onToggle
        self.onSettings = onSettings
        self.updateChecker = updateChecker
        super.init()

        item.button?.image = NSImage(systemSymbolName: "calendar.day.timeline.left", accessibilityDescription: "Sticky Calendar")

        let menu = NSMenu()
        menu.delegate = self
        updateItem.target = self
        updateItem.isHidden = true
        menu.addItem(updateItem)
        toggleItem.target = self
        menu.addItem(toggleItem)
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
        if case .available(let info) = updateChecker.status {
            updateItem.title = "Update Available: v\(info.version)…"
            updateItem.isHidden = false
        } else {
            updateItem.isHidden = true
        }
    }

    @objc private func toggle() { onToggle() }
    @objc private func openSettings() { onSettings() }
    @objc private func checkForUpdates() { UpdateActions.checkFromMenu(updateChecker) }

    @objc private func getUpdate() {
        if case .available(let info) = updateChecker.status { UpdateActions.getUpdate(info) }
    }
}
