import StickyCalendarCore
import SwiftUI

/// Root of the sticky window. First version: header plus a plain list of today's
/// timed events, to prove the window and EventKit plumbing end to end.
struct StickyContentView: View {
    let store: CalendarStore
    let settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(store: store)
            switch store.access {
            case .granted:
                List(store.timedEvents) { item in
                    Text("\(item.start.formatted(date: .omitted, time: .shortened))  \(item.title)")
                }
                .scrollContentBackground(.hidden)
            case .notDetermined:
                Spacer()
                Text("Waiting for Calendar access…").foregroundStyle(.secondary)
                Spacer()
            case .denied:
                AccessDeniedView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground().opacity(settings.opacity))
        .overlay(alignment: .bottom) { ErrorBanner(store: store) }
        .ignoresSafeArea()
    }
}
