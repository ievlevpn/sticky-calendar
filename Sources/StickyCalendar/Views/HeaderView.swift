import StickyCalendarCore
import SwiftUI

/// The sticky's header: the date and day arrows (or "Reminders" in the Reminders tab), and a
/// ••• button that unfurls the actions into a glass capsule on hover ("Unfurl", design 1a).
struct HeaderView: View {
    let store: CalendarStore
    let settings: AppSettings
    let reminderSettings: ReminderSettings
    let isNoteVisible: Bool
    let onToggleNote: () -> Void
    let onToggleReminders: () -> Void
    /// Refreshes what's showing: the calendar, or the Reminders tab.
    let onRefresh: () -> Void
    let isRefreshing: Bool
    let onTogglePin: () -> Void
    let onToggleCompact: () -> Void
    let onSettings: () -> Void

    @State private var isOpen = false
    /// Clicking ••• keeps the capsule open until it's clicked again.
    @State private var isLocked = false
    @State private var hovered: HeaderAction?
    @State private var pointerInside = false
    @State private var closing: Task<Void, Never>?
    @State private var width: CGFloat = 360

    /// The reminders window is open, or the Reminders tab is showing.
    private var isRemindersOpen: Bool { reminderSettings.isVisible }
    private var showsRemindersTab: Bool { reminderSettings.placement == .tab && isRemindersOpen }

    var body: some View {
        HStack(spacing: 8) {
            leading
                // The capsule takes the header's width while it's open.
                .opacity(isOpen ? 0 : 1)
                .blur(radius: isOpen ? 2 : 0)
                .offset(x: isOpen ? -6 : 0)
                .animation(.easeOut(duration: 0.22), value: isOpen)
                .allowsHitTesting(!isOpen)
            Spacer(minLength: 0)
            moreButton
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // Double-clicking the bar collapses or expands, like a title bar.
        .background(Color.clear.contentShape(Rectangle()).onTapGesture(count: 2, perform: onToggleCompact))
        // SwiftUI extends the timeline's scroll view up under the header (it insets the
        // content by the header height), so the header needs its own bar material.
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .overlay(alignment: .bottomTrailing) { label }
    }

    // MARK: Leading side

    @ViewBuilder
    private var leading: some View {
        if showsRemindersTab {
            Text("Reminders").font(.system(size: 13, weight: .semibold)).lineLimit(1)
        } else {
            HStack(spacing: 8) {
                // Drops the weekday, then the month, when a narrow window can't fit them.
                ViewThatFits(in: .horizontal) {
                    dayTitle(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    dayTitle(.dateTime.day().month(.abbreviated))
                    dayTitle(.dateTime.day())
                }
                Button { store.goToDay(offset: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .help("Previous day")
                Button { store.goToDay(offset: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                    .help("Next day")
                if store.offersJumpToNow {
                    Button { store.jumpToNow() } label: { Image(systemName: "clock.arrow.circlepath") }
                        .buttonStyle(.borderless)
                        .help("Jump to now")
                }
            }
        }
    }

    private func dayTitle(_ format: Date.FormatStyle) -> some View {
        Text(store.day.formatted(format))
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: The unfurling menu

    /// Most used first: the ones nearest the pointer.
    private var actions: [HeaderAction] {
        HeaderAction.allCases.filter { !($0 == .note && (settings.isCompact || showsRemindersTab)) }
    }

    private static let itemSize: CGFloat = 24

    /// Distance between icons: 26, tighter when the window is too narrow for the capsule.
    private var step: CGFloat {
        let room = width - 24 - 4 - 30 // side padding, the capsule's overhang, the ••• end
        return min(26, max(20, room / CGFloat(actions.count)))
    }

    private var capsuleWidth: CGFloat { 30 + step * CGFloat(actions.count) }

    private var moreButton: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .bold))
            .rotationEffect(.degrees(isOpen ? 90 : 0))
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isOpen)
            .foregroundStyle(isLocked ? Color.accentColor : Color.primary)
            .frame(width: 22, height: 24)
            .contentShape(Rectangle())
            .onTapGesture { toggleLock() }
            .help(isLocked ? "Close the menu" : "Keep the menu open")
            .accessibilityElement()
            .accessibilityLabel("More")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleLock() }
            .onHover(perform: pointer)
            .background(alignment: .trailing) { capsule }
    }

    /// The glass capsule, growing left out of the ••• button, with the actions inside.
    private var capsule: some View {
        ZStack(alignment: .trailing) {
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                .shadow(color: .black.opacity(isOpen ? 0.25 : 0), radius: 8, y: 4)
                .frame(width: isOpen ? capsuleWidth : 28, height: 28)
                .opacity(isOpen ? 1 : 0)
                .animation(.spring(response: 0.42, dampingFraction: 0.68), value: isOpen)
            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                item(action, index: index)
                    // From the capsule's end: past the ••• end, then one step per icon.
                    .padding(.trailing, 30 + CGFloat(index) * step + (step - Self.itemSize) / 2)
            }
        }
        .frame(width: capsuleWidth, height: 28, alignment: .trailing)
        .offset(x: 4) // overhangs the ••• button a little, as in the design
        .allowsHitTesting(isOpen)
        .onHover(perform: pointer)
    }

    private func item(_ action: HeaderAction, index: Int) -> some View {
        let count = actions.count
        let delay = isOpen ? Double(index) * 0.028 : Double(count - 1 - index) * 0.012
        let active = isActive(action)
        return Button { perform(action) } label: {
            Group {
                if action == .refresh && isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: action.symbol(active: active))
                        .font(.system(size: 12.5, weight: .medium))
                }
            }
            .frame(width: Self.itemSize, height: Self.itemSize)
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .background(Circle().fill(Color.primary.opacity(hovered == action ? 0.12 : 0)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(for: action).name)
        .onHover { inside in
            if inside { hovered = action } else if hovered == action { hovered = nil }
        }
        .opacity(isOpen ? 1 : 0)
        .blur(radius: isOpen ? 0 : 3)
        .scaleEffect(isOpen ? 1 : 0.5)
        .offset(x: isOpen ? 0 : 14)
        .animation(.spring(response: 0.42, dampingFraction: 0.68).delay(delay), value: isOpen)
    }

    /// The hovered action's name and shortcut, under the capsule.
    private var label: some View {
        let text = hovered.map { label(for: $0) }
        return HStack(spacing: 6) {
            Text(text?.name ?? "").fontWeight(.semibold)
            if let key = text?.shortcut, !key.isEmpty {
                Text(key).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(.regularMaterial).shadow(color: .black.opacity(0.2), radius: 6, y: 3))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
        .opacity(isOpen && hovered != nil ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: hovered)
        .animation(.easeOut(duration: 0.15), value: isOpen)
        .padding(.trailing, 8)
        .offset(y: 24) // just below the header, over the timeline
        .allowsHitTesting(false)
    }

    // MARK: Behaviour

    /// Opens while the pointer is over the button or the capsule; closes shortly after it
    /// leaves both (unless locked open).
    private func pointer(_ inside: Bool) {
        pointerInside = inside
        closing?.cancel()
        if inside {
            isOpen = true
        } else {
            closing = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled, !pointerInside else { return }
                hovered = nil
                if !isLocked { isOpen = false }
            }
        }
    }

    private func toggleLock() {
        isLocked.toggle()
        isOpen = isLocked || pointerInside
    }

    private func perform(_ action: HeaderAction) {
        switch action {
        case .reminders: onToggleReminders()
        case .note: onToggleNote()
        case .pin: onTogglePin()
        case .refresh: onRefresh()
        case .calendar: CalendarJump.perform(day: store.day, settings: settings, store: store)
        case .compact: onToggleCompact()
        case .settings: onSettings()
        }
    }

    private func isActive(_ action: HeaderAction) -> Bool {
        switch action {
        case .reminders: isRemindersOpen
        case .note: isNoteVisible
        case .pin: settings.isPinned
        case .compact: settings.isCompact
        case .refresh, .calendar, .settings: false
        }
    }

    private func label(for action: HeaderAction) -> (name: String, shortcut: String) {
        switch action {
        case .reminders:
            (showsRemindersTab ? "Back to the calendar" : isRemindersOpen ? "Hide reminders" : "Show reminders",
             reminderSettings.hotKey == .off ? "" : reminderSettings.hotKey.symbol)
        case .note: (isNoteVisible ? "Hide note" : "Show note", "")
        case .pin: (settings.isPinned ? "Unpin" : "Pin on top", "⌃S")
        case .refresh: ("Refresh", "⌘R")
        case .calendar: ("Open in Calendar", "⌘O")
        case .compact: (settings.isCompact ? "Expand" : "Compact", "⌘M")
        case .settings: ("Settings", "⌘,")
        }
    }
}

/// The header's actions, most used first.
enum HeaderAction: CaseIterable, Hashable {
    case reminders, note, pin, refresh, calendar, compact, settings

    func symbol(active: Bool) -> String {
        switch self {
        case .reminders: active ? "checklist.checked" : "checklist"
        case .note: active ? "note.text" : "note"
        case .pin: active ? "pin.fill" : "pin.slash"
        case .refresh: "arrow.clockwise"
        case .calendar: "calendar"
        case .compact: active ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
        case .settings: "gearshape"
        }
    }
}
