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
    private var reminderTicks = 0
    private var remindersPanel: RemindersPanel?
    private var notesPanel: NotesPanel?
    private let updateChecker = UpdateChecker(currentVersion: AppVersion.short)
    private var updateTimer: Timer?
    private var noteFolderWatch: Timer?
    private lazy var hotKey = GlobalHotKey { [weak self] in self?.toggleFromHotKey() }
    private lazy var remindersHotKey = GlobalHotKey { [weak self] in self?.toggleRemindersFromHotKey() }
    private var panel: StickyPanel?
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()

        let panel = StickyPanel(
            store: store, settings: settings, notepad: notepad,
            reminderStore: reminderStore, reminderSettings: reminderSettings,
            onToggleReminders: { [weak self] in self?.toggleReminders() },
            onToggleNoteWindow: { [weak self] in self?.toggleNoteWindow() },
            onMoveNote: { [weak self] in self?.moveNote(to: $0) },
            onChooseReminderPlacement: { [weak self] in self?.chooseReminderPlacement($0) },
            onSettings: { [weak self] in self?.showSettings() }
        )
        self.panel = panel
        statusItem = StatusItemController(
            isPanelVisible: { [weak panel] in panel?.isVisible ?? false },
            areRemindersOpen: { [weak self] in self?.reminderSettings.isVisible ?? false },
            remindersHaveOwnWindow: { [weak self] in self?.reminderSettings.placement == .window },
            onToggle: { [weak self] in self?.togglePanel() },
            onToggleReminders: { [weak self] in self?.toggleReminders() },
            onSettings: { [weak self] in self?.showSettings() },
            onAbout: { [weak self] in self?.showAbout() },
            updateChecker: updateChecker
        )
        panel.orderFrontRegardless()
        // Not placed yet (e.g. opened as a window by 0.7): ask when they're next opened, not at launch.
        if !reminderSettings.isPlacementChosen { reminderSettings.setVisible(false) }
        if reminderSettings.placement == .window, reminderSettings.isVisible { showRemindersWindow() }
        if notepad.placement == .window, notepad.isVisible { showNoteWindow(focus: false) }
        hotKey.apply(settings.globalHotKey.carbonKey)
        remindersHotKey.apply(reminderSettings.hotKey.carbonKey)
        scheduleReminderRefresh()
        watchNoteFolder()
        applyScreenCapturePrivacy()

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

    // MARK: Screen sharing

    /// Settings → Hide from screen sharing: every window of ours (the stickies, Settings,
    /// About) is marked not to be captured, or capturable again. Called when windows open.
    private func applyScreenCapturePrivacy() {
        let sharing: NSWindow.SharingType = settings.hidesFromScreenCapture ? .none : .readOnly
        for window in [panel, remindersPanel, notesPanel, settingsWindow, aboutWindow] as [NSWindow?] {
            window?.sharingType = sharing
        }
    }

    private func setHidesFromScreenCapture(_ hides: Bool) {
        settings.setHidesFromScreenCapture(hides)
        applyScreenCapturePrivacy()
    }

    // MARK: Note

    private func toggleNoteWindow() {
        if notepad.isVisible { hideNoteWindow() } else { showNoteWindow(focus: true) }
    }

    private func showNoteWindow(focus: Bool) {
        if notesPanel == nil {
            notesPanel = NotesPanel(
                notepad: notepad, appSettings: settings, beside: panel,
                onSettings: { [weak self] in self?.showSettings() },
                onClose: { [weak self] in self?.hideNoteWindow() },
                onAttach: { [weak self] in self?.moveNote(to: .pane) }
            )
        }
        notepad.setVisible(true)
        applyScreenCapturePrivacy()
        notesPanel?.orderFrontRegardless()
        if focus {
            notesPanel?.makeKey()
            notesPanel?.editor.requestFocus()
        }
    }

    private func hideNoteWindow() {
        notepad.setVisible(false)
        notesPanel?.orderOut(nil)
    }

    /// The note bar's and note window's move buttons: same as Settings, but the note stays open.
    private func moveNote(to placement: NotePlacement) {
        setNotePlacement(placement)
        switch placement {
        case .window:
            showNoteWindow(focus: true)
        case .pane:
            notepad.setVisible(true)
            panel?.orderFrontRegardless()
        }
    }

    /// Settings → Note: moving the note closes it where it was.
    private func setNotePlacement(_ placement: NotePlacement) {
        guard placement != notepad.placement else { return }
        hideNoteWindow()
        notepad.setPlacement(placement)
    }

    // MARK: Reminders

    /// The header button and menu item: opens or closes the reminders window, or switches
    /// the calendar sticky to its Reminders tab and back.
    private func toggleReminders() {
        switch reminderSettings.placement {
        case .window:
            if reminderSettings.isVisible { hideRemindersWindow() } else { showRemindersWindow() }
        case .tab:
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
        applyScreenCapturePrivacy()
        remindersPanel?.orderFrontRegardless()
    }

    private func hideRemindersWindow() {
        reminderSettings.setVisible(false)
        remindersPanel?.orderOut(nil)
    }

    /// The first-open question: stay a tab (as they opened), or move to their own window.
    private func chooseReminderPlacement(_ placement: ReminderPlacement) {
        if placement == .window {
            reminderSettings.setVisible(false) // leave the tab
            reminderSettings.setPlacement(.window)
            showRemindersWindow()
        } else {
            reminderSettings.setPlacement(.tab)
        }
    }

    /// Settings → Reminders → Change Source: forget the source and show the chooser.
    private func changeReminderSource() {
        reminderSettings.setProvider(nil)
        reminderStore.use(nil)
        if !reminderSettings.isVisible { toggleReminders() }
    }

    /// Todoist, TickTick and To Do don't announce changes: look again every few minutes;
    /// Things every 30 seconds. A check still under way isn't doubled.
    private func scheduleReminderRefresh() {
        reminderRefresh = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reminderTicks += 1
                guard self.reminderSettings.isVisible, !self.reminderStore.isLoading else { return }
                if self.reminderSettings.provider == .things {
                    // A quit Things stays quit: only ⌘R starts it.
                    guard !NSRunningApplication.runningApplications(withBundleIdentifier: JXAThings.bundleID).isEmpty else { return }
                } else {
                    guard self.reminderTicks % 10 == 0 else { return }
                }
                Task { await self.reminderStore.reload() }
            }
        }
    }

    /// With notes kept in a folder, picks up edits made to the open note elsewhere (e.g. in
    /// Obsidian). Our own edits are saved as they're typed, so this changes nothing otherwise.
    private func watchNoteFolder() {
        noteFolderWatch = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.notepad.isVisible else { return }
                self.notepad.reloadFromFolder()
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

    /// Settings float like the stickies and join every Space, so they open over a full-screen
    /// app instead of switching away from it.
    private func showSettings() {
        if settingsWindow == nil {
            let window = UtilityPanel(contentViewController: NSHostingController(
                rootView: SettingsView(
                    store: store, settings: settings, notepad: notepad, hotKey: hotKey,
                    reminderStore: reminderStore, reminderSettings: reminderSettings, remindersHotKey: remindersHotKey,
                    onReminderPlacement: { [weak self] in self?.setReminderPlacement($0) },
                    onChangeReminderSource: { [weak self] in self?.changeReminderSource() },
                    onNotePlacement: { [weak self] in self?.setNotePlacement($0) },
                    onAbout: { [weak self] in self?.showAbout() },
                    onHidesFromScreenCapture: { [weak self] in self?.setHidesFromScreenCapture($0) },
                    updateChecker: updateChecker
                )
            ))
            window.title = "Sticky Calendar Settings"
            window.center()
            settingsWindow = window
        }
        applyScreenCapturePrivacy()
        settingsWindow?.orderFrontRegardless()
        settingsWindow?.makeKey()
    }

    private func showAbout() {
        if aboutWindow == nil {
            let window = UtilityPanel(contentViewController: NSHostingController(rootView: AboutView(updateChecker: updateChecker)))
            window.title = "About Sticky Calendar"
            window.center()
            aboutWindow = window
        }
        applyScreenCapturePrivacy()
        aboutWindow?.orderFrontRegardless()
        aboutWindow?.makeKey()
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

/// The Settings and About windows: floating, non-activating panels on every Space,
/// including over full-screen apps (an ordinary window would open on the desktop and switch away).
@MainActor
final class UtilityPanel: NSPanel {
    convenience init(contentViewController: NSViewController) {
        self.init(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        self.contentViewController = contentViewController
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    /// ⌘W closes it (there's no File menu to do it).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == [.command], event.charactersIgnoringModifiers?.lowercased() == "w" {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
