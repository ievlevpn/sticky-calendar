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

/// "Version 1.2.3 is available" under the header, with Update and a close button. Closed,
/// it stays away until a newer release.
struct UpdateBanner: View {
    let updateChecker: UpdateChecker

    var body: some View {
        if let info = updateChecker.announcedRelease {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
                Text("Version \(info.version.description) is available")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Button("Update") { UpdateActions.getUpdate(info) }
                    .controlSize(.small)
                    .fixedSize()
                    .focusable(false)
                Button {
                    withAnimation { updateChecker.dismissAnnouncement() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Hide until the next version")
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.12))
            .overlay(alignment: .bottom) { Divider() }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
