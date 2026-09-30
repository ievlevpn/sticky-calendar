import Foundation

/// Runs JavaScript for Automation with /usr/bin/osascript, in its own process: off the main
/// thread, stoppable after a time limit, and with the Automation permission asked for on
/// behalf of this app (macOS attributes a child process's Apple Events to its parent).
public struct OsaScriptRunner: Sendable {
    public enum Failure: Error, Equatable {
        /// -1743: the user hasn't allowed this app to control the other one.
        case notAllowed
        /// -600: the app isn't running.
        case appNotRunning
        /// -1728: no such object (e.g. a to-do deleted meanwhile).
        case noSuchObject
        case timedOut
        case failed(code: Int?, message: String)
    }

    public let timeout: Duration

    public init(timeout: Duration = .seconds(20)) { self.timeout = timeout }

    /// Runs `script` with `args` available to it as the constant `args`, and returns what the
    /// script's last expression evaluates to, as text. Arguments go in as a JSON literal, so
    /// no text in them can end a string or run as code.
    public func run(_ script: String, args: Any = [String: Any]()) async throws -> String {
        let json = try JSONSerialization.data(withJSONObject: args, options: [.fragmentsAllowed])
        let source = "const args = \(String(decoding: json, as: UTF8.self));\n\(script)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-"]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let exited = AsyncStream<Void> { continuation in
            process.terminationHandler = { _ in continuation.yield(); continuation.finish() }
        }
        try process.run()
        // Read while it runs: a full pipe would otherwise stall it.
        let out = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
        let err = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }
        input.fileHandleForWriting.write(Data(source.utf8))
        try? input.fileHandleForWriting.close()
        let timedOut = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in exited {}; return false }
            group.addTask { try? await Task.sleep(for: timeout); return true }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        if timedOut, process.isRunning {
            process.terminate()
            throw Failure.timedOut
        }
        let text = String(decoding: await out.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            let message = String(decoding: await err.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Self.failure(from: message)
        }
        return text
    }

    /// "execution error: Error: Not authorized to send Apple events to Things3. (-1743)"
    static func failure(from message: String) -> Failure {
        let pattern = try! NSRegularExpression(pattern: #"\((-?\d+)\)\s*$"#)
        let range = NSRange(message.startIndex..., in: message)
        let code = pattern.firstMatch(in: message, range: range)
            .flatMap { Range($0.range(at: 1), in: message) }
            .flatMap { Int(message[$0]) }
        switch code {
        case -1743: return .notAllowed
        case -600: return .appNotRunning
        case -1728: return .noSuchObject
        default: return .failed(code: code, message: message)
        }
    }
}
