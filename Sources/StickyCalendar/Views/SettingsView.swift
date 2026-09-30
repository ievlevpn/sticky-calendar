import ServiceManagement
import StickyCalendarCore
import SwiftUI

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

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Calendars") {
                if store.calendars.isEmpty {
                    Text("No calendars available.").foregroundStyle(.secondary)
                }
                ForEach(store.calendars) { calendar in
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

            Section("Appearance") {
                Slider(value: Binding(get: { settings.opacity }, set: settings.setOpacity), in: AppSettings.opacityRange) {
                    Text("Opacity")
                }
                Picker("Zoom", selection: Binding(get: { settings.zoom }, set: settings.setZoom)) {
                    ForEach(AppSettings.zoomSteps, id: \.self) { step in
                        Text(step.formatted(.percent)).tag(step)
                    }
                }
                .help("Size of the timeline and note. In the sticky: ⌘= bigger, ⌘- smaller, ⌘0 actual size.")
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
                Text("The stickies fade when the pointer isn't over them and you're not typing in them, and come back when you point at them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Hide from screen sharing and screenshots", isOn: Binding(
                    get: { settings.hidesFromScreenCapture }, set: onHidesFromScreenCapture
                ))
                Text("Asks macOS to leave Sticky Calendar's windows out of screen shares and screenshots. Some apps capture the screen in ways that may ignore this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section("Note") {
                Picker("Show the note", selection: Binding(get: { notepad.placement }, set: onNotePlacement)) {
                    Text("Under the timeline or reminders").tag(NotePlacement.pane)
                    Text("In its own sticky").tag(NotePlacement.window)
                }
                Toggle("A separate note for each day", isOn: Binding(get: { notepad.isPerDay }, set: notepad.setPerDay))
                Text(notepad.isPerDay
                     ? "The note follows the day you're viewing, like a journal."
                     : "One note, whichever day you're viewing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reminders") {
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
                Picker("Show reminders", selection: Binding(get: { reminderSettings.placement }, set: onReminderPlacement)) {
                    Text("In their own sticky").tag(ReminderPlacement.window)
                    Text("As a tab in this sticky").tag(ReminderPlacement.tab)
                }
                Picker("List", selection: Binding(get: { reminderSettings.mode }, set: reminderSettings.setMode)) {
                    Text("Today and overdue").tag(ReminderMode.today)
                    Text("Whole lists").tag(ReminderMode.lists)
                }
                Toggle("Show reminders completed today", isOn: Binding(
                    get: { reminderSettings.showsCompleted }, set: reminderSettings.setShowsCompleted
                ))
                if reminderStore.access == .granted {
                    ForEach(reminderStore.lists) { list in
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
                } else if reminderSettings.provider != nil {
                    Text("Lists appear here once Sticky Calendar may read your reminders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Shortcuts") {
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
                    Text("Works from any app. In the sticky: ⌘M compact, ⌘= / ⌘- zoom, ⌘, settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Updates") {
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
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updateChecker.automaticChecksEnabled },
                    set: updateChecker.setAutomaticChecks
                ))
                Button("Check Now") { Task { await updateChecker.checkNow() } }
                    .disabled(updateChecker.isDevelopmentBuild)
            }

            Section {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 700)
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
