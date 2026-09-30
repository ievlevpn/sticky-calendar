import Foundation
import Security

/// JSON over HTTPS with a bearer token, for the Todoist, TickTick and Microsoft To Do sources.
struct RemoteClient: Sendable {
    let base: URL
    let token: String
    let session: URLSession
    /// "Todoist", "TickTick": for error messages.
    let service: String
    /// Asked for the token before each request instead of `token` (Microsoft's expire hourly),
    /// and once more with `renew` after a 401, the request then retried once.
    var tokenProvider: (@MainActor @Sendable (_ renew: Bool) async throws -> String)? = nil

    enum Failure: Error { case unauthorized }

    func get(_ path: String, query: [URLQueryItem] = []) async throws -> Any {
        try await send("GET", path, query: query, body: nil)
    }

    /// A page link the server handed back (Microsoft's `@odata.nextLink`). Only followed on the
    /// service's own host over HTTPS, so the token can't be sent anywhere else.
    func get(url: URL) async throws -> Any {
        guard url.scheme == "https", url.host == base.host else {
            throw ReminderSourceError("\(service) sent a page link Sticky Calendar won't follow.")
        }
        return try await perform("GET", url: url, body: nil)
    }

    @discardableResult
    func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]?) async throws -> Any {
        var parts = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        return try await perform(method, url: parts.url!, body: body)
    }

    private func perform(_ method: String, url: URL, body: [String: Any]?,
                         renewed: Bool = false, waited: Bool = false) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = method
        let bearer = try await tokenProvider?(renewed) ?? token
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ReminderSourceError("Couldn't reach \(service): \(error.localizedDescription)")
        }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 401, tokenProvider != nil, !renewed {
            return try await perform(method, url: url, body: body, renewed: true, waited: waited)
        }
        if status == 401 || status == 403 { throw Failure.unauthorized }
        if status == 429, !waited {
            let seconds = min(Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1, 30)
            try await Task.sleep(for: .seconds(seconds))
            return try await perform(method, url: url, body: body, renewed: renewed, waited: true)
        }
        if status == 404 { throw ReminderSourceError("That reminder no longer exists in \(service).") }
        guard (200..<300).contains(status) else {
            throw ReminderSourceError("\(service) couldn't do that (error \(status)).")
        }
        return data.isEmpty ? [String: Any]() : (try? JSONSerialization.jsonObject(with: data)) ?? [String: Any]()
    }
}

/// API tokens in the login keychain, not in UserDefaults.
public enum ReminderTokens {
    private static let service = "com.ievlevpn.StickyCalendar.reminders"

    public static func token(for account: String) -> String? {
        var result: AnyObject?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true,
        ]
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func setToken(_ token: String?, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let token, !token.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// What a remote source last knew of each task, to send only what a save changes. A read
/// that was already under way when a task was saved may still have the task as it was
/// (the store ignores such a read, but it lands here), so for a little while what was saved
/// counts over what was read: else ticking and quickly unticking would send no reopen.
struct KnownTasks {
    private var items: [String: ReminderItem] = [:]
    private var savedAt: [String: Date] = [:]
    private let settleTime: TimeInterval = 10

    subscript(id: String) -> ReminderItem? { items[id] }

    mutating func saved(_ item: ReminderItem) {
        items[item.id] = item
        savedAt[item.id] = Date()
    }

    mutating func read(_ fetched: [ReminderItem]) {
        let recent = Date().addingTimeInterval(-settleTime)
        savedAt = savedAt.filter { $0.value > recent }
        var next = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for id in savedAt.keys { next[id] = items[id] }
        items = next
    }
}

/// Parsing shared by the remote sources.
enum RemoteDates {
    static func day(_ text: String, in zone: TimeZone) -> Date? {
        formatter("yyyy-MM-dd", zone).date(from: String(text.prefix(10)))
    }

    static func dayString(_ date: Date, in zone: TimeZone) -> String {
        formatter("yyyy-MM-dd", zone).string(from: date)
    }

    /// ISO 8601 with or without fractional seconds, "Z" or "+0000"; `floating` when it has no zone.
    static func dateTime(_ text: String, floating zone: TimeZone) -> Date? {
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX"] {
            if let date = formatter(format, zone).date(from: text) { return date }
        }
        return formatter("yyyy-MM-dd'T'HH:mm:ss", zone).date(from: String(text.prefix(19)))
    }

    static func utcString(_ date: Date, format: String = "yyyy-MM-dd'T'HH:mm:ss'Z'") -> String {
        formatter(format, TimeZone(identifier: "UTC")!).string(from: date)
    }

    private static func formatter(_ format: String, _ zone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = format
        return f
    }
}

// MARK: - Todoist

/// Reminders from Todoist (API v1) with a personal API token (Todoist → Settings →
/// Integrations → Developer). Projects are the lists; the Inbox is the default.
@MainActor
public final class TodoistSource: ReminderSource {
    public var onChange: (() -> Void)?

    private let client: RemoteClient
    private let calendar: Calendar
    private var projects: [ReminderListInfo] = []
    private var inboxID: String?
    private var rejected = false
    /// The last known state of each task, to tell what a save changes.
    private var known = KnownTasks()

    public static let tokenAccount = "todoist"
    public static let tokenPage = URL(string: "https://app.todoist.com/app/settings/integrations/developer")!

    public init(token: String, session: URLSession = .shared, calendar: Calendar = .autoupdatingCurrent) {
        client = RemoteClient(base: URL(string: "https://api.todoist.com/api/v1")!, token: token, session: session, service: "Todoist")
        self.calendar = calendar
    }

    public func currentAccess() -> CalendarAccess {
        client.token.isEmpty ? .notDetermined : rejected ? .denied : .granted
    }

    public func requestAccess() async -> CalendarAccess { currentAccess() }
    public func lists() -> [ReminderListInfo] { projects }
    public func defaultListID() -> String? { inboxID ?? projects.first?.id }

    public func reminders(completedSince: Date) async throws -> [ReminderItem] {
        try await authorized {
            let projectRows = try await pages("projects")
            var items = try await pages("tasks").compactMap(item)
            let until = RemoteDates.utcString(Date().addingTimeInterval(60))
            // Its own page size: the docs give no maximum for this one, so keep the default.
            let done = try? await pages("tasks/completed/by_completion_date", key: "items", query: [
                URLQueryItem(name: "since", value: RemoteDates.utcString(completedSince)),
                URLQueryItem(name: "until", value: until),
            ], limit: nil)
            // A repeating task completed earlier is still open: keep only the open one.
            let open = Set(items.map(\.id))
            items += (done ?? []).compactMap(item).filter { !open.contains($0.id) }
                .map { var i = $0; i.isCompleted = true; return i }
            projects = projectRows.compactMap { row in
                guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
                if row["inbox_project"] as? Bool == true { inboxID = id }
                return ReminderListInfo(id: id, title: name, color: Self.color(row["color"] as? String))
            }
            known.read(items)
            return items
        }
    }

    public func save(_ item: ReminderItem) async throws -> ReminderItem {
        try await authorized {
            if item.isNew {
                var body: [String: Any] = ["content": item.title, "project_id": item.listID,
                                           "priority": Self.todoistPriority(item.priority)]
                if let notes = item.notes { body["description"] = notes }
                body.merge(dueFields(item)) { $1 }
                let row = try await client.send("POST", "tasks", body: body) as? [String: Any]
                return row.flatMap(self.item) ?? item
            }
            let before = known[item.id]
            var body: [String: Any] = [:]
            if before?.title != item.title { body["content"] = item.title }
            if before?.due != item.due || before?.dueHasTime != item.dueHasTime { body.merge(dueFields(item)) { $1 } }
            if before?.notes != item.notes { body["description"] = item.notes ?? "" }
            if before?.priority != item.priority { body["priority"] = Self.todoistPriority(item.priority) }
            if !body.isEmpty { try await client.send("POST", "tasks/\(item.id)", body: body) }
            if before?.isCompleted != item.isCompleted {
                try await client.send("POST", "tasks/\(item.id)/\(item.isCompleted ? "close" : "reopen")", body: nil)
            }
            known.saved(item)
            return item
        }
    }

    public func remove(_ item: ReminderItem) async throws {
        try await authorized { try await client.send("DELETE", "tasks/\(item.id)", body: nil) }
    }

    public func link(for item: ReminderItem) -> URL? {
        URL(string: "https://app.todoist.com/app/task/\(item.id)")
    }

    // MARK: Private

    @discardableResult
    private func authorized<T>(_ body: () async throws -> T) async throws -> T {
        do {
            let result = try await body()
            rejected = false
            return result
        } catch RemoteClient.Failure.unauthorized {
            rejected = true
            throw ReminderSourceError("Todoist didn't accept the API token. Check it in Settings → Reminders.")
        }
    }

    /// Every page of a paginated list.
    private func pages(_ path: String, key: String = "results", query: [URLQueryItem] = [],
                       limit: Int? = 200) async throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        var cursor: String?
        repeat {
            var q = query + (limit.map { [URLQueryItem(name: "limit", value: "\($0)")] } ?? [])
            if let cursor { q.append(URLQueryItem(name: "cursor", value: cursor)) }
            let page = try await client.get(path, query: q) as? [String: Any] ?? [:]
            rows += page[key] as? [[String: Any]] ?? []
            cursor = page["next_cursor"] as? String
        } while cursor != nil && rows.count < 5000
        return rows
    }

    private func item(_ row: [String: Any]) -> ReminderItem? {
        guard let id = row["id"] as? String, let title = row["content"] as? String else { return nil }
        var due: Date?
        var hasTime = false
        let dueRow = row["due"] as? [String: Any]
        if let dueRow, let text = dueRow["date"] as? String {
            if text.count <= 10 {
                due = RemoteDates.day(text, in: calendar.timeZone)
            } else {
                due = RemoteDates.dateTime(text, floating: calendar.timeZone)
                hasTime = due != nil
            }
        }
        let completedAt = (row["completed_at"] as? String).flatMap { RemoteDates.dateTime($0, floating: calendar.timeZone) }
        let description = row["description"] as? String
        return ReminderItem(
            id: id, title: title, listID: row["project_id"] as? String ?? "", due: due, dueHasTime: hasTime,
            isCompleted: row["checked"] as? Bool ?? false, completionDate: completedAt,
            notes: description?.isEmpty == false ? description : nil,
            priority: Self.priority(todoist: row["priority"] as? Int ?? 1),
            isRepeating: dueRow?["is_recurring"] as? Bool ?? false
        )
    }

    /// Todoist's 4 is its top ("p1"), 1 is normal.
    static func priority(todoist value: Int) -> ReminderPriority {
        switch value {
        case 4: .high
        case 3: .medium
        case 2: .low
        default: .none
        }
    }

    static func todoistPriority(_ priority: ReminderPriority) -> Int { priority.rawValue + 1 }

    private func dueFields(_ item: ReminderItem) -> [String: Any] {
        guard let due = item.due else { return ["due_string": "no date"] }
        return item.dueHasTime
            ? ["due_datetime": RemoteDates.utcString(due)]
            : ["due_date": RemoteDates.dayString(due, in: calendar.timeZone)]
    }

    /// Todoist's named project colours.
    static func color(_ name: String?) -> RGBA {
        let hex: [String: UInt32] = [
            "berry_red": 0xB8256F, "red": 0xDB4035, "orange": 0xFF9933, "yellow": 0xFAD000, "olive_green": 0xAFB83B,
            "lime_green": 0x7ECC49, "green": 0x299438, "mint_green": 0x6ACCBC, "teal": 0x158FAD, "sky_blue": 0x14AAF5,
            "light_blue": 0x96C3EB, "blue": 0x4073FF, "grape": 0x884DFF, "violet": 0xAF38EB, "lavender": 0xEB96EB,
            "magenta": 0xE05194, "salmon": 0xFF8D85, "charcoal": 0x808080, "grey": 0xB8B8B8, "taupe": 0xCCAC93,
        ]
        return name.flatMap { hex[$0] }.map(RGBA.init(hex:)) ?? RGBA(hex: 0x808080)
    }
}

// MARK: - TickTick

/// Reminders from TickTick (Open API) with a personal API token (TickTick → Settings →
/// Account → API Token). Lists are the projects plus the Inbox.
@MainActor
public final class TickTickSource: ReminderSource {
    public var onChange: (() -> Void)?

    private let client: RemoteClient
    private let calendar: Calendar
    private var projects: [ReminderListInfo] = []
    private var inboxID = "inbox"
    private var rejected = false
    private var known = KnownTasks()

    public static let tokenAccount = "ticktick"
    public static let tokenPage = URL(string: "https://ticktick.com/webapp/#settings/account")!

    public init(token: String, session: URLSession = .shared, calendar: Calendar = .autoupdatingCurrent) {
        client = RemoteClient(base: URL(string: "https://api.ticktick.com/open/v1")!, token: token, session: session, service: "TickTick")
        self.calendar = calendar
    }

    public func currentAccess() -> CalendarAccess {
        client.token.isEmpty ? .notDetermined : rejected ? .denied : .granted
    }

    public func requestAccess() async -> CalendarAccess { currentAccess() }
    public func lists() -> [ReminderListInfo] { projects }
    public func defaultListID() -> String? { inboxID }

    /// TickTick lists only open tasks; ones ticked here stay in view until the next day.
    public func reminders(completedSince: Date) async throws -> [ReminderItem] {
        try await authorized {
            let rows = try await client.get("project") as? [[String: Any]] ?? []
            let open = rows.filter { $0["closed"] as? Bool != true }
            var lists = open.compactMap { row -> ReminderListInfo? in
                guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
                return ReminderListInfo(id: id, title: name, color: (row["color"] as? String).flatMap(RGBA.init(hexString:)) ?? .fallback)
            }
            var items: [ReminderItem] = []
            for id in ["inbox"] + lists.map(\.id) {
                let data = try await client.get("project/\(id)/data") as? [String: Any] ?? [:]
                let tasks = (data["tasks"] as? [[String: Any]] ?? []).compactMap(item)
                if id == "inbox", let real = tasks.first?.listID { inboxID = real }
                items += tasks
            }
            lists.insert(ReminderListInfo(id: inboxID, title: "Inbox", color: RGBA(hex: 0x4772FA)), at: 0)
            projects = lists
            known.read(items)
            return items
        }
    }

    public func save(_ item: ReminderItem) async throws -> ReminderItem {
        try await authorized {
            if item.isNew {
                var body: [String: Any] = ["title": item.title, "projectId": item.listID,
                                           "priority": Self.tickTickPriority(item.priority)]
                if let notes = item.notes { body["content"] = notes }
                body.merge(dueFields(item)) { $1 }
                let row = try await client.send("POST", "task", body: body) as? [String: Any]
                return row.flatMap(self.item) ?? item
            }
            let before = known[item.id]
            if before?.isCompleted == false, item.isCompleted {
                try await client.send("POST", "project/\(item.listID)/task/\(item.id)/complete", body: nil)
            }
            var body: [String: Any] = ["id": item.id, "projectId": item.listID]
            if before?.title != item.title { body["title"] = item.title }
            if before?.due != item.due || before?.dueHasTime != item.dueHasTime { body.merge(dueFields(item)) { $1 } }
            if before?.notes != item.notes { body["content"] = item.notes ?? "" }
            if before?.priority != item.priority { body["priority"] = Self.tickTickPriority(item.priority) }
            // Reopening isn't a documented call; setting the status back is what TickTick's apps do.
            if before?.isCompleted == true, !item.isCompleted { body["status"] = 0 }
            if body.count > 2 { try await client.send("POST", "task/\(item.id)", body: body) }
            known.saved(item)
            return item
        }
    }

    public func remove(_ item: ReminderItem) async throws {
        try await authorized { try await client.send("DELETE", "project/\(item.listID)/task/\(item.id)", body: nil) }
    }

    public func link(for item: ReminderItem) -> URL? {
        URL(string: "https://ticktick.com/webapp/#p/\(item.listID)/tasks/\(item.id)")
    }

    // MARK: Private

    @discardableResult
    private func authorized<T>(_ body: () async throws -> T) async throws -> T {
        do {
            let result = try await body()
            rejected = false
            return result
        } catch RemoteClient.Failure.unauthorized {
            rejected = true
            throw ReminderSourceError("TickTick didn't accept the API token. Check it in Settings → Reminders.")
        }
    }

    private func item(_ row: [String: Any]) -> ReminderItem? {
        guard let id = row["id"] as? String, let title = row["title"] as? String else { return nil }
        let zone = (row["timeZone"] as? String).flatMap(TimeZone.init(identifier:)) ?? calendar.timeZone
        var due: Date?
        let allDay = row["isAllDay"] as? Bool ?? false
        if let text = row["dueDate"] as? String, let instant = RemoteDates.dateTime(text, floating: zone) {
            // An all-day date is midnight in the task's zone; keep the day, in ours.
            due = allDay ? RemoteDates.day(RemoteDates.dayString(instant, in: zone), in: calendar.timeZone) : instant
        }
        let status = row["status"] as? Int ?? 0
        let content = row["content"] as? String
        return ReminderItem(
            id: id, title: title, listID: row["projectId"] as? String ?? inboxID, due: due, dueHasTime: due != nil && !allDay,
            isCompleted: status != 0,
            completionDate: (row["completedTime"] as? String).flatMap { RemoteDates.dateTime($0, floating: zone) },
            notes: content?.isEmpty == false ? content : nil,
            priority: Self.priority(tickTick: row["priority"] as? Int ?? 0),
            isRepeating: (row["repeatFlag"] as? String).map { !$0.isEmpty } ?? false
        )
    }

    /// TickTick: 0 none, 1 low, 3 medium, 5 high.
    static func priority(tickTick value: Int) -> ReminderPriority {
        switch value {
        case 5...: .high
        case 3...4: .medium
        case 1...2: .low
        default: .none
        }
    }

    static func tickTickPriority(_ priority: ReminderPriority) -> Int { [0, 1, 3, 5][priority.rawValue] }

    private func dueFields(_ item: ReminderItem) -> [String: Any] {
        guard let due = item.due else { return ["dueDate": NSNull()] }
        let zone = calendar.timeZone
        let instant = item.dueHasTime ? due : calendar.startOfDay(for: due)
        return [
            "dueDate": RemoteDates.utcString(instant, format: "yyyy-MM-dd'T'HH:mm:ss'+0000'"),
            "isAllDay": !item.dueHasTime,
            "timeZone": zone.identifier,
        ]
    }
}

extension RGBA {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// "#F18181".
    init?(hexString: String) {
        let digits = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }
}
