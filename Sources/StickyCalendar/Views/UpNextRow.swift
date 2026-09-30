import StickyCalendarCore
import SwiftUI

/// Joins an event's video call: a small camera button on event blocks and in compact mode.
struct JoinMeetingButton: View {
    let url: URL
    let color: Color
    var size: CGFloat = 9

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Image(systemName: "video.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, size * 0.6)
                .padding(.vertical, size * 0.35)
                .background(Capsule().fill(color))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Join meeting (\(url.host ?? url.scheme ?? "link"))")
    }
}

/// Compact mode's single line: the event on now, or the next one, with a countdown.
/// Clicking it expands the sticky again.
struct UpNextRow: View {
    let store: CalendarStore
    let onExpand: () -> Void

    var body: some View {
        // Every 15 s, so the progress fill moves smoothly through a meeting.
        SwiftUI.TimelineView(.periodic(from: .now, by: 15)) { context in
            let now = context.date
            let upNext = UpNext.pick(from: store.timedEvents, now: store.isViewingToday ? now : store.day)
            HStack(spacing: 8) {
                if let upNext {
                    let color = Color(rgba: store.calendarInfo(id: upNext.item.calendarID)?.color ?? .fallback)
                    RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(upNext.item.title.isEmpty ? "New Event" : upNext.item.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(detail(upNext, now: now))
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let url = MeetingLink.find(in: upNext.item) {
                        JoinMeetingButton(url: url, color: color, size: 10)
                    }
                } else {
                    Text(store.timedEvents.isEmpty ? "No events" : "Nothing else today")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(alignment: .leading) { progressFill(upNext, now: now) }
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpand)
            .help("Click to expand (⌘M)")
        }
    }

    /// The event on now fills the row with its colour, left to right, as it goes: empty
    /// when it starts, full when it ends. Nothing before it starts.
    @ViewBuilder
    private func progressFill(_ upNext: UpNext?, now: Date) -> some View {
        if let upNext, upNext.isOngoing, store.isViewingToday {
            let color = Color(rgba: store.calendarInfo(id: upNext.item.calendarID)?.color ?? .fallback)
            GeometryReader { geo in
                Rectangle()
                    .fill(color.opacity(0.28))
                    .frame(width: geo.size.width * upNext.progress(at: now))
                    .animation(.easeInOut(duration: 0.6), value: upNext.progress(at: now))
            }
            .allowsHitTesting(false)
        }
    }

    /// "Now · until 16:15", "17:30 · in 1 h 12 min", or just the time on another day.
    private func detail(_ upNext: UpNext, now: Date) -> String {
        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        if upNext.isOngoing { return "Now · until \(time(upNext.item.end))" }
        guard store.isViewingToday else { return time(upNext.item.start) }
        let minutes = Int(upNext.item.start.timeIntervalSince(now) / 60) + 1
        let wait = Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return "\(time(upNext.item.start)) · in \(wait)"
    }
}
