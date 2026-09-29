import StickyCalendarCore
import SwiftUI

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

    /// The reminders window is open, or the Reminders tab is showing.
    private var isRemindersOpen: Bool { reminderSettings.isVisible }
    private var showsRemindersTab: Bool { reminderSettings.placement == .tab && isRemindersOpen }

    var body: some View {
        HStack(spacing: 8) {
            if showsRemindersTab {
                Text("Reminders").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                refreshButton
                pinButton
                settingsButton
                remindersButton // last in both modes, so it stays put when switching
            } else {
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
                Spacer(minLength: 0)
                // All the buttons if they fit; otherwise the less frequent ones in a menu.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        jumpToNowButton
                        if !settings.isCompact { noteButton }
                        refreshButton
                        calendarButton
                        pinButton
                        compactButton
                        settingsButton
                        remindersButton // last in both modes, so it stays put when switching
                    }
                    HStack(spacing: 8) {
                        jumpToNowButton
                        if !settings.isCompact { noteButton }
                        pinButton
                        moreMenu
                        remindersButton
                    }
                }
                .layoutPriority(1)
            }
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

    // MARK: Buttons

    @ViewBuilder
    private var jumpToNowButton: some View {
        if store.offersJumpToNow {
            Button { store.jumpToNow() } label: { Image(systemName: "clock.arrow.circlepath") }
                .buttonStyle(.borderless)
                .help("Jump to now")
        }
    }

    private var noteButton: some View {
        Button(action: onToggleNote) { Image(systemName: isNoteVisible ? "note.text" : "note") }
            .buttonStyle(.borderless)
            .help(isNoteVisible ? "Hide note" : "Show note")
    }

    private var remindersButton: some View {
        let tab = reminderSettings.placement == .tab
        return Button(action: onToggleReminders) {
            Image(systemName: isRemindersOpen ? "checklist.checked" : "checklist")
        }
        .buttonStyle(.borderless)
        .help(tab ? (isRemindersOpen ? "Back to the calendar" : "Show reminders")
                  : (isRemindersOpen ? "Hide reminders" : "Show reminders"))
    }

    @ViewBuilder
    private var refreshButton: some View {
        if isRefreshing {
            ProgressView().controlSize(.small).frame(width: 16, height: 16)
        } else {
            Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh (⌘R)")
        }
    }

    private var calendarButton: some View {
        Button { openInCalendar() } label: { Image(systemName: "calendar") }
            .buttonStyle(.borderless)
            .help("Open in Calendar (⌘O)")
    }

    private var pinButton: some View {
        Button(action: onTogglePin) { Image(systemName: settings.isPinned ? "pin.fill" : "pin.slash") }
            .buttonStyle(.borderless)
            .help(settings.isPinned ? "Unpin: behave like a normal window (⌃S)" : "Pin: keep on top of other windows (⌃S)")
    }

    private var compactButton: some View {
        Button(action: onToggleCompact) {
            Image(systemName: settings.isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
        }
        .buttonStyle(.borderless)
        .help(settings.isCompact ? "Expand (⌘M, or double-click here)" : "Compact: just what's next (⌘M, or double-click here)")
    }

    private var settingsButton: some View {
        Button(action: onSettings) { Image(systemName: "gearshape") }
            .buttonStyle(.borderless)
            .help("Settings (⌘,)")
    }

    /// Refresh, Open in Calendar, compact and settings, when the header is too narrow for them.
    private var moreMenu: some View {
        Menu {
            Button("Refresh", action: onRefresh)
            Button("Open in Calendar", action: openInCalendar)
            Button(settings.isCompact ? "Expand" : "Compact", action: onToggleCompact)
            Divider()
            Button("Settings…", action: onSettings)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }

    private func openInCalendar() {
        CalendarJump.perform(day: store.day, settings: settings, store: store)
    }

    private func dayTitle(_ format: Date.FormatStyle) -> some View {
        Text(store.day.formatted(format))
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
    }
}
