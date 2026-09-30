import AppKit
import Foundation

/// Where a new Things to-do goes.
public enum ThingsContainer: Equatable, Sendable {
    case inbox, project(String), area(String)
    /// No project or area: scheduled if it has a date, else Things puts it in the Inbox.
    case none
}

public enum ThingsFailure: Error, Equatable {
    case notAllowed, notRunning, timedOut, notFound, other(String)
}

/// One read of Things: open to-dos, those completed since a day began, and which list each
/// is in.
public struct ThingsSnapshot: Decodable, Equatable, Sendable {
    public struct ToDo: Decodable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var notes: String?
        /// "open", "completed", "canceled".
        public var status: String
        /// "When": the day it's planned for.
        public var when: Date?
        /// Things' "due date": the deadline.
        public var deadline: Date?
        public var completed: Date?

        public init(id: String, name: String, notes: String? = nil, status: String = "open",
                    when: Date? = nil, deadline: Date? = nil, completed: Date? = nil) {
            self.id = id; self.name = name; self.notes = notes; self.status = status
            self.when = when; self.deadline = deadline; self.completed = completed
        }
    }

    public struct Container: Decodable, Equatable, Sendable {
        public var id: String
        public var name: String
        /// "project" or "area".
        public var kind: String
        public var toDoIDs: [String]

        public init(id: String, name: String, kind: String, toDoIDs: [String]) {
            self.id = id; self.name = name; self.kind = kind; self.toDoIDs = toDoIDs
        }
    }

    public var open: [ToDo]
    public var done: [ToDo]
    public var inbox: [String]
    public var lists: [Container]

    public init(open: [ToDo] = [], done: [ToDo] = [], inbox: [String] = [], lists: [Container] = []) {
        self.open = open; self.done = done; self.inbox = inbox; self.lists = lists
    }

    public static func decode(_ json: String) throws -> ThingsSnapshot {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = withFraction.date(from: text) ?? plain.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
            }
            return date
        }
        return try decoder.decode(ThingsSnapshot.self, from: Data(json.utf8))
    }
}

/// What `ThingsSource` needs from Things.
@MainActor
public protocol ThingsScripting: AnyObject {
    func isRunning() -> Bool
    /// Starts Things in the background.
    func launch() async
    func snapshot(completedSince: Date) async throws -> ThingsSnapshot
    func setStatus(id: String, completed: Bool) async throws
    func setName(id: String, name: String) async throws
    func setNotes(id: String, notes: String) async throws
    /// Sets "When" to `day`; nil moves it to Anytime.
    func schedule(id: String, on day: Date?) async throws
    /// Returns the new to-do's id.
    func create(name: String, notes: String?, in container: ThingsContainer, on day: Date?) async throws -> String
    /// Moves it to Things' Trash.
    func delete(id: String) async throws
}

/// Things through JavaScript for Automation. Built-in lists are addressed by id
/// (`TMInboxListSource`, `TMLogbookListSource`, `TMNextListSource` = Anytime), so it works
/// whatever language Things runs in. Every property is read in bulk, one Apple Event each.
@MainActor
public final class JXAThings: ThingsScripting {
    public static let bundleID = "com.culturedcode.ThingsMac"
    private let runner: OsaScriptRunner

    public init(runner: OsaScriptRunner = OsaScriptRunner()) { self.runner = runner }

    public func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    public func launch() async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        // Give it a moment to answer Apple Events.
        for _ in 0..<20 where !isRunning() { try? await Task.sleep(for: .milliseconds(250)) }
        try? await Task.sleep(for: .seconds(1))
    }

    public func snapshot(completedSince: Date) async throws -> ThingsSnapshot {
        let json = try await run(Self.readScript, ["since": ISO8601DateFormatter().string(from: completedSince)])
        do { return try ThingsSnapshot.decode(json) } catch { throw ThingsFailure.other("Things answered in a way Sticky Calendar doesn't understand.") }
    }

    public func setStatus(id: String, completed: Bool) async throws {
        _ = try await run("T.toDos.byId(args.id).status = args.status; ''", ["id": id, "status": completed ? "completed" : "open"])
    }

    public func setName(id: String, name: String) async throws {
        _ = try await run("T.toDos.byId(args.id).name = args.name; ''", ["id": id, "name": name])
    }

    public func setNotes(id: String, notes: String) async throws {
        _ = try await run("T.toDos.byId(args.id).notes = args.notes; ''", ["id": id, "notes": notes])
    }

    public func schedule(id: String, on day: Date?) async throws {
        _ = try await run("""
            const t = T.toDos.byId(args.id);
            if (args.day) { T.schedule(t, {for: new Date(args.day)}); } else { T.move(t, {to: T.lists.byId('TMNextListSource')}); }
            ''
            """, ["id": id, "day": day.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()])
    }

    public func create(name: String, notes: String?, in container: ThingsContainer, on day: Date?) async throws -> String {
        let (kind, containerID): (String, String) = switch container {
        case .inbox: ("inbox", "")
        case let .project(id): ("project", id)
        case let .area(id): ("area", id)
        case .none: ("none", "")
        }
        return try await run("""
            const t = T.ToDo({name: args.name, notes: args.notes || ''});
            if (args.kind === 'project') { T.projects.byId(args.container).toDos.push(t); }
            else if (args.kind === 'area') { T.areas.byId(args.container).toDos.push(t); }
            else { T.lists.byId('TMInboxListSource').toDos.push(t); }
            const made = T.toDos.byId(t.id());
            if (args.day) { T.schedule(made, {for: new Date(args.day)}); }
            made.id()
            """, ["name": name, "notes": notes ?? "", "kind": kind, "container": containerID,
                  "day": day.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()])
    }

    public func delete(id: String) async throws {
        _ = try await run("T.delete(T.toDos.byId(args.id)); ''", ["id": id])
    }

    private func run(_ body: String, _ args: [String: Any]) async throws -> String {
        do {
            return try await runner.run("const T = Application('\(Self.bundleID)');\n\(body)", args: args)
        } catch let failure as OsaScriptRunner.Failure {
            switch failure {
            case .notAllowed: throw ThingsFailure.notAllowed
            case .appNotRunning: throw ThingsFailure.notRunning
            case .noSuchObject: throw ThingsFailure.notFound
            case .timedOut: throw ThingsFailure.timedOut
            case let .failed(_, message): throw ThingsFailure.other(message)
            }
        }
    }

    /// Reads everything in bulk. Projects are to-dos too in Things' dictionary, so they're
    /// left out of the open to-dos by id, and so are those in the Trash.
    static let readScript = """
        function iso(d) { return d ? d.toISOString() : null; }
        function bulk(items) {
          const ids = items.id();
          if (ids.length === 0) { return []; }
          const names = items.name(), notes = items.notes(), status = items.status(),
                when = items.activationDate(), deadline = items.dueDate(), done = items.completionDate();
          return ids.map((id, i) => ({id: id, name: names[i], notes: notes[i], status: status[i],
                                     when: iso(when[i]), deadline: iso(deadline[i]), completed: iso(done[i])}));
        }
        const projects = T.projects.whose({status: 'open'});
        const projectIDs = projects.id(), projectNames = projects.name();
        // Things keeps deleted to-dos in its Trash with status "open", so leave those out too.
        const trashIDs = T.lists.byId('TMTrashListSource').toDos.id();
        const open = bulk(T.toDos.whose({status: 'open'})).filter(t => projectIDs.indexOf(t.id) < 0 && trashIDs.indexOf(t.id) < 0);
        const done = bulk(T.lists.byId('TMLogbookListSource').toDos.whose({completionDate: {_greaterThan: new Date(args.since)}}));
        const lists = [];
        projectIDs.forEach((id, i) => lists.push({id: id, name: projectNames[i], kind: 'project', toDoIDs: T.projects.byId(id).toDos.id()}));
        const areaIDs = T.areas.id(), areaNames = T.areas.name();
        areaIDs.forEach((id, i) => lists.push({id: id, name: areaNames[i], kind: 'area', toDoIDs: T.areas.byId(id).toDos.id()}));
        JSON.stringify({open: open, done: done, inbox: T.lists.byId('TMInboxListSource').toDos.id(), lists: lists})
        """
}
