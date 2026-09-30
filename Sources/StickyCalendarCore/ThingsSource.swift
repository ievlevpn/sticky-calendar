import Foundation

/// Reminders from Things 3 on this Mac, through `ThingsScripting`. The due date is Things'
/// "When" (so Today matches Things' Today; a past "When" counts as today, as Things rolls it
/// over); deadlines are shown apart. Things has no times or importance for us.
@MainActor
public final class ThingsSource: ReminderSource {
    public var onChange: (() -> Void)?

    public static let inboxID = "things-inbox"
    /// To-dos in no project, no area and not in the Inbox (e.g. planned for today).
    public static let otherID = "things-other"

    private let things: ThingsScripting
    private let calendar: Calendar
    private let now: () -> Date
    private var listInfos: [ReminderListInfo] = []
    private var kinds: [String: String] = [:]
    private var rejected = false
    /// Things is started for the first load and after ⌘R, not by the regular checks, so
    /// quitting it stays quit.
    private var mayLaunch = true
    private var known = KnownTasks()

    private static let palette: [RGBA] = [0x4A90D9, 0x7B61FF, 0x2FB57A, 0xE58A2B, 0xD9534F, 0x3AAFB9, 0xB85FC6, 0x8C9A2B]
        .map(RGBA.init(hex:))

    public init(things: ThingsScripting? = nil, calendar: Calendar = .autoupdatingCurrent,
                now: @escaping () -> Date = Date.init) {
        self.things = things ?? JXAThings()
        self.calendar = calendar
        self.now = now
    }

    public func currentAccess() -> CalendarAccess { rejected ? .denied : .granted }
    public func requestAccess() async -> CalendarAccess { currentAccess() }
    public func lists() -> [ReminderListInfo] { listInfos }
    public func defaultListID() -> String? { Self.inboxID }
    public var supportsTime: Bool { false }
    public var supportsPriority: Bool { false }
    public func refreshIfNeeded() { mayLaunch = true }

    public func reminders(completedSince: Date) async throws -> [ReminderItem] {
        if !things.isRunning() {
            guard mayLaunch else { throw ReminderSourceError("Things is closed. ⌘R opens it.") }
            await things.launch()
        }
        mayLaunch = false
        let snapshot = try await call { try await self.things.snapshot(completedSince: completedSince) }
        var listOf: [String: String] = [:]
        for container in snapshot.lists { for id in container.toDoIDs where listOf[id] == nil { listOf[id] = container.id } }
        for id in snapshot.inbox { listOf[id] = Self.inboxID }
        let today = calendar.startOfDay(for: now())
        var items = snapshot.open.map { item($0, listID: listOf[$0.id] ?? Self.otherID, today: today) }
        let open = Set(items.map(\.id))
        items += snapshot.done.filter { !open.contains($0.id) }
            .map { item($0, listID: listOf[$0.id] ?? Self.otherID, today: today) }
        var infos = [ReminderListInfo(id: Self.inboxID, title: "Inbox", color: RGBA(hex: 0x3A8DDE))]
        kinds = [:]
        for (index, container) in snapshot.lists.enumerated() {
            kinds[container.id] = container.kind
            infos.append(ReminderListInfo(id: container.id, title: container.name, color: Self.palette[index % Self.palette.count]))
        }
        if items.contains(where: { $0.listID == Self.otherID }) {
            infos.append(ReminderListInfo(id: Self.otherID, title: "Other", color: RGBA(hex: 0x8E8E93)))
        }
        listInfos = infos
        known.read(items)
        return items
    }

    public func save(_ item: ReminderItem) async throws -> ReminderItem {
        try await call {
            if item.isNew {
                let container: ThingsContainer = switch item.listID {
                case Self.inboxID: .inbox
                case Self.otherID: .none
                case let id where self.kinds[id] == "project": .project(id)
                case let id where self.kinds[id] == "area": .area(id)
                default: .inbox
                }
                var saved = item
                saved.id = try await self.things.create(name: item.title, notes: item.notes, in: container, on: item.due)
                self.known.saved(saved)
                return saved
            }
            let before = self.known[item.id]
            if before?.title != item.title { try await self.things.setName(id: item.id, name: item.title) }
            if before?.notes != item.notes { try await self.things.setNotes(id: item.id, notes: item.notes ?? "") }
            if before?.due != item.due { try await self.things.schedule(id: item.id, on: item.due) }
            if before?.isCompleted != item.isCompleted { try await self.things.setStatus(id: item.id, completed: item.isCompleted) }
            self.known.saved(item)
            return item
        }
    }

    public func remove(_ item: ReminderItem) async throws {
        try await call { try await self.things.delete(id: item.id) }
    }

    public func link(for item: ReminderItem) -> URL? {
        var parts = URLComponents(string: "things:///show")!
        parts.queryItems = [URLQueryItem(name: "id", value: item.id)]
        return parts.url
    }

    private func item(_ todo: ThingsSnapshot.ToDo, listID: String, today: Date) -> ReminderItem {
        var due = todo.when.map { calendar.startOfDay(for: $0) }
        if let day = due, day < today, todo.status == "open" { due = today }
        return ReminderItem(
            id: todo.id, title: todo.name, listID: listID, due: due, dueHasTime: false,
            isCompleted: todo.status == "completed", completionDate: todo.completed,
            notes: todo.notes?.isEmpty == false ? todo.notes : nil,
            deadline: todo.deadline.map { calendar.startOfDay(for: $0) }
        )
    }

    /// Runs `body`, turning Things' failures into what the store shows.
    private func call<T>(_ body: () async throws -> T) async throws -> T {
        do {
            let result = try await body()
            rejected = false
            return result
        } catch let failure as ThingsFailure {
            switch failure {
            case .notAllowed:
                rejected = true
                throw ReminderSourceError("Sticky Calendar isn't allowed to control Things.")
            case .notRunning: throw ReminderSourceError("Things is closed. ⌘R opens it.")
            case .timedOut: throw ReminderSourceError("Things didn't answer.")
            case .notFound: throw ReminderSourceError("That reminder no longer exists in Things.")
            case let .other(message): throw ReminderSourceError("Things couldn't do that: \(message)")
            }
        }
    }
}
