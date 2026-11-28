// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Covers the session an embedded flow leaves: the token its assertion is exchanged for, with the assertion as the
/// ID token, and what stays when the exchange fails.
final class EmbeddedSessionTests: OAuthTestCase {
    private let assertion = OAuthTestCase.jwt(["sub": "u1", "username": "alice"])
    private let issued = OAuthTestCase.jwt(["sub": "u1", "client_id": "client-1"])

    private func completeFlow(_ extra: String = "") {
        StubBackend.reply("/flow/execute", #"{"flowStatus":"COMPLETE","assertion":"\#(assertion)"\#(extra)}"#)
    }

    private func issueToken() {
        StubBackend.reply("/oauth2/token", #"{"access_token":"\#(issued)","token_type":"Bearer","expires_in":3600}"#)
    }

    private func signIn() async throws {
        _ = try await client.signIn(payload: EmbeddedSignInPayload(), request: EmbeddedFlowRequestConfig(applicationId: "app-1"))
    }

    func testCompletedSignInKeepsTheTokenItsAssertionIsExchangedFor() async throws {
        try await makeClient(applicationId: "app-1")
        try storeSession(["sub": "u0"], refreshToken: "old-refresh")
        completeFlow()
        issueToken()

        try await signIn()

        XCTAssertEqual(form(StubBackend.requests(to: "/oauth2/token").first), [
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "client_id": "client-1",
            "subject_token": assertion,
            "subject_token_type": "urn:ietf:params:oauth:token-type:jwt"
        ])
        XCTAssertEqual(store.accessToken(), issued)
        XCTAssertEqual(store.idToken(), assertion)
        XCTAssertNil(store.refreshToken(), "nothing of the previous session carries over")
        XCTAssertFalse(store.isNearExpiry())
        let user = try await client.getUser()
        XCTAssertEqual(user.claims["username"]?.value as? String, "alice")
    }

    func testUserIsReadFromTheAssertionAfterARelaunch() async throws {
        try await makeClient(applicationId: "app-1")
        completeFlow()
        issueToken()
        try await signIn()

        try await makeClient(applicationId: "app-1")
        let user = try await client.getUser()

        XCTAssertEqual(user.claims["username"]?.value as? String, "alice")
    }

    func testCompletedSignUpKeepsTheExchangedToken() async throws {
        try await makeClient(applicationId: "app-1")
        completeFlow()
        issueToken()

        _ = try await client.signUp()

        XCTAssertEqual(store.accessToken(), issued)
    }

    func testApplicationWithoutTheGrantGetsNoSessionAndTheStepsHandlesAreDropped() async throws {
        try await makeClient(applicationId: "app-1")
        try storeSession(["sub": "u0"])
        let before = store.accessToken()
        try store.mergeFlowSessions([EmbeddedFlowSessionData(flowIdentifier: "f-0", sessionHandle: "h-0")], cleared: [])
        completeFlow(#","sessionData":[{"flowIdentifier":"f-1","sessionHandle":"h-1"}],"clearedSessions":["f-0"]"#)
        StubBackend.reply("/oauth2/token", status: 400, #"{"error":"unauthorized_client"}"#)

        do {
            try await signIn()
            XCTFail("Expected the exchange to fail")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .invalidConfiguration)
            XCTAssertEqual(error.serverError?.code, "unauthorized_client")
            XCTAssertTrue(error.message.contains("urn:ietf:params:oauth:grant-type:token-exchange"))
        }
        XCTAssertEqual(store.accessToken(), before)
        XCTAssertEqual(store.flowSessions(), [], "the step's new handle is dropped and the one it ended stays ended")
    }

    func testAnotherRefusalOfTheExchangeIsReportedAsTheServersError() async throws {
        try await makeClient(applicationId: "app-1")
        completeFlow()
        StubBackend.reply("/oauth2/token", status: 400, #"{"error":"invalid_request"}"#)

        await assertThrows(.invalidInput) { try await self.signIn() }
        XCTAssertNil(store.accessToken())
    }

    func testEmbeddedFlowDoesNotStartWithoutAClientId() async throws {
        try await makeClient(clientId: nil, applicationId: "app-1")

        await assertThrows(.invalidConfiguration) { try await self.signIn() }
        await assertThrows(.invalidConfiguration) { _ = try await self.client.signUp() }
        XCTAssertTrue(StubBackend.requests(to: "/flow/execute").isEmpty)
    }

    func testEmbeddedFlowStepIsNotSubmittedWithoutAClientId() async throws {
        try await makeClient(clientId: nil, applicationId: "app-1")
        let step = EmbeddedSignInPayload(flowId: "f-1", inputs: ["username": "alice"])

        await assertThrows(.invalidConfiguration) {
            _ = try await self.client.signIn(payload: step, request: EmbeddedFlowRequestConfig(applicationId: "app-1"))
        }
        await assertThrows(.invalidConfiguration) { _ = try await self.client.signUp(payload: step) }
        XCTAssertTrue(StubBackend.requests(to: "/flow/execute").isEmpty)
    }

    func testStepThatDoesNotCompleteStoresNoToken() async throws {
        try await makeClient(applicationId: "app-1")
        StubBackend.reply("/flow/execute", #"{"executionId":"f-1","flowStatus":"INCOMPLETE"}"#)

        try await signIn()

        XCTAssertTrue(StubBackend.requests(to: "/oauth2/token").isEmpty)
        XCTAssertNil(store.accessToken())
    }
}
