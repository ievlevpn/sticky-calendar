import Foundation
import Network

/// Waits, on a free port reachable only from this Mac, for the browser to come back from
/// Microsoft's sign-in with a code. Answers that one request with a page the user can close,
/// ignores anything else (a favicon, a wrong `state`), and stops after one code, an error,
/// a cancel, or its time limit.
public final class LoopbackRedirect: @unchecked Sendable {
    public enum Failure: Error, Equatable {
        case cancelled, timedOut, couldNotListen
        /// Microsoft sent an error back (e.g. the user declined).
        case denied(String)
    }

    private let state: String
    private let timeout: Duration
    private let queue = DispatchQueue(label: "LoopbackRedirect")
    private let lock = NSLock()
    private var listener: NWListener?
    private var timer: Task<Void, Never>?
    private var outcome: Result<String, Failure>?
    private var waiter: CheckedContinuation<String, Error>?

    /// A one-way switch: `set()` is true only the first time.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var isSet = false
        func set() -> Bool { lock.withLock { defer { isSet = true }; return !isSet } }
    }

    public init(state: String, timeout: Duration = .seconds(300)) {
        self.state = state
        self.timeout = timeout
    }

    /// Starts listening; returns the redirect URI to give Microsoft. The time limit runs from here.
    public func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.acceptLocalOnly = true
        let listener: NWListener
        do { listener = try NWListener(using: parameters, on: .any) } catch { throw Failure.couldNotListen }
        let alreadyFinished = lock.withLock {
            if outcome == nil { self.listener = listener }
            return outcome != nil
        }
        if alreadyFinished { throw Failure.cancelled }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        let port: UInt16
        do {
            port = try await withCheckedThrowingContinuation { continuation in
                let resumed = Flag()
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard resumed.set() else { return }
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    case .failed, .cancelled:
                        guard resumed.set() else { return }
                        continuation.resume(throwing: Failure.couldNotListen)
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            }
        } catch {
            listener.cancel()
            throw error
        }
        let limit = timeout
        let timer = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled else { return }
            self?.finish(.failure(.timedOut))
        }
        let done = lock.withLock {
            if outcome == nil { self.timer = timer }
            return outcome != nil
        }
        if done { timer.cancel() }
        return URL(string: "http://localhost:\(port)")!
    }

    /// Waits for the code.
    public func code() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let outcome {
                lock.unlock()
                continuation.resume(with: outcome.mapError { $0 as Error })
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    public func cancel() { finish(.failure(.cancelled)) }

    /// Records the first outcome, wakes the waiter once, and shuts the listener and timer down.
    private func finish(_ result: Result<String, Failure>) {
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = result
        let waiter = waiter
        self.waiter = nil
        let listener = listener
        self.listener = nil
        let timer = timer
        self.timer = nil
        lock.unlock()
        listener?.cancel()
        timer?.cancel()
        waiter?.resume(with: result.mapError { $0 as Error })
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self else { return connection.cancel() }
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let target = request.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? ""
            let parts = URLComponents(string: "http://localhost\(target)")
            let query = Dictionary((parts?.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { a, _ in a }
            guard parts?.path == "/" || parts?.path == "", query["code"] != nil || query["error"] != nil else {
                return self.reply(connection, status: "404 Not Found", message: "Nothing here.")
            }
            guard query["state"] == self.state else {
                return self.reply(connection, status: "400 Bad Request", message: "This sign-in link doesn't match. Try again from Sticky Calendar.")
            }
            if let error = query["error"] {
                let reason = query["error_description"].flatMap { $0.isEmpty ? nil : $0 } ?? error
                self.reply(connection, status: "200 OK", message: "Sign-in didn't finish: \(reason)")
                self.finish(.failure(.denied(reason)))
            } else if let code = query["code"] {
                self.reply(connection, status: "200 OK", message: "Signed in to Sticky Calendar. You can close this tab.")
                self.finish(.success(code))
            }
        }
    }

    private func reply(_ connection: NWConnection, status: String, message: String) {
        let escaped = message.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        let body = """
            <!doctype html><meta charset="utf-8"><title>Sticky Calendar</title>
            <body style="font: 15px -apple-system, sans-serif; margin: 3em; color: #333">\(escaped)</body>
            """
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
