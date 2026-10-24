// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
@testable import ThunderID
import XCTest

final class BackendSessionTests: BackendTestCase {
    // MARK: - Loading

    func testReportsLoadingUntilTheFirstSessionReadSettles() async throws {
        let gate = DispatchSemaphore(value: 0)
        StubBackend.gate = ("/api/auth/session", gate)
        StubBackend.reply("/api/auth/session", signedIn)
        try await makeClient(readSession: false)

        XCTAssertTrue(client.isBackendMode)
        XCTAssertTrue(client.isLoading())
        gate.signal()
        gate.signal()
        let isSignedIn = try await client.isSignedIn()

        XCTAssertTrue(isSignedIn)
        XCTAssertFalse(client.isLoading())
        let user = try await client.getUser()
        XCTAssertEqual(user["name"] as? String, "Ada")
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/session").count, 1)
        XCTAssertEqual(StubBackend.requests.first?.header("X-Session-Handle"), "h1")
    }

    func testWithoutAStoredHandleIsSignedOutWithoutANetworkCall() async throws {
        try await makeClient(handle: nil, readSession: false)

        let isSignedIn = try await client.isSignedIn()

        XCTAssertFalse(isSignedIn)
        XCTAssertFalse(client.isLoading())
        XCTAssertTrue(StubBackend.requests.isEmpty)
    }

    // MARK: - Sign-in handoff

    func testSignInURLOpensTheBackendWithAPKCEChallenge() async throws {
        try await makeClient(handle: nil)

        let url = try client.buildSignInURL()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }

        XCTAssertEqual(url.host, "app.example.com")
        XCTAssertEqual(url.path, "/api/auth/signin")
        XCTAssertEqual(value("redirect_uri"), "myapp://callback")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertNotNil(value("code_challenge"))
        XCTAssertNil(value("client_id"))
    }

    func testHandoffPostsTheCodeAndVerifierAndStoresTheHandle() async throws {
        try await makeClient(handle: nil)
        let signInURL = try client.buildSignInURL()
        let challenge = URLComponents(url: signInURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "code_challenge" }?.value
        StubBackend.reply(
            "/api/auth/session",
            #"{"handle":"h2","isSignedIn":true,"user":{"sub":"u1","name":"Ada"},"expiresAt":1900000000}"#
        )

        let user = try await client.handleRedirectCallback(url: URL(string: "myapp://callback?session_code=c1")!)

        XCTAssertEqual(user["name"] as? String, "Ada")
        let handoff = try XCTUnwrap(StubBackend.requests(to: "/api/auth/session").first)
        XCTAssertEqual(handoff.request.httpMethod, "POST")
        XCTAssertNil(handoff.header("X-Session-Handle"))
        XCTAssertEqual(handoff.json?["session_code"] as? String, "c1")
        let verifier = try XCTUnwrap(handoff.json?["code_verifier"] as? String)
        XCTAssertEqual(Self.s256(verifier), challenge)
        XCTAssertEqual(storedHandle, "h2")
        let isSignedIn = try await client.isSignedIn()
        XCTAssertTrue(isSignedIn)
        XCTAssertFalse(client.isLoading())

        StubBackend.reply("/api/auth/proxy/users/me", #"{"id":"u1"}"#)
        _ = try await client.httpRequest(request("\(apiBase)/users/me"))
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/proxy/users/me").first?.header("X-Session-Handle"), "h2")
    }

    func testHandoffRefusesACallbackWithoutACodeOrForASignInItDidNotStart() async throws {
        try await makeClient(handle: nil)

        await assertThrows(.invalidGrant) {
            _ = try await self.client.handleRedirectCallback(url: URL(string: "myapp://callback?session_code=c1")!)
        }
        _ = try client.buildSignInURL()
        await assertThrows(.invalidGrant) {
            _ = try await self.client.handleRedirectCallback(url: URL(string: "myapp://callback")!)
        }
        await assertThrows(.authenticationFailed) {
            _ = try await self.client.handleRedirectCallback(url: URL(string: "myapp://callback?error=access_denied")!)
        }
        XCTAssertTrue(StubBackend.requests.isEmpty)
        XCTAssertNil(storedHandle)
    }

    // MARK: - Proxy and 401 handling

    func testSendsRequestsUnderTheApiBaseThroughTheProxyWithTheHandle() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/proxy/users", #"{"users":[]}"#)

        let (data, response) = try await client.httpRequest(request("\(apiBase)/users?limit=5"))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"users":[]}"#)
        let sent = try XCTUnwrap(StubBackend.requests.first)
        XCTAssertEqual(sent.request.url?.absoluteString, "\(backendBase)/api/auth/proxy/users?limit=5")
        XCTAssertEqual(sent.header("X-Session-Handle"), "h1")
        XCTAssertNil(sent.header("Authorization"))
    }

    func testProfileOperationsGoThroughTheProxy() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/proxy/users/me", #"{"id":"u1","attributes":{},"isReadOnly":false}"#)

        let profile = try await client.getUserProfile()

        XCTAssertEqual(profile.id, "u1")
        XCTAssertEqual(StubBackend.requests.first?.header("X-Session-Handle"), "h1")
    }

    func testSessionExpiredRefreshesOnceAndRetries() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/proxy/users", status: 401, #"{"error":"session_expired"}"#)
        StubBackend.reply("/api/auth/proxy/users", #"{"users":[]}"#)
        StubBackend.reply("/api/auth/refresh")

        let (_, response) = try await client.httpRequest(request("\(apiBase)/users"))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/refresh").count, 1)
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/proxy/users").count, 2)
        XCTAssertEqual(signOuts, 0)
    }

    func testASecondSessionExpiredMeansSignedOut() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/proxy/users", status: 401, #"{"error":"session_expired"}"#)
        StubBackend.reply("/api/auth/refresh")

        let (_, response) = try await client.httpRequest(request("\(apiBase)/users"))

        XCTAssertEqual(response.statusCode, 401)
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/refresh").count, 1)
        XCTAssertEqual(signOuts, 1)
        XCTAssertNil(storedHandle)
        let isSignedIn = try await client.isSignedIn()
        XCTAssertFalse(isSignedIn)
    }

    func testAFailedRefreshMeansSignedOut() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/proxy/users", status: 401, #"{"error":"session_expired"}"#)
        StubBackend.reply("/api/auth/refresh", status: 401, #"{"error":"login_required"}"#)

        let (_, response) = try await client.httpRequest(request("\(apiBase)/users"))

        XCTAssertEqual(response.statusCode, 401)
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/proxy/users").count, 1)
        XCTAssertEqual(signOuts, 1)
        XCTAssertNil(storedHandle)
    }

    func testLoginRequiredSignsOutAndNotifies() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/proxy/users", status: 401, #"{"error":"login_required"}"#)

        let (_, response) = try await client.httpRequest(request("\(apiBase)/users"))

        XCTAssertEqual(response.statusCode, 401)
        XCTAssertTrue(StubBackend.requests(to: "/api/auth/refresh").isEmpty)
        XCTAssertEqual(signOuts, 1)
        XCTAssertNil(storedHandle)
        let isSignedIn = try await client.isSignedIn()
        XCTAssertFalse(isSignedIn)
        XCTAssertEqual(StubBackend.requests.count, 1)
    }

    func testAnyOther401IsReturnedUntouched() async throws {
        try await makeClient()
        let body = #"{"error":"invalid_token","detail":"API says no"}"#
        StubBackend.reply("/api/auth/proxy/users", status: 401, body)

        let (data, response) = try await client.httpRequest(request("\(apiBase)/users"))

        XCTAssertEqual(response.statusCode, 401)
        XCTAssertEqual(String(data: data, encoding: .utf8), body)
        XCTAssertTrue(StubBackend.requests(to: "/api/auth/refresh").isEmpty)
        XCTAssertEqual(signOuts, 0)
        XCTAssertEqual(storedHandle, "h1")
    }

    func testRefusesAUrlOutsideTheApiBaseAndTheBypassList() async throws {
        try await makeClient()

        for url in ["https://other.example.com/users", "https://api.example.com.attacker.test/users", "\(dataPlane)v2"] {
            await assertThrows(.unsupportedOperation) {
                _ = try await self.client.httpRequest(self.request(url))
            }
        }
        XCTAssertTrue(StubBackend.requests.isEmpty)
    }

    // MARK: - Sign-out and session end

    func testSignOutEndsTheSessionAndClearsTheHandleAndToken() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/token", #"{"access_token":"t1","token_type":"Bearer","expires_in":300}"#)
        _ = try await client.getAccessToken()
        StubBackend.reply("/api/auth/signout", #"{"redirectUrl":"https://auth.example.com/oidc/logout?x=1"}"#)

        let redirect = try await client.signOut()

        XCTAssertEqual(redirect, "https://auth.example.com/oidc/logout?x=1")
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/signout").first?.header("X-Session-Handle"), "h1")
        XCTAssertNil(storedHandle)
        XCTAssertNil(storedToken)
        XCTAssertEqual(signOuts, 0)
        let isSignedIn = try await client.isSignedIn()
        XCTAssertFalse(isSignedIn)
    }

    func testSignOutClearsLocalStateEvenWhenTheBackendFails() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/signout", status: 500)

        await assertThrows(.serverError) { _ = try await self.client.signOut() }

        XCTAssertNil(storedHandle)
        let isSignedIn = try await client.isSignedIn()
        XCTAssertFalse(isSignedIn)
    }

    func testASessionThatEndedElsewhereClearsTheTokenAndNotifiesOnce() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/token", #"{"access_token":"t1","token_type":"Bearer","expires_in":300}"#)
        _ = try await client.getAccessToken()
        StubBackend.reply("/api/auth/checksession", #"{"isSignedIn":false}"#)

        let live = await client.backend!.checkSession()

        XCTAssertFalse(live)
        XCTAssertNil(storedToken)
        XCTAssertNil(storedHandle)
        XCTAssertEqual(signOuts, 1)
        _ = await client.backend!.checkSession()
        XCTAssertEqual(signOuts, 1)
    }

    func testPollsCheckSessionEveryCheckInterval() async throws {
        try await makeClient(checkInterval: 0.05)
        StubBackend.reply("/api/auth/checksession", #"{"isSignedIn":true}"#)

        for _ in 0..<40 where StubBackend.requests(to: "/api/auth/checksession").count < 2 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let checks = StubBackend.requests(to: "/api/auth/checksession")
        XCTAssertGreaterThanOrEqual(checks.count, 2)
        XCTAssertEqual(checks.first?.header("X-Session-Handle"), "h1")
        XCTAssertEqual(signOuts, 0)
    }

    // MARK: - Unsupported operations

    func testRefusesTheEmbeddedFlowsAndTokenExchange() async throws {
        try await makeClient()

        await assertThrows(.unsupportedOperation) {
            _ = try await self.client.signIn(
                payload: .init(),
                request: .init(applicationId: "app", flowType: .authentication)
            )
        }
        await assertThrows(.unsupportedOperation) { _ = try await self.client.signUp() }
        await assertThrows(.unsupportedOperation) {
            _ = try await self.client.exchangeToken(config: .init(subjectToken: "s", subjectTokenType: "t"))
        }
        XCTAssertTrue(StubBackend.requests.isEmpty)
    }

    private static func s256(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
