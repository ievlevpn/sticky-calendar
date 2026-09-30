import Foundation
import Testing
@testable import StickyCalendarCore

@MainActor
struct MicrosoftAuthTests {
    final class Kept { var tokens: [String?] = [] }

    private static let tokenPath = "/common/oauth2/v2.0/token"

    @Test func pkceChallengeIsTheHashedVerifier() {
        // RFC 7636, appendix B.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(PKCE.make().verifier.count >= 43)
    }

    @Test func theAuthorizeURLCarriesEverything() {
        let pkce = PKCE(verifier: "v".padding(toLength: 43, withPad: "v", startingAt: 0))
        let url = MicrosoftAuth.authorizeURL(clientID: "cid", redirect: URL(string: "http://localhost:5555")!, pkce: pkce, state: "s1")
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: parts.queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(parts.host == "login.microsoftonline.com" && parts.path == "/common/oauth2/v2.0/authorize")
        #expect(query["client_id"] == "cid" && query["response_type"] == "code")
        #expect(query["redirect_uri"] == "http://localhost:5555" && query["scope"] == "Tasks.ReadWrite offline_access")
        #expect(query["code_challenge"] == pkce.challenge && query["code_challenge_method"] == "S256" && query["state"] == "s1")
    }

    @Test func exchangingACodeKeepsTheRefreshToken() async throws {
        let (session, log) = StubHTTP.session { _ in
            (200, ["access_token": "A1", "refresh_token": "R1", "expires_in": 3600])
        }
        let kept = Kept()
        let auth = MicrosoftSession(clientID: "cid", refreshToken: nil, session: session, now: { at(12) }, keep: { kept.tokens.append($0) })
        try await auth.exchange(code: "C", verifier: "V", redirect: URL(string: "http://localhost:5555")!)
        #expect(try await auth.token(renew: false) == "A1")
        #expect(kept.tokens == ["R1"] && auth.isSignedIn)
        let body = log()[0].body
        #expect(log()[0].path == Self.tokenPath && body["grant_type"] as? String == "authorization_code")
        #expect(body["code"] as? String == "C" && body["code_verifier"] as? String == "V" && body["client_id"] as? String == "cid")
        #expect(body["client_secret"] == nil)
    }

    @Test func anExpiringTokenIsRenewedOnceForManyCallers() async throws {
        let (session, log) = StubHTTP.session { call in
            (200, ["access_token": "A2", "refresh_token": "R2", "expires_in": 3600])
        }
        let kept = Kept()
        let auth = MicrosoftSession(clientID: "cid", refreshToken: "R1", session: session, now: { at(12) }, keep: { kept.tokens.append($0) })
        async let a = auth.token(renew: false)
        async let b = auth.token(renew: false)
        async let c = auth.token(renew: false)
        async let d = auth.token(renew: false)
        let tokens = try await [a, b, c, d]
        #expect(tokens == ["A2", "A2", "A2", "A2"])
        #expect(log().filter { $0.path == Self.tokenPath }.count == 1)
        #expect(log()[0].body["refresh_token"] as? String == "R1" && kept.tokens == ["R2"])
    }

    @Test func aRefusedRefreshSignsOut() async {
        let (session, _) = StubHTTP.session { _ in (400, ["error": "invalid_grant"]) }
        let kept = Kept()
        let auth = MicrosoftSession(clientID: "cid", refreshToken: "R1", session: session, now: { at(12) }, keep: { kept.tokens.append($0) })
        await #expect(throws: MicrosoftSession.Failure.refused) { try await auth.token(renew: true) }
        #expect(!auth.isSignedIn && kept.tokens == [nil])
    }

    @Test func withoutARefreshTokenItIsSignedOut() async {
        let auth = MicrosoftSession(clientID: "cid", refreshToken: nil, session: .shared, now: { at(12) }, keep: { _ in })
        await #expect(throws: MicrosoftSession.Failure.signedOut) { try await auth.token(renew: false) }
    }
}
