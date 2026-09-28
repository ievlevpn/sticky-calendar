import StickyCalendarCore
import SwiftUI

struct AllDayStrip: View {
    let store: CalendarStore

    var body: some View {
        if !store.allDayEvents.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.allDayEvents) { item in
                        let color = Color(rgba: store.calendarInfo(id: item.calendarID)?.color ?? .fallback)
                        Text(item.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(color.opacity(0.3)))
                            .onTapGesture(count: 2) { SystemLinks.openInCalendar(item) }
                            .help("Double-click to open in Calendar")
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 4)
        }
    }
}
