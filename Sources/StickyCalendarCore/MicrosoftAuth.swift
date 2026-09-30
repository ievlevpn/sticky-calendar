import CryptoKit
import Foundation

/// A PKCE pair (RFC 7636): the app keeps the verifier and sends its hash.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func make() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return PKCE(verifier: base64URL(Data(bytes)))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Signing in to Microsoft (Entra ID, personal and work accounts) as a public client: no
/// secret, PKCE, and a redirect to a local port.
public enum MicrosoftAuth {
    /// The app's registration in Microsoft Entra (see RELEASING.md). Empty until registered,
    /// and then Microsoft To Do isn't offered.
    public static let clientID = ""
    public static let tokenAccount = "microsoftToDo"
    static let authority = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/")!
    static let scopes = "Tasks.ReadWrite offline_access"

    public static var isAvailable: Bool { !clientID.isEmpty }

    public static func authorizeURL(clientID: String = clientID, redirect: URL, pkce: PKCE, state: String) -> URL {
        var parts = URLComponents(url: authority.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirect.absoluteString),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return parts.url!
    }

    public static func randomState() -> String { PKCE.make().verifier }
}

/// Holds a Microsoft sign-in: the refresh token (kept in the keychain) and an access token
/// (in memory). Renewals happen one at a time, as Microsoft replaces the refresh token on
/// every use: parallel renewals would race, and the losers would be refused.
@MainActor
public final class MicrosoftSession {
    public enum Failure: Error, Equatable {
        /// Never signed in, or signed out.
        case signedOut
        /// Microsoft refused the refresh token (expired, revoked, password changed).
        case refused
    }

    private let clientID: String
    private let session: URLSession
    private let now: () -> Date
    private let keep: (String?) -> Void
    private var refreshToken: String?
    private var accessToken: String?
    private var expiry = Date.distantPast
    private var renewal: Task<String, Error>?

    public init(clientID: String = MicrosoftAuth.clientID,
                refreshToken: String? = ReminderTokens.token(for: MicrosoftAuth.tokenAccount),
                session: URLSession = .shared, now: @escaping () -> Date = Date.init,
                keep: @escaping (String?) -> Void = { ReminderTokens.setToken($0, for: MicrosoftAuth.tokenAccount) }) {
        self.clientID = clientID
        self.refreshToken = refreshToken
        self.session = session
        self.now = now
        self.keep = keep
    }

    public var isSignedIn: Bool { refreshToken != nil }

    /// Finishes signing in with the code from the redirect.
    public func exchange(code: String, verifier: String, redirect: URL) async throws {
        _ = try await redeem(["grant_type": "authorization_code", "code": code,
                              "code_verifier": verifier, "redirect_uri": redirect.absoluteString])
    }

    /// A usable access token: the current one while it has 5 minutes left, else a renewed
    /// one; `renew` forces renewal (after a 401).
    public func token(renew: Bool) async throws -> String {
        if !renew, let accessToken, expiry > now().addingTimeInterval(300) { return accessToken }
        if let renewal { return try await renewal.value }
        guard let refreshToken else { throw Failure.signedOut }
        // Stored before the first suspension, and cleared by the task itself (on the main actor)
        // as it ends, whether it succeeded or failed, so no caller can see a finished task.
        let task = Task {
            defer { self.renewal = nil }
            return try await self.redeem(["grant_type": "refresh_token", "refresh_token": refreshToken])
        }
        renewal = task
        return try await task.value
    }

    public func signOut() {
        refreshToken = nil
        accessToken = nil
        keep(nil)
    }

    private func redeem(_ fields: [String: String]) async throws -> String {
        var request = URLRequest(url: MicrosoftAuth.authority.appendingPathComponent("token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = (fields.merging(["client_id": clientID, "scope": MicrosoftAuth.scopes]) { a, _ in a })
            .sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // "+" is literal in a query but a space in a form: encode it.
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ReminderSourceError("Couldn't reach Microsoft: \(error.localizedDescription)")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 400, json["error"] as? String == "invalid_grant" {
            signOut()
            throw Failure.refused
        }
        guard (200..<300).contains(status), let access = json["access_token"] as? String else {
            throw ReminderSourceError("Microsoft didn't accept the sign-in (error \(status)).")
        }
        accessToken = access
        expiry = now().addingTimeInterval(json["expires_in"] as? Double ?? 3600)
        if let refresh = json["refresh_token"] as? String {
            refreshToken = refresh
            keep(refresh)
        }
        return access
    }
}
