import Foundation

/// Answers a test's requests from a handler, without the network. Each session carries its
/// own id header, so tests running in parallel don't see each other's requests.
final class StubHTTP: URLProtocol, @unchecked Sendable {
    struct Call: Sendable {
        let method: String
        let path: String
        let query: [String: String]
        let body: [String: any Sendable]
        let headers: [String: String]
    }

    typealias Handler = @Sendable (Call) -> (status: Int, json: Any)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var calls: [String: [Call]] = [:]

    /// A session whose requests go to `handler`; `log()` returns what was asked.
    static func session(_ handler: @escaping Handler) -> (URLSession, log: () -> [Call]) {
        let id = UUID().uuidString
        lock.withLock { handlers[id] = handler; calls[id] = [] }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubHTTP.self]
        config.httpAdditionalHeaders = ["X-Stub": id]
        return (URLSession(configuration: config), { lock.withLock { calls[id] ?? [] } })
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Stub") ?? ""
        let url = request.url!
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var bodyData = request.httpBody
        if bodyData == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            bodyData = data
        }
        var body = bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        if body.isEmpty, let bodyData, let text = String(data: bodyData, encoding: .utf8), text.contains("=") {
            // A form (OAuth's token endpoint).
            var form = URLComponents()
            form.percentEncodedQuery = text
            for item in form.queryItems ?? [] { body[item.name] = item.value ?? "" }
        }
        let call = Call(
            method: request.httpMethod ?? "GET", path: url.path,
            query: Dictionary(uniqueKeysWithValues: (parts?.queryItems ?? []).map { ($0.name, $0.value ?? "") }),
            body: body.mapValues { "\($0)" },
            headers: request.allHTTPHeaderFields ?? [:]
        )
        let handler = Self.lock.withLock { () -> Handler? in
            Self.calls[id, default: []].append(call)
            return Self.handlers[id]
        }
        let (status, json) = handler?(call) ?? (404, [:])
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        var headers = ["Content-Type": "application/json"]
        if status == 429 { headers["Retry-After"] = "0" }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
