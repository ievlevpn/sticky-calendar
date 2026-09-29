import AppKit
import StickyCalendarCore
import SwiftUI

/// The day's timeline: a whole day at a fixed scale inside a vertical scroll view, with
/// hour grid, past-time wash, event blocks, now-ruler, and all direct-manipulation
/// gestures (create, move, resize, select, open editor).
struct DayTimelineView: View {
    let store: CalendarStore
    /// Scales hours, labels and event text together (Settings → Zoom, ⌘= / ⌘- / ⌘0).
    let zoom: CGFloat

    /// The event being moved or resized, with its live (snapped) times.
    @State private var dragPreview: EventItem?
    /// A new event being dragged out or edited before its first save.
    @State private var draft: EventItem?
    @State private var isDraftEditorOpen = false
    /// The existing event whose editor popover is open.
    @State private var editingID: String?
    /// Whether the editor being opened should focus its title (opened with Return).
    @State private var focusTitleOnOpen = false
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollBridge = ScrollBridge()

    private static let space = "timeline"
    private var gutter: CGFloat { 44 * zoom }
    private let trailingInset: CGFloat = 8
    /// Room above 00:00 and below 24:00 so their labels aren't clipped.
    private var verticalInset: CGFloat { 8 * zoom }

    var body: some View {
        let geo = TimelineGeometry(dayStart: store.day, pointsPerHour: TimelineGeometry.defaultPointsPerHour * Double(zoom))
        GeometryReader { viewport in
            let width = max(viewport.size.width - gutter - trailingInset, 20)
            ScrollView(.vertical) {
                SwiftUI.TimelineView(.everyMinute) { context in
                    content(geo, width: width, now: context.date)
                        .onChange(of: context.date) { _, now in reportNowVisibility(geo, now: now) }
                }
                .padding(.vertical, verticalInset)
                .background(ScrollObserver(bridge: scrollBridge) { offset, height in
                    scrollOffset = offset
                    viewportHeight = height
                    reportNowVisibility(geo, now: Date())
                })
            }
            .onAppear { perform(store.scrollRequest, geo: geo, animated: false) }
            .onChange(of: store.scrollRequest) { _, request in perform(request, geo: geo, animated: true) }
            .onChange(of: store.scrollStepRequest) { _, request in
                guard let request else { return }
                let target = geo.offset(after: request.step, from: Double(scrollOffset),
                                        viewportHeight: Double(viewportHeight), padding: Double(verticalInset))
                scrollBridge.scroll(animated: true) { _ in target }
            }
            .onChange(of: store.revealRequest) { _, request in
                guard let request, let item = store.timedEvents.first(where: { $0.id == request.eventID }) else { return }
                let frame = geo.frame(for: item)
                guard let target = geo.revealOffset(top: frame.top, bottom: frame.top + frame.height,
                                                    scrollOffset: Double(scrollOffset), viewportHeight: Double(viewportHeight),
                                                    padding: Double(verticalInset)) else { return }
                scrollBridge.scroll(animated: true) { _ in target }
            }
            .onChange(of: zoom) { old, new in keepCenter(from: old, to: new) }
            .onChange(of: store.editRequest) { _, request in
                guard let request else { return }
                focusTitleOnOpen = true
                editingID = request.eventID
            }
        }
        .overlay {
            if store.visibleCalendars.isEmpty {
                Text("No calendars selected.\nChoose some in Settings.")
                    .multilineTextAlignment(.center)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func content(_ geo: TimelineGeometry, width: CGFloat, now: Date) -> some View {
        let slots = OverlapLayout.columns(for: store.timedEvents)
        return ZStack(alignment: .topLeading) {
            HourGrid(geometry: geo, gutter: gutter, zoom: zoom)
            if store.isViewingToday { pastWash(geo, now: now, width: width) }
            creationSurface(geo, width: width)
            ForEach(store.timedEvents) { item in
                block(item, slot: slots[item.id] ?? ColumnSlot(column: 0, count: 1),
                      geo: geo, width: width, now: now)
            }
            if let draft { draftBlock(draft, geo: geo, width: width) }
            if store.isViewingToday { nowRuler(geo, now: now, width: width) }
        }
        .frame(width: gutter + width + trailingInset, height: CGFloat(geo.height), alignment: .topLeading)
        .coordinateSpace(name: Self.space)
    }

    // MARK: Scrolling

    /// Today's "now" sits a third of the way down; an event just below the top; an hour at the top.
    private func perform(_ request: ScrollRequest, geo: TimelineGeometry, animated: Bool) {
        let y = geo.y(for: request.target, events: store.timedEvents, now: Date())
        let fraction: Double = switch request.target {
        case .now: 1.0 / 3
        case .event: 0.1
        case .hour: 0
        }
        scrollBridge.scroll(animated: animated) { viewport in
            geo.scrollOffset(showing: y, at: fraction, viewportHeight: viewport, padding: Double(verticalInset))
        }
    }

    /// Keeps the time in the middle of the view there when the zoom changes.
    private func keepCenter(from old: CGFloat, to new: CGFloat) {
        let hourHeight = TimelineGeometry.defaultPointsPerHour
        let center = Double(scrollOffset - 8 * old + viewportHeight / 2) / (hourHeight * Double(old)) // in hours
        let inset = Double(8 * new)
        scrollBridge.scroll(animated: false) { viewport in
            let target = center * hourHeight * Double(new) + inset - viewport / 2
            return min(max(target, 0), max(24 * hourHeight * Double(new) + 2 * inset - viewport, 0))
        }
    }

    private func reportNowVisibility(_ geo: TimelineGeometry, now: Date) {
        let visible = geo.isVisible(
            now,
            scrollOffset: Double(scrollOffset - verticalInset),
            viewportHeight: Double(viewportHeight)
        )
        if store.isNowOnScreen != visible { store.isNowOnScreen = visible }
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

    /// Red line across the timeline with the current time in a capsule over the hour labels.
    @ViewBuilder
    private func nowRuler(_ geo: TimelineGeometry, now: Date, width: CGFloat) -> some View {
        let y = CGFloat(geo.y(for: now))
        if y >= 0 && y <= CGFloat(geo.height) {
            HStack(spacing: 0) {
                Text(now.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9 * zoom, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.red))
                    .frame(width: gutter, alignment: .trailing)
                Rectangle().fill(Color.red).frame(height: 1.5)
            }
            .frame(width: gutter + width, height: 14 * zoom)
            .offset(y: y - 7 * zoom)
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
            height: CGFloat(frame.height),
            zoom: zoom
        )
        .frame(width: max(columnWidth - 2, 4), height: CGFloat(frame.height))
        .overlay(alignment: .top) { resizeHandle(item, .resizeStart, geo: geo) }
        .overlay(alignment: .bottom) { resizeHandle(item, .resizeEnd, geo: geo) }
        .gesture(dragGesture(item, .move, geo: geo))
        .onTapGesture(count: 2) {
            focusTitleOnOpen = false
            editingID = item.id
        }
        // Simultaneous, so selection is immediate: a plain single-tap below a double-tap
        // waits out the double-click interval (~0.4 s) before firing.
        .simultaneousGesture(TapGesture().onEnded { store.selectedID = item.id })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(store.selectedID == item.id ? .isSelected : [])
        .popover(
            isPresented: Binding(get: { editingID == item.id }, set: { if !$0 { editingID = nil } }),
            arrowEdge: .leading
        ) {
            EventEditPopover(
                item: item,
                calendars: editorCalendars(for: item),
                // Merges only the user's changes onto the event's current state,
                // so anything synced while the editor was open is kept.
                onFinish: { snapshot, result in
                    if let result { store.requestEdit(of: snapshot, result: result) }
                },
                onDelete: { store.requestDelete(item) },
                onOpenInCalendar: { SystemLinks.openInCalendar(item) },
                focusTitle: focusTitleOnOpen
            )
        }
        .offset(x: gutter + CGFloat(slot.column) * columnWidth, y: CGFloat(frame.top))
    }

    private func draftBlock(_ item: EventItem, geo: TimelineGeometry, width: CGFloat) -> some View {
        let frame = geo.frame(for: item)
        let color = Color(rgba: store.calendarInfo(id: item.calendarID)?.color ?? .fallback)
        return EventBlockView(item: item, color: color, isSelected: true, isPast: false, height: CGFloat(frame.height), zoom: zoom)
            .frame(width: width, height: CGFloat(frame.height))
            .popover(
                isPresented: Binding(get: { isDraftEditorOpen }, set: { if !$0 { isDraftEditorOpen = false } }),
                arrowEdge: .leading
            ) {
                EventEditPopover(
                    item: item,
                    calendars: editorCalendars(for: item),
                    onFinish: { _, result in
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

    /// Writable calendars, plus the event's own calendar so the picker can show it.
    private func editorCalendars(for item: EventItem) -> [CalendarInfo] {
        store.calendars.filter { $0.isWritable || $0.id == item.calendarID }
    }
}

struct HourGrid: View {
    let geometry: TimelineGeometry
    let gutter: CGFloat
    let zoom: CGFloat

    var body: some View {
        Canvas { context, size in
            for hour in 0...24 {
                let y = CGFloat(geometry.y(forHour: hour))
                var line = Path()
                line.move(to: CGPoint(x: gutter, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.secondary.opacity(0.35)), lineWidth: 0.5)

                let label = Text(String(format: "%02d:00", hour))
                    .font(.system(size: 9 * zoom, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                context.draw(context.resolve(label), at: CGPoint(x: gutter - 6, y: y), anchor: .trailing)

                if hour < 24 {
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
    let zoom: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        // Thresholds are in unzoomed points: zoom scales the text and the hours alike.
        let height = self.height / zoom
        VStack(alignment: .leading, spacing: 1) {
            Text(item.title.isEmpty ? "New Event" : item.title)
                .font(.system(size: 11 * zoom, weight: .semibold))
                .lineLimit(height > 34 ? 2 : 1)
            if height > 28 {
                Text("\(item.start.formatted(date: .omitted, time: .shortened)) – \(item.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10 * zoom))
                    .foregroundStyle(.secondary)
            }
            if height > 46, let location = item.location, !location.isEmpty {
                Text(location)
                    .font(.system(size: 10 * zoom))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 7 * zoom)
        .padding(.trailing, 4 * zoom)
        .padding(.vertical, height > 20 ? 3 * zoom : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(color.opacity(isSelected ? 0.45 : 0.25)))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(color, lineWidth: isSelected ? 1.5 : 0))
        .opacity(isPast ? 0.5 : 1)
    }
}
