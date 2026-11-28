// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// A request for a more recent sign-in comes back as `.stepUpRequired`, and `reauthenticate(maxAge:options:)`
/// signs the same user in again before it replaces the session.
final class StepUpTests: OAuthTestCase {
    private let challengeBody = """
    {"code":"AUTH-4011","message":{"defaultValue":"Recent authentication required"},
     "description":{"defaultValue":"Authenticate again","params":{"maxAge":"300"}}}
    """
    private let oldIdToken = OAuthTestCase.jwt(["sub": "u1", "nonce": "first"])
    // Built once each: a dictionary's key order, and so the token text, can differ between builds.
    private let oldAccessToken = OAuthTestCase.jwt(["sub": "u1", "v": "old"])
    private let newAccessToken = OAuthTestCase.jwt(["sub": "u1", "v": "new"])

    private func signedInClient(clientId: String? = "client-1", applicationId: String? = nil) async throws {
        try await makeClient(clientId: clientId, applicationId: applicationId)
        try store.save(TokenResponse(
            accessToken: oldAccessToken,
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: "old-rt",
            idToken: oldIdToken
        ))
    }

    private func query(_ url: URL?) -> [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }) { first, _ in first }
    }

    // MARK: - Typed error

    func testAProfileUpdateRefusedForAnOldSignInIsStepUpRequiredFromTheHeader() async throws {
        try await signedInClient()
        StubBackend.reply("/users/me", status: 401, challengeBody, headers: [
            "WWW-Authenticate": #"Bearer error="insufficient_user_authentication", max_age="120""#
        ])

        let error = await assertThrowsThunderIDError(.stepUpRequired) {
            _ = try await self.client.updateUserProfile(payload: ["email": "new@example.com"])
        }

        XCTAssertEqual(error?.authenticationChallenge?.maxAge, 120)
        XCTAssertEqual(error?.serverError?.code, "AUTH-4011")
    }

    func testAProfileUpdateRefusedForAnOldSignInIsStepUpRequiredFromTheBody() async throws {
        try await signedInClient()
        StubBackend.reply("/users/me", status: 401, challengeBody)

        let error = await assertThrowsThunderIDError(.stepUpRequired) {
            _ = try await self.client.updateUserProfile(payload: ["mobile": "+94770000000"])
        }

        XCTAssertEqual(error?.authenticationChallenge?.maxAge, 300)
    }

    // MARK: - Sign-in options

    func testSignInOptionsSendMaxAgeAndExtraParametersWithoutOverridingTheSDKs() async throws {
        try await makeClient()

        let url = try client.buildSignInURL(options: SignInOptions(
            extra: ["resource": "https://api.example.com", "client_id": "other"],
            maxAge: 60,
            idTokenHint: "hint"
        ))

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.filter { $0.name == "client_id" }.map(\.value), ["client-1"])
        let params = query(url)
        XCTAssertEqual(params["max_age"], "60")
        XCTAssertEqual(params["id_token_hint"], "hint")
        XCTAssertEqual(params["resource"], "https://api.example.com")
    }

    // MARK: - reauthenticate

    /// Answers the browser like the server: the token endpoint returns `claims` in the new ID token, with
    /// the request's nonce unless `nonce` overrides it.
    private func browser(
        sub: String = "u1",
        nonce: String? = nil,
        state: String? = nil,
        captured: @escaping (URL) -> Void = { _ in }
    ) -> (URL) async throws -> URL {
        { [self] url in
            captured(url)
            let params = query(url)
            let idToken = Self.jwt(["sub": sub, "nonce": nonce ?? params["nonce"] ?? ""])
            let body: [String: Any] = [
                "access_token": sub == "u1" ? newAccessToken : Self.jwt(["sub": sub, "v": "new"]),
                "token_type": "Bearer",
                "expires_in": 3600,
                "refresh_token": "new-rt",
                "id_token": idToken
            ]
            let data = try JSONSerialization.data(withJSONObject: body)
            StubBackend.reply("/oauth2/token", String(data: data, encoding: .utf8) ?? "{}")
            return URL(string: "myapp://callback?code=c1&state=\(state ?? params["state"] ?? "")")!
        }
    }

    private var refreshRequests: Int {
        StubBackend.requests(to: "/oauth2/token").filter { form($0)["grant_type"] == "refresh_token" }.count
    }

    private func assertSessionUnchanged(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(store.refreshToken(), "old-rt", file: file, line: line)
        XCTAssertEqual(store.idToken(), oldIdToken, file: file, line: line)
        XCTAssertEqual(store.accessToken(), oldAccessToken, file: file, line: line)
    }

    func testSendsMaxAgeAndTheIdTokenHintThenReplacesTheSession() async throws {
        try await signedInClient()
        var opened: URL?

        let user = try await client.reauthenticate(
            maxAge: 300,
            options: ReauthenticateOptions(authorize: browser { opened = $0 })
        )

        let params = query(opened)
        XCTAssertEqual(params["max_age"], "300")
        XCTAssertNil(params["prompt"])
        XCTAssertEqual(params["id_token_hint"], oldIdToken)
        XCTAssertEqual(params["scope"], "openid profile")
        XCTAssertEqual(params["code_challenge_method"], "S256")
        XCTAssertFalse(params["state", default: ""].isEmpty)
        XCTAssertFalse(params["nonce", default: ""].isEmpty)
        let redeem = form(StubBackend.requests(to: "/oauth2/token").first)
        XCTAssertEqual(redeem["grant_type"], "authorization_code")
        XCTAssertEqual(redeem["code"], "c1")
        XCTAssertFalse(redeem["code_verifier", default: ""].isEmpty)
        XCTAssertEqual(user.sub, "u1")
        XCTAssertEqual(store.refreshToken(), "new-rt")
        XCTAssertEqual(store.accessToken(), newAccessToken)
        XCTAssertEqual(refreshRequests, 0)
    }

    func testAsksForANewSignInWhenTheMaxAgeIsUnknown() async throws {
        try await signedInClient()
        var opened: URL?

        _ = try await client.reauthenticate(maxAge: nil, options: ReauthenticateOptions(authorize: browser { opened = $0 }))

        XCTAssertEqual(query(opened)["prompt"], "login")
        XCTAssertNil(query(opened)["max_age"])
    }

    func testAnotherUserIsRefusedAndTheSessionIsKept() async throws {
        try await signedInClient()

        let error = await assertThrowsThunderIDError(.authenticationFailed) {
            _ = try await self.client.reauthenticate(
                maxAge: 300,
                options: ReauthenticateOptions(authorize: self.browser(sub: "u2"))
            )
        }

        XCTAssertEqual(error?.message, "The sign-in returned another user")
        assertSessionUnchanged()
        XCTAssertEqual(refreshRequests, 0)
    }

    func testAnotherNonceIsRefusedAndTheSessionIsKept() async throws {
        try await signedInClient()

        await assertThrows(.authenticationFailed) {
            _ = try await self.client.reauthenticate(
                maxAge: 300,
                options: ReauthenticateOptions(authorize: self.browser(nonce: "other"))
            )
        }

        assertSessionUnchanged()
    }

    func testAnotherStateIsRefusedBeforeTheCodeIsRedeemed() async throws {
        try await signedInClient()

        await assertThrows(.authenticationFailed) {
            _ = try await self.client.reauthenticate(
                maxAge: 300,
                options: ReauthenticateOptions(authorize: self.browser(state: "other"))
            )
        }

        XCTAssertTrue(StubBackend.requests(to: "/oauth2/token").isEmpty)
        assertSessionUnchanged()
    }

    func testACancelledSignInKeepsTheSession() async throws {
        try await signedInClient()
        struct Cancelled: Error {}

        let error = await assertThrowsThunderIDError(.authenticationFailed) {
            _ = try await self.client.reauthenticate(
                maxAge: 300,
                options: ReauthenticateOptions(authorize: { _ in throw Cancelled() })
            )
        }

        XCTAssertTrue(error?.underlyingError is Cancelled)
        XCTAssertTrue(StubBackend.requests(to: "/oauth2/token").isEmpty)
        assertSessionUnchanged()
    }

    func testAppNativeModeRunsTheSignInFlowInstead() async throws {
        try await signedInClient(applicationId: "app-1")
        try store.markEmbeddedSignIn()

        await assertThrows(.unsupportedOperation) {
            _ = try await self.client.reauthenticate(maxAge: 300, options: ReauthenticateOptions(authorize: self.browser()))
        }

        assertSessionUnchanged()
    }

    func testARefreshKeepsTheEmbeddedSignInMark() async throws {
        try await signedInClient(applicationId: "app-1")
        try store.markEmbeddedSignIn()
        let refreshed = TokenResponse(accessToken: newAccessToken, tokenType: "Bearer", expiresIn: 3600)

        try store.save(refreshed, refreshed: true)
        XCTAssertTrue(store.isEmbeddedSignIn())

        try store.save(refreshed)
        XCTAssertFalse(store.isEmbeddedSignIn())
    }
}
