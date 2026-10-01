import AppKit
import StickyCalendarCore
import SwiftUI

/// The sticky's header. The date is the control (design 2b): click it for a month picker,
/// scroll over it to step through days, and a "Today" chip brings you back. The actions sit
/// behind a ••• button that unfurls on hover (design 1a). In the Reminders tab, "Reminders"
/// replaces the date; compact, a chip with the mode and how many are open (design 3c).
struct HeaderView: View {
    let store: CalendarStore
    let settings: AppSettings
    let reminderSettings: ReminderSettings
    /// Open reminders, for the compact Reminders tab's chip.
    let compactReminderCount: Int
    let isNoteVisible: Bool
    let onToggleNote: () -> Void
    let onToggleReminders: () -> Void
    /// Refreshes what's showing: the calendar, or the Reminders tab.
    let onRefresh: () -> Void
    let isRefreshing: Bool
    let onTogglePin: () -> Void
    let onToggleCompact: () -> Void
    let onSettings: () -> Void

    @State private var isMenuOpen = false
    @State private var isPickingDay = false
    @State private var width: CGFloat = 360

    /// The reminders window is open, or the Reminders tab is showing.
    private var isRemindersOpen: Bool { reminderSettings.isVisible }
    private var showsRemindersTab: Bool { reminderSettings.placement == .tab && isRemindersOpen }
    private var isCompact: Bool { settings.isCompact }

    var body: some View {
        HStack(spacing: 6) {
            leading.fadedWhileMenuOpen(isMenuOpen)
            Spacer(minLength: 0)
            UnfurlMenu(items: items, availableWidth: width, isOpen: $isMenuOpen)
        }
        .padding(.leading, showsRemindersTab && !isCompact ? 12 : 6)
        .padding(.trailing, 12)
        .frame(height: 32)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // Double-clicking the bar collapses or expands, like a title bar; dragging it moves the window.
        .background(TitleBarArea(onDoubleClick: onToggleCompact))
        // SwiftUI extends the timeline's scroll view up under the header (it insets the
        // content by the header height), so the header needs its own bar material.
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: The date

    @ViewBuilder
    private var leading: some View {
        if showsRemindersTab && isCompact {
            remindersChip
        } else if showsRemindersTab {
            Text("Reminders").font(.system(size: 13, weight: .semibold)).lineLimit(1)
        } else {
            HStack(spacing: 6) {
                dateButton
                if !store.isViewingToday || store.offersJumpToNow {
                    backToToday
                }
            }
        }
    }

    /// "Today 3": what the compact reminders flip through. Click to switch Today and Lists.
    private var remindersChip: some View {
        let isToday = reminderSettings.mode == .today
        return Button { reminderSettings.setMode(isToday ? .lists : .today) } label: {
            HStack(spacing: 4) {
                Text(isToday ? "Today" : "Lists").font(.system(size: 13, weight: .semibold))
                if compactReminderCount > 0 {
                    Text("\(compactReminderCount)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(isToday ? "Showing today's reminders. Click for all lists." : "Showing all lists. Click for today's.")
    }

    /// The date as a button: click for the month picker, scroll to step a day at a time.
    private var dateButton: some View {
        Button { isPickingDay.toggle() } label: {
            HStack(spacing: 4) {
                // Drops the weekday, then the month, when a narrow window can't fit them.
                ViewThatFits(in: .horizontal) {
                    dayTitle(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    dayTitle(.dateTime.day().month(.abbreviated))
                    dayTitle(.dateTime.day())
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Choose a day (or scroll over the date; ←/→)")
        .overlay(ScrollWheelCatcher { steps in store.goToDay(offset: steps) })
        .popover(isPresented: $isPickingDay, arrowEdge: .bottom) {
            MonthPicker(selected: store.day) { day in
                store.goTo(day)
                isPickingDay = false
            }
        }
    }

    private func dayTitle(_ format: Date.FormatStyle) -> some View {
        Text(store.day.formatted(format))
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
    }

    /// "‹ Today" (or "Today ›") on another day; "Now" on today when now is scrolled away.
    private var backToToday: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let label = store.isViewingToday ? "Now" : "Today"
        let arrow = store.isViewingToday ? nil : (store.day > today ? "chevron.left" : "chevron.right")
        return Button { store.jumpToNow() } label: {
            HStack(spacing: 3) {
                if let arrow, arrow == "chevron.left" { Image(systemName: arrow).font(.system(size: 8, weight: .bold)) }
                Text(label).font(.system(size: 11, weight: .semibold))
                if let arrow, arrow == "chevron.right" { Image(systemName: arrow).font(.system(size: 8, weight: .bold)) }
            }
            .foregroundStyle(Color.red)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule().fill(Color.red.opacity(0.15)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(store.isViewingToday ? "Jump to now" : "Back to today")
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    // MARK: The menu

    /// Most used first: the ones nearest the pointer.
    private var items: [UnfurlItem] {
        var items = [
            UnfurlItem(
                id: "reminders", symbol: isRemindersOpen ? "checklist.checked" : "checklist", isActive: isRemindersOpen,
                name: showsRemindersTab ? "Back to the calendar" : isRemindersOpen ? "Hide reminders" : "Show reminders",
                shortcut: reminderSettings.hotKey == .off ? "" : reminderSettings.hotKey.symbol,
                action: onToggleReminders
            ),
        ]
        if !isCompact {
            items.append(UnfurlItem(id: "note", symbol: isNoteVisible ? "note.text" : "note", isActive: isNoteVisible,
                                    name: isNoteVisible ? "Hide note" : "Show note", action: onToggleNote))
        }
        items += [
            UnfurlItem(id: "pin", symbol: settings.isPinned ? "pin.fill" : "pin.slash", isActive: settings.isPinned,
                       name: settings.isPinned ? "Unpin" : "Pin on top", shortcut: "⌃S", action: onTogglePin),
            UnfurlItem(id: "refresh", symbol: "arrow.clockwise", isBusy: isRefreshing, name: "Refresh", shortcut: "⌘R",
                       action: onRefresh),
        ]
        if showsRemindersTab {
            if let provider = reminderSettings.provider {
                items.append(UnfurlItem(id: "reminders-app", symbol: "arrow.up.forward.app", name: "Open \(provider.appName)",
                                        shortcut: "⌘O") { SystemLinks.openReminderSource(reminderSettings) })
            }
        } else {
            items.append(UnfurlItem(id: "calendar", symbol: "calendar", name: "Open in Calendar", shortcut: "⌘O") {
                CalendarJump.perform(day: store.day, settings: settings, store: store)
            })
        }
        items += [
            UnfurlItem(id: "compact",
                       symbol: isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                       isActive: isCompact, name: isCompact ? "Expand" : "Compact", shortcut: "⌘M",
                       action: onToggleCompact),
            UnfurlItem(id: "settings", symbol: "gearshape", name: "Settings", shortcut: "⌘,", action: onSettings),
        ]
        return items
    }
}

/// A small month calendar: pick a day. Today has a red ring; the shown day is filled.
struct MonthPicker: View {
    let selected: Date
    let onPick: (Date) -> Void

    @State private var month: Date
    private let calendar = Calendar.autoupdatingCurrent

    init(selected: Date, onPick: @escaping (Date) -> Void) {
        self.selected = selected
        self.onPick = onPick
        _month = State(initialValue: selected)
    }

    var body: some View {
        let days = MonthGrid.days(of: month, calendar: calendar)
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Text(month.formatted(.dateTime.month(.wide))).font(.system(size: 13, weight: .bold))
                Text(month.formatted(.dateTime.year())).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).help("Previous month")
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless).help("Next month")
            }
            .padding(.horizontal, 4)
            HStack(spacing: 0) {
                ForEach(Array(MonthGrid.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 0), count: 7), spacing: 2) {
                ForEach(days, id: \.self) { day in cell(day) }
            }
        }
        .padding(10)
        .frame(width: 216)
    }

    private func cell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        return Button { onPick(day) } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 11, weight: isSelected || isToday ? .bold : .medium).monospacedDigit())
                .foregroundStyle(isSelected ? Color.white : isToday ? Color.red : inMonth ? Color.primary : Color.secondary.opacity(0.6))
                .frame(width: 24, height: 24)
                .background(Circle().fill(isSelected ? Color.accentColor : Color.clear))
                .overlay(Circle().strokeBorder(isToday && !isSelected ? Color.red.opacity(0.6) : .clear, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func shift(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) { month = next }
    }
}

/// The header's empty part, standing in for the title bar it covers. The window's own
/// (hidden) title bar would otherwise take clicks in its top 28 pt or so: there a
/// double-click never reached the header, so it toggled compact mode only near the bar's
/// bottom edge. This view takes them: a double-click calls `onDoubleClick`, a drag moves
/// the window, even before the window has the keys.
struct TitleBarArea: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> AreaView {
        let view = AreaView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ view: AreaView, context: Context) { view.onDoubleClick = onDoubleClick }

    final class AreaView: NSView {
        var onDoubleClick: (() -> Void)?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick?()
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

/// Turns scroll-wheel and trackpad scrolling over a view into whole steps (+1 = next day),
/// one per mouse notch or per ~24 pt of trackpad travel. It lies over the view but takes
/// only scroll events; clicks go through to what's underneath.
struct ScrollWheelCatcher: NSViewRepresentable {
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onStep = onStep
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.onStep = onStep }

    final class CatcherView: NSView {
        var onStep: ((Int) -> Void)?
        private var travel: CGFloat = 0

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            // Down (or a swipe up with natural scrolling) moves forward in time.
            let delta = -event.scrollingDeltaY
            if !event.hasPreciseScrollingDeltas {
                if delta != 0 { onStep?(delta > 0 ? 1 : -1) }
                return
            }
            if event.phase == .began { travel = 0 }
            travel += delta
            while abs(travel) >= 24 {
                let step = travel > 0 ? 1 : -1
                onStep?(step)
                travel -= CGFloat(step) * 24
            }
        }
    }
}
