import ServiceManagement
import StickyCalendarCore
import SwiftUI

struct SettingsView: View {
    let store: CalendarStore
    let settings: AppSettings
    let notepad: Notepad
    let hotKey: GlobalHotKey
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
                Toggle("A separate note for each day", isOn: Binding(get: { notepad.isPerDay }, set: notepad.setPerDay))
                Text(notepad.isPerDay
                     ? "The note follows the day you're viewing, like a journal."
                     : "One note, whichever day you're viewing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                Picker("Show or hide the sticky", selection: Binding(
                    get: { settings.globalHotKey },
                    set: { choice in
                        settings.setGlobalHotKey(choice)
                        hotKey.apply(choice)
                    }
                )) {
                    ForEach(GlobalHotKeyChoice.allCases, id: \.self) { Text($0.symbol).tag($0) }
                }
                if hotKey.failed {
                    Text("Another app already uses \(settings.globalHotKey.symbol). Choose another shortcut.")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Works from any app. In the sticky: ⌘M compact, ⌘= / ⌘- zoom, ⌘, settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Updates") {
                LabeledContent("Version", value: "\(AppVersion.short) (build \(AppVersion.build))")
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
