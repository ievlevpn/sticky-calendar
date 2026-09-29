import StickyCalendarCore
import SwiftUI

struct HeaderView: View {
    let store: CalendarStore
    let settings: AppSettings
    let isNoteVisible: Bool
    let onToggleNote: () -> Void
    let onTogglePin: () -> Void
    let onToggleCompact: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Drops the weekday, then the month, when a narrow window can't fit them.
            ViewThatFits(in: .horizontal) {
                dayTitle(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                dayTitle(.dateTime.day().month(.abbreviated))
                dayTitle(.dateTime.day())
            }
            .layoutPriority(1)
            Button { store.goToDay(offset: -1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .help("Previous day")
            Button { store.goToDay(offset: 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .help("Next day")
            Spacer()
            if store.offersJumpToNow {
                Button { store.jumpToNow() } label: { Image(systemName: "clock.arrow.circlepath") }
                    .buttonStyle(.borderless)
                    .help("Jump to now")
            }
            if !settings.isCompact {
                Button(action: onToggleNote) {
                    Image(systemName: isNoteVisible ? "note.text" : "note")
                }
                .buttonStyle(.borderless)
                .help(isNoteVisible ? "Hide note" : "Show note")
            }
            Button { CalendarJump.perform(day: store.day, settings: settings, store: store) } label: {
                Image(systemName: "calendar")
            }
            .buttonStyle(.borderless)
            .help("Open in Calendar (⌘O)")
            Button(action: onTogglePin) {
                Image(systemName: settings.isPinned ? "pin.fill" : "pin.slash")
            }
            .buttonStyle(.borderless)
            .help(settings.isPinned ? "Unpin: behave like a normal window (⌃S)" : "Pin: keep on top of other windows (⌃S)")
            Button(action: onToggleCompact) {
                Image(systemName: settings.isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
            }
            .buttonStyle(.borderless)
            .help(settings.isCompact ? "Expand (⌘M, or double-click here)" : "Compact: just what's next (⌘M, or double-click here)")
            Button(action: onSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings (⌘,)")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        // Double-clicking the bar collapses or expands, like a title bar.
        .background(Color.clear.contentShape(Rectangle()).onTapGesture(count: 2, perform: onToggleCompact))
        // SwiftUI extends the timeline's scroll view up under the header (it insets the
        // content by the header height), so the header needs its own bar material.
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func dayTitle(_ format: Date.FormatStyle) -> some View {
        Text(store.day.formatted(format))
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
    }
}
