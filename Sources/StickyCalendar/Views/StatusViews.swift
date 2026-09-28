import StickyCalendarCore
import SwiftUI

struct AccessDeniedView: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Sticky Calendar needs full access to your calendars to show and edit today's events.")
                .font(.callout)
                .multilineTextAlignment(.center)
            Button("Open Privacy Settings") { SystemLinks.openPrivacySettings() }
            Spacer()
        }
        .padding(20)
    }
}

struct ErrorBanner: View {
    let store: CalendarStore

    var body: some View {
        if let message = store.lastError {
            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                .padding(10)
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(4))
                    if store.lastError == message { store.lastError = nil }
                }
        }
    }
}
