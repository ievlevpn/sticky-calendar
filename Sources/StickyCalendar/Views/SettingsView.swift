import ServiceManagement
import StickyCalendarCore
import SwiftUI

struct SettingsView: View {
    let store: CalendarStore
    let settings: AppSettings
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
        .frame(width: 380, height: 600)
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
