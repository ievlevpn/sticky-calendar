import AppKit

/// The menu-bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggleItem = NSMenuItem(title: "Hide Sticky", action: #selector(toggle), keyEquivalent: "")
    private let isPanelVisible: () -> Bool
    private let onToggle: () -> Void
    private let onSettings: () -> Void

    init(isPanelVisible: @escaping () -> Bool, onToggle: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.isPanelVisible = isPanelVisible
        self.onToggle = onToggle
        self.onSettings = onSettings
        super.init()

        item.button?.image = NSImage(systemSymbolName: "calendar.day.timeline.left", accessibilityDescription: "Sticky Calendar")

        let menu = NSMenu()
        menu.delegate = self
        toggleItem.target = self
        menu.addItem(toggleItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sticky Calendar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = isPanelVisible() ? "Hide Sticky" : "Show Sticky"
    }

    @objc private func toggle() { onToggle() }
    @objc private func openSettings() { onSettings() }
}
