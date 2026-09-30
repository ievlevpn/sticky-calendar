import AppKit
import ServiceManagement
import StickyCalendarCore
import SwiftUI

/// Settings, in tabs. Typing in the search field shows every matching setting from all
/// tabs at once, matched loosely ("fde" finds "Fade when idle").
struct SettingsView: View {
    let store: CalendarStore
    let settings: AppSettings
    let notepad: Notepad
    let hotKey: GlobalHotKey
    let reminderStore: ReminderStore
    let reminderSettings: ReminderSettings
    let remindersHotKey: GlobalHotKey
    let onReminderPlacement: (ReminderPlacement) -> Void
    let onChangeReminderSource: () -> Void
    let onNotePlacement: (NotePlacement) -> Void
    let onAbout: () -> Void
    let onHidesFromScreenCapture: (Bool) -> Void
    let updateChecker: UpdateChecker

    @State private var tab = SettingsTab.general
    @State private var query = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 8)
            if isSearching {
                results
            } else {
                Picker("", selection: $tab) {
                    ForEach(SettingsTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 20)
                Form {
                    ForEach(items.filter { $0.tab == tab }) { $0.content }
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 480, height: 600)
    }

    // MARK: Search

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search settings", text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onExitCommand { query = "" }
            if isSearching {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.borderless)
                    .help("Clear the search (Esc)")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
        .background(Button("") { isSearchFocused = true }.keyboardShortcut("f").hidden())
    }

    /// Matching settings, best first, under the name of their tab.
    @ViewBuilder
    private var results: some View {
        let matches = SettingsSearch.rank(items, query: query) { [$0.title] + $0.keywords }
        if matches.isEmpty {
            VStack {
                Spacer()
                Text("No settings match “\(query)”.").foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            Form {
                ForEach(SettingsTab.allCases) { tab in
                    let inTab = matches.filter { $0.tab == tab }
                    if !inTab.isEmpty {
                        Section(tab.title) {
                            ForEach(inTab) { $0.content }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: The settings

    /// Every setting, in the order it appears in its tab.
    private var items: [SettingItem] {
        var items: [SettingItem] = []
        func add(_ tab: SettingsTab, _ title: String, _ keywords: [String] = [], @ViewBuilder _ content: () -> some View) {
            items.append(SettingItem(id: "\(tab.rawValue).\(items.count)", tab: tab, title: title, keywords: keywords,
                                     content: AnyView(content())))
        }

        // General
        add(.general, "Opacity", ["transparency", "see through", "appearance"]) {
            Slider(value: Binding(get: { settings.opacity }, set: settings.setOpacity), in: AppSettings.opacityRange) {
                Text("Opacity")
            }
        }
        add(.general, "Zoom", ["size", "bigger", "smaller", "text size", "scale"]) {
            Picker("Zoom", selection: Binding(get: { settings.zoom }, set: settings.setZoom)) {
                ForEach(AppSettings.zoomSteps, id: \.self) { step in
                    Text(step.formatted(.percent)).tag(step)
                }
            }
            .help("Size of the timeline and note. In the sticky: ⌘= bigger, ⌘- smaller, ⌘0 actual size.")
        }
        add(.general, "Fade when idle", ["fade after", "fade by", "dim", "transparent", "inactive", "opacity"]) {
            fadeWhenIdle
        }
        add(.general, "Hide from screen sharing and screenshots", ["privacy", "capture", "zoom call", "record"]) {
            Toggle("Hide from screen sharing and screenshots", isOn: Binding(
                get: { settings.hidesFromScreenCapture }, set: onHidesFromScreenCapture
            ))
            caption("Asks macOS to leave Sticky Calendar's windows out of screen shares and screenshots. Some apps capture the screen in ways that may ignore this.")
        }
        add(.general, "Launch at login", ["startup", "start automatically", "login items"]) {
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
        }

        // Calendars
        add(.calendars, "Calendar button", ["open in calendar", "calendar app", "same day"]) {
            Picker("Calendar button", selection: Binding<CalendarJumpMode?>(
                get: { settings.calendarJumpMode },
                set: { if let mode = $0 { settings.setCalendarJumpMode(mode) } }
            )) {
                if settings.calendarJumpMode == nil {
                    Text("Ask on first use").tag(CalendarJumpMode?.none)
                }
                Text("Show the same day").tag(CalendarJumpMode?.some(.sameDay))
                Text("Just open Calendar").tag(CalendarJumpMode?.some(.justOpen))
            }
        }
        if store.calendars.isEmpty {
            add(.calendars, "Calendars", ["show", "hide"]) {
                Text("No calendars available.").foregroundStyle(.secondary)
            }
        }
        for calendar in store.calendars {
            add(.calendars, calendar.title, ["calendar", "show", "hide"]) {
                Toggle(isOn: Binding(
                    get: { !settings.hiddenCalendarIDs.contains(calendar.id) },
                    set: { visible in
                        settings.setCalendar(calendar.id, visible: visible)
                        store.reload()
                    }
                )) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(rgba: calendar.color)).frame(width: 9, height: 9)
                        Text(calendar.title)
                    }
                }
            }
        }

        // Note
        add(.note, "Show the note", ["placement", "own sticky", "window", "under the timeline"]) {
            Picker("Show the note", selection: Binding(get: { notepad.placement }, set: onNotePlacement)) {
                Text("Under the timeline or reminders").tag(NotePlacement.pane)
                Text("In its own sticky").tag(NotePlacement.window)
            }
        }
        add(.note, "A separate note for each day", ["per day", "journal", "daily"]) {
            Toggle("A separate note for each day", isOn: Binding(get: { notepad.isPerDay }, set: notepad.setPerDay))
            caption(notepad.isPerDay
                    ? "The note follows the day you're viewing, like a journal."
                    : "One note, whichever day you're viewing.")
        }
        add(.note, "Keep notes in a folder", ["markdown", "md", "files", "obsidian", "vault", "save", "export"]) {
            noteFolder
        }

        // Reminders
        add(.reminders, "Source", ["apple reminders", "todoist", "ticktick", "obsidian", "tasks"]) {
            LabeledContent("Source") {
                HStack {
                    Text(reminderSettings.provider?.name ?? "Not chosen yet")
                        .foregroundStyle(reminderSettings.provider == nil ? .secondary : .primary)
                    if reminderSettings.provider == .obsidian, let vault = reminderSettings.obsidianVaultPath {
                        Text("· \((vault as NSString).lastPathComponent)").foregroundStyle(.secondary)
                    }
                    Button(reminderSettings.provider == nil ? "Choose…" : "Change Source…", action: onChangeReminderSource)
                }
            }
        }
        add(.reminders, "Show reminders", ["placement", "tab", "own sticky", "window"]) {
            Picker("Show reminders", selection: Binding(get: { reminderSettings.placement }, set: onReminderPlacement)) {
                Text("In their own sticky").tag(ReminderPlacement.window)
                Text("As a tab in this sticky").tag(ReminderPlacement.tab)
            }
        }
        add(.reminders, "List", ["today", "overdue", "whole lists", "mode"]) {
            Picker("List", selection: Binding(get: { reminderSettings.mode }, set: reminderSettings.setMode)) {
                Text("Today and overdue").tag(ReminderMode.today)
                Text("Whole lists").tag(ReminderMode.lists)
            }
        }
        add(.reminders, "Show reminders completed today", ["done", "ticked", "completed"]) {
            Toggle("Show reminders completed today", isOn: Binding(
                get: { reminderSettings.showsCompleted }, set: reminderSettings.setShowsCompleted
            ))
        }
        if reminderStore.access == .granted {
            for list in reminderStore.lists {
                add(.reminders, list.title, ["list", "show", "hide"]) {
                    Toggle(isOn: Binding(
                        get: { !reminderSettings.hiddenListIDs.contains(list.id) },
                        set: { reminderSettings.setList(list.id, visible: $0) }
                    )) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(rgba: list.color)).frame(width: 9, height: 9)
                            Text(list.title)
                        }
                    }
                }
            }
        } else if reminderSettings.provider != nil {
            add(.reminders, "Lists", ["show", "hide"]) {
                caption("Lists appear here once Sticky Calendar may read your reminders.")
            }
        }

        // Shortcuts
        add(.shortcuts, "Show or hide the sticky", ["hotkey", "keyboard", "global shortcut"]) {
            Picker("Show or hide the sticky", selection: Binding(
                get: { settings.globalHotKey },
                set: { choice in
                    settings.setGlobalHotKey(choice)
                    hotKey.apply(choice.carbonKey)
                }
            )) {
                ForEach(GlobalHotKeyChoice.allCases, id: \.self) { Text($0.symbol).tag($0) }
            }
            if hotKey.failed {
                Text("Another app already uses \(settings.globalHotKey.symbol). Choose another shortcut.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        add(.shortcuts, "Show or hide reminders", ["hotkey", "keyboard", "global shortcut"]) {
            Picker("Show or hide reminders", selection: Binding(
                get: { reminderSettings.hotKey },
                set: { choice in
                    reminderSettings.setHotKey(choice)
                    remindersHotKey.apply(choice.carbonKey)
                }
            )) {
                ForEach(RemindersHotKeyChoice.allCases, id: \.self) { Text($0.symbol).tag($0) }
            }
            if remindersHotKey.failed {
                Text("Another app already uses \(reminderSettings.hotKey.symbol). Choose another shortcut.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                caption("Works from any app. In the sticky: ⌘M compact, ⌘= / ⌘- zoom, ⌘, settings.")
            }
        }

        // Updates
        add(.updates, "Version", ["about", "build"]) {
            LabeledContent("Version") {
                HStack {
                    Text("\(AppVersion.short) (build \(AppVersion.build))")
                    Button("About…", action: onAbout)
                }
            }
            Text(updateChecker.summary).foregroundStyle(.secondary)
            if case .available(let info) = updateChecker.status {
                Button("Get Version \(info.version.description)…") { UpdateActions.getUpdate(info) }
            }
        }
        add(.updates, "Check for updates automatically", ["update", "new version"]) {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updateChecker.automaticChecksEnabled },
                set: updateChecker.setAutomaticChecks
            ))
        }
        add(.updates, "Check now", ["update", "new version"]) {
            Button("Check Now") { Task { await updateChecker.checkNow() } }
                .disabled(updateChecker.isDevelopmentBuild)
        }
        return items
    }

    // MARK: Parts

    @ViewBuilder
    private var fadeWhenIdle: some View {
        Toggle("Fade when idle", isOn: Binding(get: { settings.fadesWhenIdle }, set: settings.setFadesWhenIdle))
        if settings.fadesWhenIdle {
            Picker("Fade after", selection: Binding(get: { settings.idleFadeDelay }, set: settings.setIdleFadeDelay)) {
                ForEach(AppSettings.idleFadeDelays, id: \.self) { seconds in
                    Text(Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
                        .tag(seconds)
                }
            }
            Slider(value: Binding(get: { settings.idleFadeAmount }, set: settings.setIdleFadeAmount),
                   in: AppSettings.idleFadeAmountRange) {
                Text("Fade by")
            } minimumValueLabel: {
                Text("A little").font(.caption)
            } maximumValueLabel: {
                Text("Almost gone").font(.caption)
            }
        }
        caption("The stickies fade when the pointer isn't over them and you're not typing in them, and come back when you point at them.")
    }

    @ViewBuilder
    private var noteFolder: some View {
        Picker("Keep notes", selection: Binding(
            get: { notepad.folderPath != nil },
            set: { inFolder in
                if inFolder { chooseNoteFolder() } else { notepad.setFolder(nil) }
            }
        )) {
            Text("In Sticky Calendar").tag(false)
            Text("As Markdown files in a folder").tag(true)
        }
        if let folder = notepad.folderPath {
            LabeledContent("Folder") {
                HStack {
                    Text((folder as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(folder)
                    Button("Change…", action: chooseNoteFolder)
                    Button("Show") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder) }
                }
            }
            if let error = notepad.saveError {
                Text("Couldn't save the note: \(error)").font(.caption).foregroundStyle(.red)
            }
        }
        caption(notepad.folderPath == nil
                ? "Or keep them as .md files, e.g. in an Obsidian vault. Existing notes are copied there."
                : "Each day's note is a file like 2026-09-30.md (as Obsidian's daily notes); a single note is “\(Notepad.singleNoteFileName)”. Edits made to them elsewhere show up here.")
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Actions

    private func chooseNoteFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Keep Notes Here"
        panel.message = "Choose a folder for your notes, e.g. your Obsidian vault's daily notes folder. Notes already in Sticky Calendar are copied there (existing files are left as they are)."
        if let current = notepad.folderPath { panel.directoryURL = URL(fileURLWithPath: current) }
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        notepad.setFolder(url.path)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, calendars, note, reminders, shortcuts, updates

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .calendars: "Calendars"
        case .note: "Note"
        case .reminders: "Reminders"
        case .shortcuts: "Shortcuts"
        case .updates: "Updates"
        }
    }
}

/// One setting: where it lives, the words it's found by, and its controls.
struct SettingItem: Identifiable {
    let id: String
    let tab: SettingsTab
    let title: String
    let keywords: [String]
    let content: AnyView
}
