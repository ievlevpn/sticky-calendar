import StickyCalendarCore
import SwiftUI

struct HeaderView: View {
    let store: CalendarStore
    let settings: AppSettings
    let onTogglePin: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(store.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if store.offersJumpToNow {
                Button { store.jumpToNow() } label: { Image(systemName: "clock.arrow.circlepath") }
                    .buttonStyle(.borderless)
                    .help("Jump to now")
            }
            Button(action: onTogglePin) {
                Image(systemName: settings.isPinned ? "pin.fill" : "pin.slash")
            }
            .buttonStyle(.borderless)
            .help(settings.isPinned ? "Unpin: behave like a normal window (⌃S)" : "Pin: keep on top of other windows (⌃S)")
            Button { store.goToDay(offset: -1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .help("Previous day")
            Button { store.goToDay(offset: 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .help("Next day")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }
}
