// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Covers signing the signed-in user in again by running the sign-in flow, for a session from an embedded
/// sign-in: `maxAge` and the kept handles on the start, and the session replaced only for the same user.
final class FlowReauthenticationTests: OAuthTestCase {
    private let issued = OAuthTestCase.jwt(["sub": "u1", "client_id": "client-1"])

    private func reauthentication(maxAge: Int? = 30) -> EmbeddedFlowRequestConfig {
        EmbeddedFlowRequestConfig(applicationId: "app-1", reauthentication: true, maxAge: maxAge)
    }

    /// Signs `u1` in with the embedded flow, so the session is one from an embedded sign-in.
    private func embeddedSession() async throws {
        try await makeClient(applicationId: "app-1")
        StubBackend.reply(
            "/flow/execute",
            #"{"flowStatus":"COMPLETE","assertion":"\#(OAuthTestCase.jwt(["sub": "u1"]))","# +
                #""sessionData":[{"flowIdentifier":"f-0","sessionHandle":"h-0"}]}"#
        )
        StubBackend.reply("/oauth2/token", #"{"access_token":"\#(issued)","token_type":"Bearer","expires_in":3600}"#)
        _ = try await client.signIn(payload: EmbeddedSignInPayload(), request: EmbeddedFlowRequestConfig(applicationId: "app-1"))
        StubBackend.reset()
    }

    func testSessionFromAnEmbeddedSignInSignsInAgainWithTheFlow() async throws {
        try await embeddedSession()

        XCTAssertEqual(client.reauthenticationMethod(), .flow)
        await assertThrows(.unsupportedOperation) { _ = try await self.client.reauthenticate(maxAge: 30) }
    }

    func testRedirectSessionSignsInAgainInTheBrowser() async throws {
        try await makeClient(applicationId: "app-1")
        try storeSession(["sub": "u1"])

        XCTAssertEqual(client.reauthenticationMethod(), .browser)
    }

    func testTokensFromTheTokenEndpointEndTheEmbeddedMark() async throws {
        try await embeddedSession()

        try storeSession(["sub": "u1"])

        XCTAssertEqual(client.reauthenticationMethod(), .browser)
    }

    func testStartSendsMaxAgeAndTheKeptHandles() async throws {
        try await embeddedSession()
        StubBackend.reply("/flow/execute", #"{"executionId":"e-1","flowStatus":"INCOMPLETE"}"#)

        _ = try await client.signIn(payload: EmbeddedSignInPayload(), request: reauthentication())

        let body = StubBackend.requests(to: "/flow/execute").first?.json
        XCTAssertEqual(body?["maxAge"] as? Int, 30)
        XCTAssertEqual(body?["flowType"] as? String, "AUTHENTICATION")
        XCTAssertEqual(body?["sessionData"] as? [[String: String]], [["flowIdentifier": "f-0", "sessionHandle": "h-0"]])
    }

    func testStartAsksForANewSignInWhenTheChallengeHasNoMaxAge() async throws {
        try await embeddedSession()
        StubBackend.reply("/flow/execute", #"{"executionId":"e-1","flowStatus":"INCOMPLETE"}"#)

        _ = try await client.signIn(payload: EmbeddedSignInPayload(), request: reauthentication(maxAge: nil))

        XCTAssertEqual(StubBackend.requests(to: "/flow/execute").first?.json?["maxAge"] as? Int, 0)
    }

    func testAnOrdinarySignInSendsNoMaxAge() async throws {
        try await makeClient(applicationId: "app-1")
        StubBackend.reply("/flow/execute", #"{"executionId":"e-1","flowStatus":"INCOMPLETE"}"#)

        _ = try await client.signIn(payload: EmbeddedSignInPayload(), request: EmbeddedFlowRequestConfig(applicationId: "app-1"))

        XCTAssertNil(StubBackend.requests(to: "/flow/execute").first?.json?["maxAge"])
    }

    func testSameUserReplacesTheSessionWithTheExchangedToken() async throws {
        try await embeddedSession()
        let assertion = OAuthTestCase.jwt(["sub": "u1", "auth_time": 2000])
        StubBackend.reply("/flow/execute", #"{"flowStatus":"COMPLETE","assertion":"\#(assertion)"}"#)
        let renewed = OAuthTestCase.jwt(["sub": "u1", "auth_time": 2000])
        StubBackend.reply("/oauth2/token", #"{"access_token":"\#(renewed)","token_type":"Bearer","expires_in":3600}"#)

        _ = try await client.signIn(payload: EmbeddedSignInPayload(flowId: "e-1"), request: reauthentication())

        XCTAssertEqual(store.accessToken(), renewed)
        XCTAssertEqual(store.idToken(), assertion)
        XCTAssertEqual(client.reauthenticationMethod(), .flow)
    }

    func testAnotherUserIsRefusedBeforeTheExchangeAndTheSessionStays() async throws {
        try await embeddedSession()
        let before = store.accessToken()
        StubBackend.reply(
            "/flow/execute",
            #"{"flowStatus":"COMPLETE","assertion":"\#(OAuthTestCase.jwt(["sub": "u2"]))","# +
                #""sessionData":[{"flowIdentifier":"f-9","sessionHandle":"h-9"}]}"#
        )

        do {
            _ = try await client.signIn(payload: EmbeddedSignInPayload(flowId: "e-1"), request: reauthentication())
            XCTFail("Expected the sign-in to be refused")
        } catch let error as ThunderIDError {
            XCTAssertTrue(error.isReauthenticationByAnotherAccount)
        }

        XCTAssertTrue(StubBackend.requests(to: "/oauth2/token").isEmpty)
        XCTAssertEqual(store.accessToken(), before)
        XCTAssertEqual(store.flowSessions().map(\.flowIdentifier), ["f-0"], "the other user's handle is not kept")
    }

    func testAStepThatCompletesAStartedReSignInIsCheckedWithoutTheFlag() async throws {
        try await embeddedSession()
        let before = store.accessToken()
        StubBackend.reply("/flow/execute", #"{"executionId":"e-7","flowStatus":"INCOMPLETE"}"#)
        StubBackend.reply(
            "/flow/execute",
            #"{"flowStatus":"COMPLETE","assertion":"\#(OAuthTestCase.jwt(["sub": "u2"]))"}"#
        )
        _ = try await client.signIn(payload: EmbeddedSignInPayload(), request: reauthentication())

        await assertThrows(.authenticationFailed) {
            _ = try await self.client.signIn(
                payload: EmbeddedSignInPayload(flowId: "e-7"),
                request: EmbeddedFlowRequestConfig(applicationId: "app-1")
            )
        }

        XCTAssertTrue(StubBackend.requests(to: "/oauth2/token").isEmpty)
        XCTAssertEqual(store.accessToken(), before)
    }

    func testAReSignInWhoseStartReturnsAnErrorStepIsStillCheckedWhenItCompletes() async throws {
        try await embeddedSession()
        StubBackend.reply("/flow/execute", #"{"executionId":"e-1","flowStatus":"ERROR"}"#)
        StubBackend.reply("/flow/execute", #"{"flowStatus":"COMPLETE","assertion":"\#(OAuthTestCase.jwt(["sub": "u2"]))"}"#)
        _ = try await client.signIn(payload: EmbeddedSignInPayload(), request: reauthentication())

        do {
            _ = try await client.signIn(
                payload: EmbeddedSignInPayload(flowId: "e-1"),
                request: EmbeddedFlowRequestConfig(applicationId: "app-1")
            )
            XCTFail("Expected the sign-in to be refused")
        } catch let error as ThunderIDError {
            XCTAssertTrue(error.isReauthenticationByAnotherAccount)
        }
        XCTAssertTrue(StubBackend.requests(to: "/oauth2/token").isEmpty)
    }

    func testSignUpStepsOnAReSignInFlowAreCheckedToo() async throws {
        try await embeddedSession()
        let before = store.accessToken()
        StubBackend.reply("/flow/execute", #"{"executionId":"e-1","flowStatus":"INCOMPLETE"}"#)
        StubBackend.reply("/flow/execute", #"{"flowStatus":"COMPLETE","assertion":"\#(OAuthTestCase.jwt(["sub": "u2"]))"}"#)
        _ = try await client.signIn(payload: EmbeddedSignInPayload(), request: reauthentication())

        await assertThrows(.authenticationFailed) {
            _ = try await self.client.signUp(payload: EmbeddedSignInPayload(flowId: "e-1"))
        }
        XCTAssertEqual(store.accessToken(), before)
    }

    func testAReSignInWithNobodySignedInDoesNotStart() async throws {
        try await makeClient(applicationId: "app-1")

        do {
            _ = try await client.signIn(payload: EmbeddedSignInPayload(), request: reauthentication())
            XCTFail("Expected the sign-in to be refused")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .authenticationFailed)
            XCTAssertFalse(error.isReauthenticationByAnotherAccount)
        }
        XCTAssertTrue(StubBackend.requests(to: "/flow/execute").isEmpty)
    }

    func testClearingTheSessionForgetsTheReSignInFlowsInProgress() async throws {
        try await embeddedSession()
        StubBackend.reply("/flow/execute", #"{"executionId":"e-1","flowStatus":"INCOMPLETE"}"#)
        _ = try await client.signIn(payload: EmbeddedSignInPayload(), request: reauthentication())

        client.clearSession()

        XCTAssertTrue(client.reauthenticationSubjects.isEmpty)
    }
}
