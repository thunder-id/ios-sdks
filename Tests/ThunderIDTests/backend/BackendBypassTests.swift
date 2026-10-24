// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class BackendBypassTests: BackendTestCase {
    private func token(_ value: String, expiresIn: Int = 300) -> String {
        #"{"access_token":"\#(value)","token_type":"Bearer","expires_in":\#(expiresIn),"scope":"orders"}"#
    }

    func testABypassedRequestGoesStraightThereWithTheAccessToken() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/token", token("t1"))
        StubBackend.reply("/api/orders", #"{"orders":[]}"#)

        let (data, response) = try await client.httpRequest(request("\(dataPlane)/orders"))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"orders":[]}"#)
        let tokenRequest = try XCTUnwrap(StubBackend.requests(to: "/api/auth/token").first)
        XCTAssertEqual(tokenRequest.request.httpMethod, "POST")
        XCTAssertEqual(tokenRequest.header("X-Session-Handle"), "h1")
        let sent = try XCTUnwrap(StubBackend.requests(to: "/api/orders").first)
        XCTAssertEqual(sent.request.url?.absoluteString, "\(dataPlane)/orders")
        XCTAssertEqual(sent.header("Authorization"), "Bearer t1")
        XCTAssertNil(sent.header("X-Session-Handle"))
    }

    func testTheTokenIsStoredAndReusedUntilItNearsExpiry() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/token", token("t1"))
        StubBackend.reply("/api/orders", "{}")

        _ = try await client.httpRequest(request("\(dataPlane)/orders"))
        _ = try await client.httpRequest(request("\(dataPlane)/orders"))
        let fromSurface = try await client.getAccessToken()

        XCTAssertEqual(fromSurface, "t1")
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/token").count, 1)
        XCTAssertEqual(StubBackend.requests(to: "/api/orders").map { $0.header("Authorization") }, ["Bearer t1", "Bearer t1"])
        let store = TokenStore(storage: storage)
        XCTAssertEqual(store.accessToken(), "t1")
        XCTAssertNil(store.refreshToken())
        let createdAt = try XCTUnwrap(store.createdAt())
        XCTAssertEqual(createdAt.timeIntervalSinceNow, 0, accuracy: 5)
        XCTAssertEqual(try XCTUnwrap(store.tokenExpiry()).timeIntervalSince(createdAt), 300, accuracy: 0.001)
    }

    func testATokenWithin30SecondsOfExpiryIsRequestedAgain() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/token", token("t1", expiresIn: 29))
        StubBackend.reply("/api/auth/token", token("t2", expiresIn: 300))

        let first = try await client.getAccessToken()
        let second = try await client.getAccessToken()

        XCTAssertEqual(first, "t1")
        XCTAssertEqual(second, "t2")
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/token").count, 2)
    }

    func testConcurrentCallersShareOneTokenRequest() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/token", token("t1"), delay: 0.2)

        async let first = client.getAccessToken()
        async let second = client.getAccessToken()
        async let third = client.getAccessToken()
        let tokens = try await [first, second, third]

        XCTAssertEqual(tokens, ["t1", "t1", "t1"])
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/token").count, 1)
    }

    func testA401FromTheApiGetsANewTokenAndRetriesOnce() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/token", token("t1"))
        StubBackend.reply("/api/auth/token", token("t2"))
        StubBackend.reply("/api/orders", status: 401)
        StubBackend.reply("/api/orders", #"{"orders":[]}"#)

        let (_, response) = try await client.httpRequest(request("\(dataPlane)/orders"))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(StubBackend.requests(to: "/api/orders").map { $0.header("Authorization") }, ["Bearer t1", "Bearer t2"])
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/refresh").count, 0)
        XCTAssertEqual(storedToken, "t2")
    }

    func testASecond401FromTheApiIsReturnedToTheCaller() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/token", token("t1"))
        StubBackend.reply("/api/auth/token", token("t2"))
        StubBackend.reply("/api/orders", status: 401, #"{"error":"invalid_token"}"#)

        let (data, response) = try await client.httpRequest(request("\(dataPlane)/orders"))

        XCTAssertEqual(response.statusCode, 401)
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"error":"invalid_token"}"#)
        XCTAssertEqual(StubBackend.requests(to: "/api/orders").count, 2)
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/token").count, 2)
        XCTAssertEqual(signOuts, 0)
    }

    func testWithAttachTokenOffBypassedRequestsCarryNoTokenAndNeverCallToken() async throws {
        try await makeClient(attachToken: false)
        StubBackend.reply("/api/orders", status: 401)

        let (_, response) = try await client.httpRequest(request("\(dataPlane)/orders"))

        XCTAssertEqual(response.statusCode, 401)
        let sent = try XCTUnwrap(StubBackend.requests(to: "/api/orders").first)
        XCTAssertNil(sent.header("Authorization"))
        XCTAssertNil(sent.header("X-Session-Handle"))
        XCTAssertEqual(StubBackend.requests.count, 1)
    }

    func testSessionExpiredFromTheTokenEndpointRefreshesAndAsksAgain() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/token", status: 401, #"{"error":"session_expired"}"#)
        StubBackend.reply("/api/auth/token", token("t1"))
        StubBackend.reply("/api/auth/refresh")

        let token = try await client.getAccessToken()

        XCTAssertEqual(token, "t1")
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/refresh").count, 1)
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/token").count, 2)
    }

    func testLoginRequiredFromTheTokenEndpointSignsOut() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/token", status: 401, #"{"error":"login_required"}"#)

        await assertThrows(.authenticationFailed) { _ = try await self.client.getAccessToken() }

        XCTAssertEqual(signOuts, 1)
        XCTAssertNil(storedHandle)
        let isSignedIn = try await client.isSignedIn()
        XCTAssertFalse(isSignedIn)
    }

    func testANewSessionDoesNotReuseAnEarlierSessionsToken() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/token", token("t1"))
        _ = try await client.getAccessToken()
        _ = try client.buildSignInURL()
        StubBackend.reply("/api/auth/session", #"{"handle":"h2","isSignedIn":true,"user":{"sub":"u2"}}"#)

        _ = try await client.handleRedirectCallback(url: URL(string: "myapp://callback?session_code=c2")!)

        XCTAssertNil(storedToken)
        XCTAssertEqual(storedHandle, "h2")
    }
}
