import Foundation
import Observation

/// `MAJOR.MINOR.PATCH[-prerelease]`, with an optional leading `v`. Missing parts count as 0.
public struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let pieces = text.split(separator: "-", maxSplits: 1).map(String.init)
        guard let core = pieces.first, !core.isEmpty else { return nil }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(numbers.count), numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        major = numbers[0]!
        minor = numbers.count > 1 ? numbers[1]! : 0
        patch = numbers.count > 2 ? numbers[2]! : 0
        prerelease = pieces.count > 1 ? pieces[1] : nil
    }

    public var isPrerelease: Bool { prerelease != nil }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "")
    }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) {
            return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }
        switch (a.prerelease, b.prerelease) {
        case (nil, nil), (nil, _): return false // a release is never older than its pre-release
        case (_, nil): return true
        case let (x?, y?): return x < y
        }
    }
}

public struct ReleaseInfo: Equatable, Sendable {
    public let version: SemanticVersion
    public let pageURL: URL
}

public enum UpdateStatus: Equatable, Sendable {
    /// Never checked, or the check failed (offline, private repo, rate limit, bad reply).
    case unknown
    case upToDate
    case available(ReleaseInfo)
}

/// Fetches the raw "latest release" reply. Injected so tests never touch the network.
public protocol ReleaseFetcher: Sendable {
    func fetchLatestRelease() async throws -> (statusCode: Int, body: Data)
}

public struct GitHubReleaseFetcher: ReleaseFetcher {
    public static let repository = "ievlevpn/sticky-calendar"
    public let url: URL

    public init(repository: String = GitHubReleaseFetcher.repository) {
        url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    public func fetchLatestRelease() async throws -> (statusCode: Int, body: Data) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

public enum ReleaseParser {
    private struct Payload: Decodable {
        let tag_name: String
        let html_url: URL
    }

    /// The release described by a GitHub "latest release" reply, or nil for anything else.
    public static func parse(statusCode: Int, body: Data) -> ReleaseInfo? {
        guard statusCode == 200,
              let payload = try? JSONDecoder().decode(Payload.self, from: body),
              let version = SemanticVersion(payload.tag_name) else { return nil }
        return ReleaseInfo(version: version, pageURL: payload.html_url)
    }
}

/// Tells whether a newer release exists on GitHub. Never downloads or installs anything.
@MainActor
@Observable
public final class UpdateChecker {
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    private enum Key {
        static let automaticChecks = "automaticUpdateChecks"
        static let lastCheck = "lastUpdateCheck"
    }

    public private(set) var status: UpdateStatus = .unknown
    public private(set) var automaticChecksEnabled: Bool
    public private(set) var lastCheck: Date?
    /// Whether this session's most recent check failed (as opposed to not having run).
    public private(set) var lastCheckFailed = false
    public let currentVersion: String

    @ObservationIgnored private let fetcher: ReleaseFetcher
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date

    public init(
        currentVersion: String,
        fetcher: ReleaseFetcher = GitHubReleaseFetcher(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.currentVersion = currentVersion
        self.fetcher = fetcher
        self.defaults = defaults
        self.now = now
        automaticChecksEnabled = defaults.object(forKey: Key.automaticChecks) as? Bool ?? true
        lastCheck = defaults.object(forKey: Key.lastCheck) as? Date
    }

    /// Local builds (`0.0.0-dev`, or anything unparseable) never report updates.
    public var isDevelopmentBuild: Bool {
        guard let version = SemanticVersion(currentVersion) else { return true }
        return version.isPrerelease
    }

    /// One line for Settings.
    public var summary: String {
        if isDevelopmentBuild { return "Development build — update checks are off." }
        switch status {
        case .available(let info): return "Version \(info.version) is available."
        case .upToDate: return "Sticky Calendar is up to date."
        case .unknown: return lastCheckFailed ? "Couldn't check for updates." : "Not checked yet."
        }
    }

    public func setAutomaticChecks(_ enabled: Bool) {
        automaticChecksEnabled = enabled
        defaults.set(enabled, forKey: Key.automaticChecks)
    }

    /// Checks if automatic checks are on and the last one was at least a day ago.
    public func checkIfDue() async {
        guard automaticChecksEnabled else { return }
        if let lastCheck, now().timeIntervalSince(lastCheck) < Self.checkInterval { return }
        await checkNow()
    }

    /// Checks regardless of the schedule and returns the outcome.
    @discardableResult
    public func checkNow() async -> UpdateStatus {
        guard !isDevelopmentBuild, let current = SemanticVersion(currentVersion) else {
            status = .unknown
            return status
        }
        lastCheck = now()
        defaults.set(lastCheck, forKey: Key.lastCheck)
        guard let reply = try? await fetcher.fetchLatestRelease(),
              let latest = ReleaseParser.parse(statusCode: reply.statusCode, body: reply.body) else {
            status = .unknown
            lastCheckFailed = true
            return status
        }
        lastCheckFailed = false
        status = !latest.version.isPrerelease && current < latest.version ? .available(latest) : .upToDate
        return status
    }
}

/// How this copy of the app was installed, which decides how to update it.
public enum InstallMethod: Equatable, Sendable {
    case homebrew, direct

    public static let caskName = "sticky-calendar"
    public static let upgradeCommand = "brew upgrade --cask \(caskName)"

    public static func detect(fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> InstallMethod {
        let caskrooms = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
        return caskrooms.contains { fileExists("\($0)/\(caskName)") } ? .homebrew : .direct
    }
}
