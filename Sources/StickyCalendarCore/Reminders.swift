import Foundation

public struct ReminderListInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var color: RGBA
    public var isWritable: Bool

    public init(id: String, title: String, color: RGBA = .fallback, isWritable: Bool = true) {
        self.id = id
        self.title = title
        self.color = color
        self.isWritable = isWritable
    }
}

/// A value-type snapshot of one reminder.
public struct ReminderItem: Identifiable, Equatable, Sendable {
    /// EventKit `calendarItemIdentifier`; empty for one not saved yet.
    public var id: String
    public var title: String
    public var listID: String
    /// When it's due; `dueHasTime` says whether the time of day counts or just the day.
    public var due: Date?
    public var dueHasTime: Bool
    public var isCompleted: Bool
    public var completionDate: Date?
    public var notes: String?
    public var priority: ReminderPriority
    /// It repeats: ticking it moves it to its next date and leaves it open.
    public var isRepeating: Bool
    /// A repeating one ticked here, still shown ticked: when it's due next.
    public var nextDue: Date?

    public init(
        id: String = "", title: String, listID: String, due: Date? = nil, dueHasTime: Bool = false,
        isCompleted: Bool = false, completionDate: Date? = nil, notes: String? = nil, priority: ReminderPriority = .none,
        isRepeating: Bool = false
    ) {
        self.id = id
        self.title = title
        self.listID = listID
        self.due = due
        self.dueHasTime = dueHasTime
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.notes = notes
        self.priority = priority
        self.isRepeating = isRepeating
    }

    public var isNew: Bool { id.isEmpty }
}

/// How important a reminder is; each source maps it to its own scale.
public enum ReminderPriority: Int, Sendable, CaseIterable, Comparable {
    case none, low, medium, high

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// "!", "!!", "!!!", as Reminders shows it.
    public var marks: String { String(repeating: "!", count: rawValue) }

    public var name: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

/// Everything the reminder store needs from a backend: Apple Reminders (`ReminderKitSource`),
/// Todoist, TickTick or an Obsidian vault.
@MainActor
public protocol ReminderSource: AnyObject {
    /// Called when the backend knows its data changed (including our own saves).
    var onChange: (() -> Void)? { get set }
    func currentAccess() -> CalendarAccess
    func requestAccess() async -> CalendarAccess
    /// The lists as of the last `reminders(completedSince:)`.
    func lists() -> [ReminderListInfo]
    func defaultListID() -> String?
    /// Every incomplete reminder, plus those completed since `completedSince`.
    func reminders(completedSince: Date) async throws -> [ReminderItem]
    /// Creates the reminder if `item.isNew`, otherwise updates it. Returns the saved state.
    func save(_ item: ReminderItem) async throws -> ReminderItem
    func remove(_ item: ReminderItem) async throws
    /// Opens the reminder in its own app (Reminders, Todoist, TickTick, Obsidian).
    func link(for item: ReminderItem) -> URL?
    /// Asks the backend to sync with its server before the next read (Apple Reminders);
    /// others fetch fresh anyway.
    func refreshIfNeeded()
    /// Whether notes can be written back (Obsidian's are read-only here).
    var canEditNotes: Bool { get }
}

public extension ReminderSource {
    func refreshIfNeeded() {}
    var canEditNotes: Bool { true }
}

/// A heading and its reminders, as the reminders view shows them.
public struct ReminderSection: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case overdue, today, list }
    public let id: String
    public let title: String
    public let kind: Kind
    /// The list's colour, for list sections.
    public let color: RGBA?
    public let items: [ReminderItem]

    public init(id: String, title: String, kind: Kind, color: RGBA?, items: [ReminderItem]) {
        self.id = id
        self.title = title
        self.kind = kind
        self.color = color
        self.items = items
    }
}

/// Where reminders appear: their own sticky, or a tab of the calendar sticky.
public enum ReminderPlacement: String, Sendable, CaseIterable {
    case window
    case tab
}

/// What the reminders view lists: overdue and today's, or whole lists.
public enum ReminderMode: String, Sendable, CaseIterable {
    case today
    case lists
}

/// Where reminders come from; asked the first time the reminders view opens.
public enum ReminderProvider: String, Sendable, CaseIterable {
    case appleReminders
    case todoist
    case tickTick
    case obsidian

    /// The app it opens, as in "Open Reminders".
    public var appName: String {
        self == .appleReminders ? "Reminders" : name
    }

    public var name: String {
        switch self {
        case .appleReminders: "Apple Reminders"
        case .todoist: "Todoist"
        case .tickTick: "TickTick"
        case .obsidian: "Obsidian"
        }
    }
}

/// The reminders window's own system-wide show/hide shortcut.
public enum RemindersHotKeyChoice: String, Sendable, CaseIterable {
    case off
    case controlOptionR
    case controlOptionCommandR

    public var symbol: String {
        switch self {
        case .off: "Off"
        case .controlOptionR: "⌃⌥R"
        case .controlOptionCommandR: "⌃⌥⌘R"
        }
    }
}

/// Reminder preferences, persisted in UserDefaults on every change.
@MainActor
@Observable
public final class ReminderSettings {
    private enum Key {
        static let placement = "reminderPlacement"
        static let mode = "reminderMode"
        static let showsCompleted = "remindersShowCompleted"
        static let hiddenListIDs = "hiddenReminderListIDs"
        static let isPinned = "remindersPinned"
        static let isVisible = "remindersVisible"
        static let hotKey = "remindersHotKey"
        static let provider = "reminderProvider"
        static let obsidianVault = "obsidianVaultPath"
        static let obsidianInbox = "obsidianInboxPath"
    }

    @ObservationIgnored private let defaults: UserDefaults

    public private(set) var placement: ReminderPlacement
    /// False until the user picks a placement: the first time reminders open (as a tab,
    /// the default) they ask whether to stay there or get their own window.
    public private(set) var isPlacementChosen: Bool
    public private(set) var mode: ReminderMode
    /// Also list reminders completed today (ones ticked just now stay regardless).
    public private(set) var showsCompleted: Bool
    public private(set) var hiddenListIDs: Set<String>
    /// The reminders window floats on top (window placement).
    public private(set) var isPinned: Bool
    /// The reminders window is open, or (tab placement) the tab is showing.
    public private(set) var isVisible: Bool
    public private(set) var hotKey: RemindersHotKeyChoice
    /// nil until chosen.
    public private(set) var provider: ReminderProvider?
    public private(set) var obsidianVaultPath: String?
    /// Relative to the vault; where new reminders go.
    public private(set) var obsidianInboxPath: String

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedPlacement = defaults.string(forKey: Key.placement).flatMap(ReminderPlacement.init(rawValue:))
        placement = storedPlacement ?? .tab
        isPlacementChosen = storedPlacement != nil
        mode = defaults.string(forKey: Key.mode).flatMap(ReminderMode.init(rawValue:)) ?? .today
        showsCompleted = defaults.bool(forKey: Key.showsCompleted)
        hiddenListIDs = Set(defaults.stringArray(forKey: Key.hiddenListIDs) ?? [])
        isPinned = defaults.object(forKey: Key.isPinned) as? Bool ?? true
        isVisible = defaults.bool(forKey: Key.isVisible)
        hotKey = defaults.string(forKey: Key.hotKey).flatMap(RemindersHotKeyChoice.init(rawValue:)) ?? .controlOptionR
        provider = defaults.string(forKey: Key.provider).flatMap(ReminderProvider.init(rawValue:))
        obsidianVaultPath = defaults.string(forKey: Key.obsidianVault)
        obsidianInboxPath = defaults.string(forKey: Key.obsidianInbox) ?? "Inbox.md"
    }

    /// nil forgets the choice, so the reminders view asks again.
    public func setProvider(_ value: ReminderProvider?) {
        provider = value
        defaults.set(value?.rawValue, forKey: Key.provider)
    }

    public func setObsidian(vault: String, inbox: String) {
        obsidianVaultPath = vault
        obsidianInboxPath = ObsidianSource.normalizedInboxPath(inbox)
        defaults.set(vault, forKey: Key.obsidianVault)
        defaults.set(obsidianInboxPath, forKey: Key.obsidianInbox)
    }

    public func setPlacement(_ value: ReminderPlacement) {
        placement = value
        isPlacementChosen = true
        defaults.set(value.rawValue, forKey: Key.placement)
    }

    public func setMode(_ value: ReminderMode) {
        mode = value
        defaults.set(value.rawValue, forKey: Key.mode)
    }

    public func setShowsCompleted(_ value: Bool) {
        showsCompleted = value
        defaults.set(value, forKey: Key.showsCompleted)
    }

    public func setList(_ id: String, visible: Bool) {
        if visible { hiddenListIDs.remove(id) } else { hiddenListIDs.insert(id) }
        defaults.set(hiddenListIDs.sorted(), forKey: Key.hiddenListIDs)
    }

    public func setPinned(_ value: Bool) {
        isPinned = value
        defaults.set(value, forKey: Key.isPinned)
    }

    public func setVisible(_ value: Bool) {
        isVisible = value
        defaults.set(value, forKey: Key.isVisible)
    }

    public func setHotKey(_ value: RemindersHotKeyChoice) {
        hotKey = value
        defaults.set(value.rawValue, forKey: Key.hotKey)
    }
}

/// A new reminder's title with any date in it taken out as the due date, like Reminders
/// does: "Call the bank tomorrow 10am" is due tomorrow at 10:00.
public struct ReminderInput: Equatable, Sendable {
    public var title: String
    public var due: Date?
    public var dueHasTime: Bool

    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    /// Whether the matched words name a time of day, not just a day.
    private static let timeWords = try! NSRegularExpression(
        pattern: #"\d{1,2}:\d{2}|\d\s*(am|pm|a\.m\.|p\.m\.)\b|\bnoon\b|\bmidnight\b|\b(at|@)\s*\d"#,
        options: [.caseInsensitive]
    )

    /// Relative words ("tomorrow") count from the current date.
    public static func parse(_ text: String) -> ReminderInput {
        let ns = text as NSString
        guard let match = detector.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let date = match.date else {
            return ReminderInput(title: text.trimmingCharacters(in: .whitespacesAndNewlines), due: nil, dueHasTime: false)
        }
        let words = ns.substring(with: match.range)
        let hasTime = timeWords.firstMatch(in: words, range: NSRange(location: 0, length: (words as NSString).length)) != nil
        var title = ns.replacingCharacters(in: match.range, with: " ")
        // "… on Friday", "… by tomorrow", "… at 5pm": drop the joining word left behind.
        title = title.replacingOccurrences(of: #"\s+(on|by|at|@|due)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        title = title.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // A title that was only a date keeps its words rather than going blank.
        if title.isEmpty { return ReminderInput(title: text.trimmingCharacters(in: .whitespaces), due: nil, dueHasTime: false) }
        return ReminderInput(title: title, due: date, dueHasTime: hasTime)
    }
}

/// Builds the source the settings name (nil when none is chosen or it isn't set up).
public enum ReminderSources {
    @MainActor
    public static func make(_ settings: ReminderSettings) -> ReminderSource? {
        switch settings.provider {
        case nil:
            nil
        case .appleReminders:
            ReminderKitSource()
        case .todoist:
            TodoistSource(token: ReminderTokens.token(for: TodoistSource.tokenAccount) ?? "")
        case .tickTick:
            TickTickSource(token: ReminderTokens.token(for: TickTickSource.tokenAccount) ?? "")
        case .obsidian:
            settings.obsidianVaultPath.map {
                ObsidianSource(vault: URL(fileURLWithPath: $0), inboxPath: settings.obsidianInboxPath)
            }
        }
    }
}

/// Letters of the query in order, anywhere in the text ("clbnk" finds "Call the bank"),
/// scored so that runs of consecutive letters and letters at the start of words rank higher.
public enum FuzzyMatch {
    /// nil when not every letter of `query` is found in order; higher is better.
    public static func score(_ query: String, in text: String) -> Int? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return nil }
        let hay = Array(text.lowercased())
        var score = 0
        var at = 0
        var previous = -2
        for letter in needle {
            guard let found = hay[at...].firstIndex(of: letter) else { return nil }
            score += 1
            if found == previous + 1 { score += 5 }                       // a run
            if found == 0 || !(hay[found - 1].isLetter || hay[found - 1].isNumber) { score += 3 } // word start
            previous = found
            at = found + 1
        }
        // Shorter texts with the same letters are closer matches.
        return score * 100 - hay.count
    }
}
