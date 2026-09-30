import Foundation

/// Reminders from Microsoft To Do through Microsoft Graph. Lists are To Do's lists; "Tasks"
/// is the default and "Flagged email" is read-only. To Do's due date has no time, so a time
/// lives in the task's reminder: a reminder on the due day (or without a due day) is the
/// due time.
@MainActor
public final class MicrosoftToDoSource: ReminderSource {
    public var onChange: (() -> Void)?

    private let auth: MicrosoftSession
    private let client: RemoteClient
    private let calendar: Calendar
    private var listInfos: [ReminderListInfo] = []
    private var defaultID: String?
    private var rejected = false
    private var filterUnsupported = false
    private var known = KnownTasks()

    private static let palette: [RGBA] = [0x2564CF, 0x7B61FF, 0x2FB57A, 0xE58A2B, 0xD9534F, 0x3AAFB9, 0xB85FC6, 0x8C9A2B]
        .map(RGBA.init(hex:))

    public init(auth: MicrosoftSession, session: URLSession = .shared, calendar: Calendar = .autoupdatingCurrent) {
        self.auth = auth
        self.calendar = calendar
        client = RemoteClient(base: URL(string: "https://graph.microsoft.com/v1.0/")!, token: "", session: session,
                              service: "Microsoft To Do", tokenProvider: { renew in try await auth.token(renew: renew) })
    }

    public func currentAccess() -> CalendarAccess {
        !auth.isSignedIn ? (rejected ? .denied : .notDetermined) : rejected ? .denied : .granted
    }

    public func requestAccess() async -> CalendarAccess { currentAccess() }
    public func lists() -> [ReminderListInfo] { listInfos }
    public func defaultListID() -> String? { defaultID ?? listInfos.first(where: \.isWritable)?.id }

    public func reminders(completedSince: Date) async throws -> [ReminderItem] {
        try await authorized {
            let rows = try await self.pages("me/todo/lists")
            var infos: [ReminderListInfo] = []
            for (index, row) in rows.enumerated() {
                guard let id = row["id"] as? String, let name = row["displayName"] as? String else { continue }
                let kind = row["wellknownListName"] as? String
                if kind == "defaultList" { self.defaultID = id }
                infos.append(ReminderListInfo(id: id, title: name, color: Self.palette[index % Self.palette.count],
                                              isWritable: kind != "flaggedEmails"))
            }
            var items: [ReminderItem] = []
            // Four lists at a time.
            for start in stride(from: 0, to: infos.count, by: 4) {
                let chunk = infos[start..<min(start + 4, infos.count)]
                try await withThrowingTaskGroup(of: [ReminderItem].self) { group in
                    for list in chunk {
                        group.addTask { try await self.tasks(in: list.id, completedSince: completedSince) }
                    }
                    for try await found in group { items += found }
                }
            }
            self.listInfos = infos
            self.known.read(items)
            return items
        }
    }

    public func save(_ item: ReminderItem) async throws -> ReminderItem {
        try await authorized {
            let path = "me/todo/lists/\(item.listID)/tasks"
            if item.isNew {
                let row = try await self.client.send("POST", path, body: self.fields(item, before: nil)) as? [String: Any]
                let saved = row.flatMap { self.item($0, listID: item.listID) } ?? item
                self.known.saved(saved)
                return saved
            }
            let body = self.fields(item, before: self.known[item.id])
            guard !body.isEmpty else { return item }
            let row = try await self.client.send("PATCH", "\(path)/\(item.id)", body: body) as? [String: Any]
            var saved = row.flatMap { self.item($0, listID: item.listID) } ?? item
            saved.nextDue = item.nextDue
            self.known.saved(saved)
            return saved
        }
    }

    public func remove(_ item: ReminderItem) async throws {
        try await authorized { try await self.client.send("DELETE", "me/todo/lists/\(item.listID)/tasks/\(item.id)", body: nil) }
    }

    /// To Do on the web (the format is to be confirmed with a real account).
    public func link(for item: ReminderItem) -> URL? {
        URL(string: "https://to-do.live.com/tasks/id/\(item.id)/details")
    }

    // MARK: Private

    private func authorized<T>(_ body: () async throws -> T) async throws -> T {
        do {
            let result = try await body()
            rejected = false
            return result
        } catch MicrosoftSession.Failure.refused, MicrosoftSession.Failure.signedOut, RemoteClient.Failure.unauthorized {
            rejected = true
            throw ReminderSourceError("Microsoft To Do signed you out. Sign in again.")
        }
    }

    /// A list's open tasks and those completed since `since`.
    private func tasks(in listID: String, completedSince since: Date) async throws -> [ReminderItem] {
        let path = "me/todo/lists/\(listID)/tasks"
        let stamp = RemoteDates.utcString(since, format: "yyyy-MM-dd'T'HH:mm:ss")
        var rows: [[String: Any]]
        if !filterUnsupported {
            do {
                rows = try await pages(path, filter: "status ne 'completed'")
                rows += try await pages(path, filter: "status eq 'completed' and completedDateTime/dateTime ge '\(stamp)'")
            } catch is ReminderSourceError {
                // The filter may be refused, or the service may just have failed. Fetch all and
                // filter here; only when that works is the filter written off, else the next
                // refresh tries it again.
                rows = try await pages(path)
                filterUnsupported = true
            }
        } else {
            rows = try await pages(path)
        }
        return rows.compactMap { item($0, listID: listID) }
            .filter { !$0.isCompleted || ($0.completionDate ?? .distantPast) >= since }
    }

    private func pages(_ path: String, filter: String? = nil) async throws -> [[String: Any]] {
        var page = try await client.get(path, query: filter.map { [URLQueryItem(name: "$filter", value: $0)] } ?? [])
            as? [String: Any] ?? [:]
        var rows = page["value"] as? [[String: Any]] ?? []
        while let next = (page["@odata.nextLink"] as? String).flatMap(URL.init(string:)), rows.count < 5000 {
            page = try await client.get(url: next) as? [String: Any] ?? [:]
            rows += page["value"] as? [[String: Any]] ?? []
        }
        return rows
    }

    private func item(_ row: [String: Any], listID: String) -> ReminderItem? {
        guard let id = row["id"] as? String, let title = row["title"] as? String else { return nil }
        let day = ((row["dueDateTime"] as? [String: Any])?["dateTime"] as? String)
            .flatMap { RemoteDates.day(String($0.prefix(10)), in: calendar.timeZone) }
        let reminder = row["isReminderOn"] as? Bool == true ? instant(row["reminderDateTime"]) : nil
        let due: Date?
        let hasTime: Bool
        if let reminder, day.map({ calendar.isDate(reminder, inSameDayAs: $0) }) ?? true {
            (due, hasTime) = (reminder, true)
        } else {
            (due, hasTime) = (day, false)
        }
        let body = row["body"] as? [String: Any]
        var notes = body?["content"] as? String
        if body?["contentType"] as? String == "html" {
            notes = notes?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
        }
        notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let priority: ReminderPriority = switch row["importance"] as? String {
        case "high": .high
        case "low": .low
        default: .none
        }
        return ReminderItem(
            id: id, title: title, listID: listID, due: due, dueHasTime: hasTime,
            isCompleted: row["status"] as? String == "completed",
            completionDate: instant(row["completedDateTime"]),
            notes: notes?.isEmpty == false ? notes : nil, priority: priority,
            isRepeating: row["recurrence"] is [String: Any]
        )
    }

    /// A Graph `dateTimeTimeZone`, as an instant.
    private func instant(_ value: Any?) -> Date? {
        guard let value = value as? [String: Any], let text = value["dateTime"] as? String else { return nil }
        let zone = (value["timeZone"] as? String).flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "UTC")!
        return RemoteDates.dateTime(String(text.prefix(19)), floating: zone)
    }

    /// What to send: only what changed since `before` (everything for a new task).
    private func fields(_ item: ReminderItem, before: ReminderItem?) -> [String: Any] {
        var body: [String: Any] = [:]
        let zone = calendar.timeZone.identifier
        if before?.title != item.title { body["title"] = item.title }
        if before?.notes != item.notes, item.notes != nil || before != nil {
            body["body"] = ["content": item.notes ?? "", "contentType": "text"]
        }
        if before?.priority != item.priority, item.priority != .none || before != nil {
            body["importance"] = switch item.priority {
            case .none: "normal"
            case .low: "low"
            case .medium, .high: "high"
            }
        }
        if before?.due != item.due || before?.dueHasTime != item.dueHasTime, item.due != nil || before != nil {
            if let due = item.due {
                // A day, not an instant: sent as UTC so it reads back as the same day wherever it is read.
                body["dueDateTime"] = ["dateTime": RemoteDates.dayString(due, in: calendar.timeZone) + "T00:00:00", "timeZone": "UTC"]
                if item.dueHasTime {
                    let local = DateFormatter()
                    local.locale = Locale(identifier: "en_US_POSIX")
                    local.timeZone = calendar.timeZone
                    local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                    body["reminderDateTime"] = ["dateTime": local.string(from: due), "timeZone": zone]
                    body["isReminderOn"] = true
                } else if before?.dueHasTime == true {
                    body["isReminderOn"] = false
                }
            } else {
                body["dueDateTime"] = NSNull()
                if before?.dueHasTime == true { body["isReminderOn"] = false }
            }
        }
        if before?.isCompleted != item.isCompleted, item.isCompleted || before != nil {
            body["status"] = item.isCompleted ? "completed" : "notStarted"
        }
        return body
    }
}
