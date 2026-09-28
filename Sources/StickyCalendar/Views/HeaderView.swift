import StickyCalendarCore
import SwiftUI

struct HeaderView: View {
    let store: CalendarStore

    var body: some View {
        HStack(spacing: 8) {
            Text(store.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if !store.isViewingToday {
                Button("Today") { store.goToToday() }
                    .controlSize(.small)
            }
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
