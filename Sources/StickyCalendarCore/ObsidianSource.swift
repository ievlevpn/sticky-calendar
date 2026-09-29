import CoreServices
import Foundation

/// Reminders from the tasks in an Obsidian vault's Markdown files (Tasks plugin format, see
/// `ObsidianTask`). Each file with tasks is a list; new ones go to `inboxPath`. Changes
/// rewrite just the task's line; the vault is watched, so edits in Obsidian show up.
@MainActor
public final class ObsidianSource: ReminderSource {
    public var onChange: (() -> Void)?

    public let vault: URL
    /// Relative to the vault, e.g. "Inbox.md".
    public let inboxPath: String
    private let calendar: Calendar
    /// The line each reminder was read from, to find it again when writing.
    private var known: [String: (path: String, line: Int, text: String)] = [:]
    private var files: [String] = []
    private var watcher: VaultWatcher?

    public init(vault: URL, inboxPath: String, calendar: Calendar = .autoupdatingCurrent) {
        self.vault = vault.standardizedFileURL
        self.inboxPath = Self.normalizedInboxPath(inboxPath)
        self.calendar = calendar
        watcher = VaultWatcher(folder: self.vault) { [weak self] in self?.onChange?() }
    }

    /// "Inbox" → "Inbox.md"; blank → "Inbox.md".
    public static func normalizedInboxPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let name = trimmed.isEmpty ? "Inbox" : trimmed
        return name.lowercased().hasSuffix(".md") ? name : name + ".md"
    }

    public func currentAccess() -> CalendarAccess {
        var isFolder: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: vault.path, isDirectory: &isFolder)
        return exists && isFolder.boolValue && FileManager.default.isReadableFile(atPath: vault.path) ? .granted : .denied
    }

    public func requestAccess() async -> CalendarAccess { currentAccess() }

    public func lists() -> [ReminderListInfo] {
        let paths = files.contains(inboxPath) ? files : [inboxPath] + files
        return paths.map { path in
            ReminderListInfo(id: path, title: Self.title(of: path), color: Self.color(for: path))
        }
    }

    public func defaultListID() -> String? { inboxPath }

    public func reminders(completedSince: Date) async throws -> [ReminderItem] {
        let vault = vault
        let calendar = calendar
        let scanned = await Task.detached { Self.scan(vault) }.value
        known = [:]
        var items: [ReminderItem] = []
        for entry in scanned.tasks {
            guard let task = ObsidianTask(line: entry.text) else { continue }
            let done = task.doneDate(calendar: calendar)
            if task.isDone, (done ?? .distantPast) < completedSince { continue }
            let id = "\(entry.path)#\(entry.line)"
            known[id] = (entry.path, entry.line, entry.text)
            let due = task.due(calendar: calendar)
            items.append(ReminderItem(
                id: id, title: task.title, listID: entry.path, due: due?.date, dueHasTime: due?.hasTime ?? false,
                isCompleted: task.isDone, completionDate: done
            ))
        }
        files = scanned.files
        return items
    }

    public func save(_ item: ReminderItem) async throws -> ReminderItem {
        if item.isNew {
            var task = ObsidianTask(title: item.title)
            task.setDue(item.due, hasTime: item.dueHasTime, calendar: calendar)
            let line = try append(task.line, to: item.listID)
            var saved = item
            saved.id = "\(item.listID)#\(line)"
            known[saved.id] = (item.listID, line, task.line)
            return saved
        }
        let (path, index, text) = try locate(item)
        guard var task = ObsidianTask(line: text) else { throw ReminderSourceError("That task is no longer in \(path).") }
        task.title = item.title
        if task.isDone != item.isCompleted { task.setDone(item.isCompleted, on: Date(), calendar: calendar) }
        let current = task.due(calendar: calendar)
        if current?.date != item.due || (current?.hasTime ?? false) != item.dueHasTime {
            task.setDue(item.due, hasTime: item.dueHasTime, calendar: calendar)
        }
        try rewrite(path) { lines in lines[index] = task.line }
        known[item.id] = (path, index, task.line)
        var saved = item
        saved.completionDate = task.doneDate(calendar: calendar)
        return saved
    }

    public func remove(_ item: ReminderItem) async throws {
        let (path, index, _) = try locate(item)
        try rewrite(path) { lines in lines.remove(at: index) }
        known[item.id] = nil
    }

    public func link(for item: ReminderItem) -> URL? {
        let path = known[item.id]?.path ?? item.listID
        var parts = URLComponents()
        parts.scheme = "obsidian"
        parts.host = "open"
        parts.queryItems = [URLQueryItem(name: "path", value: vault.appendingPathComponent(path).path)]
        return parts.url
    }

    // MARK: Files

    /// Where the task is now: its line if unchanged, else the same text elsewhere in the file.
    private func locate(_ item: ReminderItem) throws -> (String, Int, String) {
        guard let entry = known[item.id] else { throw ReminderSourceError("That task is no longer in the vault.") }
        let lines = try Self.lines(of: vault.appendingPathComponent(entry.path))
        if entry.line < lines.count, lines[entry.line] == entry.text { return (entry.path, entry.line, entry.text) }
        if let moved = lines.firstIndex(of: entry.text) { return (entry.path, moved, entry.text) }
        throw ReminderSourceError("That task was changed in Obsidian; showing the latest.")
    }

    /// Appends a line (after a line break if the file doesn't end with one), creating the
    /// file and its folders if needed. Returns the new line's index.
    private func append(_ line: String, to path: String) throws -> Int {
        let url = vault.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var lines = (try? Self.lines(of: url)) ?? []
        if lines.last == "" { lines.removeLast() }
        lines.append(line)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return lines.count - 1
    }

    private func rewrite(_ path: String, _ change: (inout [String]) -> Void) throws {
        let url = vault.appendingPathComponent(path)
        let original = try String(contentsOf: url, encoding: .utf8)
        var lines = original.components(separatedBy: "\n")
        change(&lines)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private nonisolated static func lines(of url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
    }

    /// Task lines of every Markdown file, skipping hidden folders (.obsidian, .trash, .git).
    nonisolated static func scan(_ vault: URL) -> (tasks: [(path: String, line: Int, text: String)], files: [String]) {
        guard let walker = FileManager.default.enumerator(
            at: vault, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return ([], []) }
        var tasks: [(String, Int, String)] = []
        var files: Set<String> = []
        let root = vault.standardizedFileURL.path
        for case let url as URL in walker where url.pathExtension.lowercased() == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8), text.contains("[") else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(root.count + 1))
            for (index, line) in text.components(separatedBy: "\n").enumerated() where ObsidianTask(line: line) != nil {
                tasks.append((path, index, line))
                files.insert(path)
            }
        }
        return (tasks, files.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    private static func title(of path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// A steady colour per file, from a small palette.
    private static func color(for path: String) -> RGBA {
        let palette = [
            RGBA(red: 0.53, green: 0.36, blue: 0.96), RGBA(red: 0.2, green: 0.55, blue: 0.98),
            RGBA(red: 0.2, green: 0.72, blue: 0.4), RGBA(red: 1.0, green: 0.58, blue: 0.0),
            RGBA(red: 0.95, green: 0.3, blue: 0.4), RGBA(red: 0.1, green: 0.7, blue: 0.75),
        ]
        let hash = path.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return palette[Int(hash % UInt32(palette.count))]
    }
}

/// Calls back (on the main thread, at most every second) when anything in `folder` changes.
final class VaultWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void

    init(folder: URL, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { watcher.onChange() } }
        }, &context, [folder.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
