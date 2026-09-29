import Foundation

/// Finds an event's video-call link (Zoom, Meet, Teams, Webex…) so it can be joined from
/// the timeline: the event's URL first, then its location, then its notes.
public enum MeetingLink {
    /// Hosts (and their subdomains) that serve meetings.
    static let hosts = [
        "zoom.us", "zoomgov.com", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "meet.jit.si", "facetime.apple.com", "chime.aws",
        "gotomeeting.com", "meet.goto.com", "around.co", "bluejeans.com",
    ]
    /// App schemes that open a meeting directly.
    static let schemes = ["zoommtg", "zoomus", "msteams"]

    public static func find(in item: EventItem) -> URL? {
        if let url = item.url, isMeeting(url) { return url }
        for text in [item.location, item.notes].compactMap({ $0 }) {
            if let url = links(in: text).first(where: isMeeting) { return url }
        }
        return nil
    }

    static func isMeeting(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if schemes.contains(scheme) { return true }
        guard scheme == "https" || scheme == "http", let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func links(in text: String) -> [URL] {
        detector.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).compactMap(\.url)
    }
}
