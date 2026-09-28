import ServiceManagement
import StickyCalendarCore
import SwiftUI

struct SettingsView: View {
    let store: CalendarStore
    let settings: AppSettings

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Visible hours") {
                Picker("From", selection: Binding(get: { settings.hourRange.start }, set: settings.setStartHour)) {
                    ForEach(0..<24, id: \.self) { Text(Self.hourLabel($0)).tag($0) }
                }
                Picker("To", selection: Binding(get: { settings.hourRange.end }, set: settings.setEndHour)) {
                    ForEach(1...24, id: \.self) { Text(Self.hourLabel($0)).tag($0) }
                }
            }

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

            Section {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 480)
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

    private static func hourLabel(_ hour: Int) -> String { String(format: "%02d:00", hour) }
}
