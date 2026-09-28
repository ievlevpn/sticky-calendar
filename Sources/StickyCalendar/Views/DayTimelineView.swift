import AppKit
import StickyCalendarCore
import SwiftUI

/// The day's timeline: hour grid, past-time wash, event blocks, now-line, and all
/// direct-manipulation gestures (create, move, resize, select, open editor).
struct DayTimelineView: View {
    let store: CalendarStore

    /// The event being moved or resized, with its live (snapped) times.
    @State private var dragPreview: EventItem?
    /// A new event being dragged out or edited before its first save.
    @State private var draft: EventItem?
    @State private var isDraftEditorOpen = false
    /// The existing event whose editor popover is open.
    @State private var editingID: String?

    private static let space = "timeline"
    private let gutter: CGFloat = 42
    private let trailingInset: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let geo = TimelineGeometry(dayStart: store.day, range: store.effectiveRange, height: proxy.size.height)
            let parts = geo.partition(store.timedEvents)
            let slots = OverlapLayout.columns(for: parts.visible)
            let width = max(proxy.size.width - gutter - trailingInset, 20)

            SwiftUI.TimelineView(.everyMinute) { context in
                ZStack(alignment: .topLeading) {
                    HourGrid(geometry: geo, gutter: gutter)
                    if store.isViewingToday { pastWash(geo, now: context.date, width: width) }
                    creationSurface(geo, width: width)
                    ForEach(parts.visible) { item in
                        block(item, slot: slots[item.id] ?? ColumnSlot(column: 0, count: 1),
                              geo: geo, width: width, now: context.date)
                    }
                    if let draft { draftBlock(draft, geo: geo, width: width) }
                    if store.isViewingToday { nowLine(geo, now: context.date, width: width) }
                }
                .coordinateSpace(name: Self.space)
            }
            .overlay(alignment: .top) { pill(count: parts.earlier.count, label: "earlier").offset(y: -6) }
            .overlay(alignment: .bottom) { pill(count: parts.later.count, label: "later").offset(y: 6) }
            .overlay {
                if store.visibleCalendars.isEmpty {
                    Text("No calendars selected.\nChoose some in Settings.")
                        .multilineTextAlignment(.center)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // MARK: Layers

    private func pastWash(_ geo: TimelineGeometry, now: Date, width: CGFloat) -> some View {
        let y = min(max(CGFloat(geo.y(for: now)), 0), CGFloat(geo.height))
        return Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: width, height: y)
            .offset(x: gutter)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func nowLine(_ geo: TimelineGeometry, now: Date, width: CGFloat) -> some View {
        let y = CGFloat(geo.y(for: now))
        if y >= 0 && y <= CGFloat(geo.height) {
            HStack(spacing: 0) {
                Circle().fill(Color.red).frame(width: 7, height: 7)
                Rectangle().fill(Color.red).frame(height: 1.5)
            }
            .frame(width: width + 4)
            .offset(x: gutter - 4, y: y - 3.5)
            .allowsHitTesting(false)
        }
    }

    /// Empty timeline area: click deselects, drag creates a new event.
    private func creationSurface(_ geo: TimelineGeometry, width: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: width, height: CGFloat(geo.height))
            .offset(x: gutter)
            .onTapGesture { store.selectedID = nil }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        guard !isDraftEditorOpen else { return }
                        let (start, end) = EventDrag.newInterval(
                            from: geo.date(forY: Double(value.startLocation.y)),
                            to: geo.date(forY: Double(value.location.y))
                        )
                        if var current = draft {
                            current.start = start
                            current.end = end
                            draft = current
                        } else if let fresh = store.makeDraft(start: start, end: end) {
                            store.selectedID = nil
                            draft = fresh
                        } else {
                            store.lastError = "No visible calendar accepts new events."
                        }
                    }
                    .onEnded { _ in
                        if draft != nil { isDraftEditorOpen = true }
                    }
            )
    }

    private func block(_ item: EventItem, slot: ColumnSlot, geo: TimelineGeometry, width: CGFloat, now: Date) -> some View {
        let shown = dragPreview.flatMap { $0.id == item.id ? $0 : nil }
            ?? store.pendingEdit.flatMap { $0.original.id == item.id ? $0.updated : nil }
            ?? item
        let frame = geo.frame(for: shown)
        let columnWidth = width / CGFloat(slot.count)
        let color = Color(rgba: store.calendarInfo(id: item.calendarID)?.color ?? .fallback)

        return EventBlockView(
            item: shown,
            color: color,
            isSelected: store.selectedID == item.id,
            isPast: now >= shown.end,
            height: CGFloat(frame.height)
        )
        .frame(width: max(columnWidth - 2, 4), height: CGFloat(frame.height))
        .overlay(alignment: .top) { resizeHandle(item, .resizeStart, geo: geo) }
        .overlay(alignment: .bottom) { resizeHandle(item, .resizeEnd, geo: geo) }
        .gesture(dragGesture(item, .move, geo: geo))
        .onTapGesture(count: 2) { editingID = item.id }
        .onTapGesture { store.selectedID = item.id }
        .popover(
            isPresented: Binding(get: { editingID == item.id }, set: { if !$0 { editingID = nil } }),
            arrowEdge: .leading
        ) {
            EventEditPopover(
                item: item,
                calendars: editorCalendars(for: item),
                onFinish: { result in
                    if let result { store.requestUpdate(from: item, to: result) }
                },
                onDelete: { store.requestDelete(item) },
                onOpenInCalendar: { SystemLinks.openInCalendar(item) }
            )
        }
        .offset(x: gutter + CGFloat(slot.column) * columnWidth, y: CGFloat(frame.top))
    }

    private func draftBlock(_ item: EventItem, geo: TimelineGeometry, width: CGFloat) -> some View {
        let frame = geo.frame(for: item)
        let color = Color(rgba: store.calendarInfo(id: item.calendarID)?.color ?? .fallback)
        return EventBlockView(item: item, color: color, isSelected: true, isPast: false, height: CGFloat(frame.height))
            .frame(width: width, height: CGFloat(frame.height))
            .popover(
                isPresented: Binding(get: { isDraftEditorOpen }, set: { if !$0 { isDraftEditorOpen = false } }),
                arrowEdge: .leading
            ) {
                EventEditPopover(
                    item: item,
                    calendars: editorCalendars(for: item),
                    onFinish: { result in
                        draft = nil
                        if let result { store.create(result) }
                    }
                )
            }
            .offset(x: gutter, y: CGFloat(frame.top))
    }

    @ViewBuilder
    private func resizeHandle(_ item: EventItem, _ kind: DragKind, geo: TimelineGeometry) -> some View {
        if !item.isReadOnly {
            Color.clear
                .frame(height: 6)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                }
                .gesture(dragGesture(item, kind, geo: geo))
        }
    }

    private func dragGesture(_ item: EventItem, _ kind: DragKind, geo: TimelineGeometry) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard !item.isReadOnly else { return }
                store.selectedID = item.id
                let delta = Double(value.translation.height) / geo.pointsPerSecond
                dragPreview = EventDrag.apply(kind, to: item, delta: delta)
            }
            .onEnded { _ in
                guard let preview = dragPreview else { return }
                dragPreview = nil
                store.requestUpdate(from: item, to: preview)
            }
    }

    @ViewBuilder
    private func pill(count: Int, label: String) -> some View {
        if count > 0 {
            Button { store.expandRangeToFitAll() } label: {
                Text("+\(count) \(label)")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
            .buttonStyle(.plain)
            .help("Show all of today's events")
        }
    }

    /// Writable calendars, plus the event's own calendar so the picker can show it.
    private func editorCalendars(for item: EventItem) -> [CalendarInfo] {
        store.calendars.filter { $0.isWritable || $0.id == item.calendarID }
    }
}

struct HourGrid: View {
    let geometry: TimelineGeometry
    let gutter: CGFloat

    var body: some View {
        Canvas { context, size in
            let range = geometry.range
            for hour in range.start...range.end {
                let y = CGFloat(geometry.y(forHour: hour))
                var line = Path()
                line.move(to: CGPoint(x: gutter, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.secondary.opacity(0.35)), lineWidth: 0.5)

                let label = Text(String(format: "%02d:00", hour))
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                context.draw(context.resolve(label), at: CGPoint(x: gutter - 6, y: y), anchor: .trailing)

                if hour < range.end {
                    let mid = (y + CGFloat(geometry.y(forHour: hour + 1))) / 2
                    var half = Path()
                    half.move(to: CGPoint(x: gutter, y: mid))
                    half.addLine(to: CGPoint(x: size.width, y: mid))
                    context.stroke(half, with: .color(.secondary.opacity(0.15)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct EventBlockView: View {
    let item: EventItem
    let color: Color
    let isSelected: Bool
    let isPast: Bool
    let height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        VStack(alignment: .leading, spacing: 1) {
            Text(item.title.isEmpty ? "New Event" : item.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(height > 34 ? 2 : 1)
            if height > 28 {
                Text("\(item.start.formatted(date: .omitted, time: .shortened)) – \(item.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if height > 46, let location = item.location, !location.isEmpty {
                Text(location)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .padding(.vertical, height > 20 ? 3 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(color.opacity(isSelected ? 0.45 : 0.25)))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(color, lineWidth: isSelected ? 1.5 : 0))
        .opacity(isPast ? 0.5 : 1)
    }
}
