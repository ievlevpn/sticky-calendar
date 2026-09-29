import StickyCalendarCore
import SwiftUI

struct HeaderView: View {
    let store: CalendarStore
    let settings: AppSettings
    let isNoteVisible: Bool
    let onToggleNote: () -> Void
    let onTogglePin: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(store.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 13, weight: .semibold))
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
            Button(action: onToggleNote) {
                Image(systemName: isNoteVisible ? "note.text" : "note")
            }
            .buttonStyle(.borderless)
            .help(isNoteVisible ? "Hide note" : "Show note")
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
            Button(action: onSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings (⌘,)")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        // SwiftUI extends the timeline's scroll view up under the header (it insets the
        // content by the header height), so the header needs its own bar material.
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}
