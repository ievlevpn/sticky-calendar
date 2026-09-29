import Foundation
import Testing
@testable import StickyCalendarCore

struct MeetingLinkTests {
    private func item(url: String? = nil, location: String? = nil, notes: String? = nil) -> EventItem {
        var e = event("m", at(10), at(11))
        e.url = url.flatMap(URL.init(string:))
        e.location = location
        e.notes = notes
        return e
    }

    @Test func findsTheLinkInUrlLocationOrNotes() {
        #expect(MeetingLink.find(in: item(url: "https://acme.zoom.us/j/123"))?.host == "acme.zoom.us")
        #expect(MeetingLink.find(in: item(location: "Room 4 / https://meet.google.com/abc-defg-hij"))?.host == "meet.google.com")
        let notes = "Agenda: https://docs.example.com/x\nJoin: https://teams.microsoft.com/l/meetup-join/19%3a"
        #expect(MeetingLink.find(in: item(notes: notes))?.host == "teams.microsoft.com")
    }

    @Test func prefersTheEventUrlAndSkipsOtherLinks() {
        let e = item(url: "https://whereby.com/room", notes: "https://zoom.us/j/1")
        #expect(MeetingLink.find(in: e)?.host == "whereby.com")
        #expect(MeetingLink.find(in: item(url: "https://example.com", location: "https://docs.google.com/x")) == nil)
    }

    @Test func acceptsMeetingAppSchemesButNotLookalikeHosts() {
        #expect(MeetingLink.find(in: item(url: "zoommtg://zoom.us/join?confno=1")) != nil)
        #expect(MeetingLink.find(in: item(location: "https://notzoom.us/j/1")) == nil)
    }
}
