// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Covers the SSO session handles app-native flow steps return: kept by flow, dropped when ended or expired,
/// sent when a switch starts its flow, kept across a switch and cleared on sign-out.
final class FlowSessionTests: OAuthTestCase {
    private func session(_ flow: String, _ handle: String, expiresIn: Int? = nil) -> EmbeddedFlowSessionData {
        EmbeddedFlowSessionData(flowIdentifier: flow, sessionHandle: handle, expiresIn: expiresIn)
    }

    func testStepCarriesTheSessionsItStartedAndEnded() throws {
        let json = #"""
        {"executionId":"f-1","flowStatus":"COMPLETE",
         "sessionData":[{"flowIdentifier":"f1","sessionHandle":"h1","expiresIn":600},{"flowIdentifier":"f2","sessionHandle":"h2"}],
         "clearedSessions":["f3"]}
        """#
        let step = try JSONDecoder().decode(EmbeddedFlowResponse.self, from: Data(json.utf8))
        XCTAssertEqual(step.sessionData, [session("f1", "h1", expiresIn: 600), session("f2", "h2")])
        XCTAssertEqual(step.clearedSessions, ["f3"])
    }

    func testMalformedSessionDataDoesNotFailTheStep() throws {
        let json = #"{"executionId":"f-1","flowStatus":"INCOMPLETE","sessionData":"oops"}"#
        let step = try JSONDecoder().decode(EmbeddedFlowResponse.self, from: Data(json.utf8))
        XCTAssertNil(step.sessionData)
        XCTAssertEqual(step.flowId, "f-1")
    }

    func testSessionsMergeByFlowAndEndedOnesAreDropped() throws {
        try store.mergeFlowSessions([session("f1", "h1", expiresIn: 600), session("f2", "h2")], cleared: [])
        try store.mergeFlowSessions([session("f1", "h1b", expiresIn: 600)], cleared: ["f2"])
        XCTAssertEqual(store.flowSessions(), [session("f1", "h1b")], "expiresIn is not sent back")

        try store.mergeFlowSessions([], cleared: ["f1"])
        XCTAssertEqual(store.flowSessions(), [])
    }

    func testSessionsPastTheirExpiryAreLeftOut() throws {
        let now = Date()
        try store.mergeFlowSessions([session("f1", "h1", expiresIn: 60), session("f2", "h2")], cleared: [], now: now)
        XCTAssertEqual(store.flowSessions(now: now.addingTimeInterval(30)).map(\.flowIdentifier), ["f1", "f2"])
        XCTAssertEqual(
            store.flowSessions(now: now.addingTimeInterval(61)).map(\.flowIdentifier),
            ["f2"],
            "a session without an expiry is kept"
        )
    }

    func testSignInStepsKeepTheSessionsTheyReturnAndAPlainSignInSendsNone() async throws {
        try await makeClient(clientId: nil, applicationId: "app-1")
        try store.mergeFlowSessions([session("f0", "h0")], cleared: [])
        StubBackend.reply(
            "/flow/execute",
            #"{"executionId":"f-1","flowStatus":"INCOMPLETE","sessionData":[{"flowIdentifier":"f1","sessionHandle":"h1"}]}"#
        )
        _ = try await client.signIn(payload: EmbeddedSignInPayload(), request: EmbeddedFlowRequestConfig(applicationId: "app-1"))
        XCTAssertNil(StubBackend.requests(to: "/flow/execute").first?.json?["sessionData"])
        XCTAssertEqual(store.flowSessions().map(\.flowIdentifier), ["f0", "f1"])

        StubBackend.reset()
        StubBackend.reply("/flow/execute", #"{"executionId":"f-1","flowStatus":"COMPLETE","clearedSessions":["f0"]}"#)
        _ = try await client.signIn(
            payload: EmbeddedSignInPayload(flowId: "f-1", actionId: "submit"),
            request: EmbeddedFlowRequestConfig(applicationId: "app-1")
        )
        XCTAssertEqual(store.flowSessions().map(\.flowIdentifier), ["f1"])
    }

    func testSignUpStepsKeepTheSessionsTheyReturn() async throws {
        try await makeClient(clientId: nil, applicationId: "app-1")
        StubBackend.reply(
            "/flow/execute",
            #"{"executionId":"f-1","flowStatus":"COMPLETE","sessionData":[{"flowIdentifier":"r1","sessionHandle":"h1"}]}"#
        )
        _ = try await client.signUp()
        XCTAssertEqual(store.flowSessions(), [session("r1", "h1")])
    }

    func testEmbeddedSwitchSendsTheUnexpiredSessions() async throws {
        try await makeClient(clientId: nil, applicationId: "app-1")
        let now = Date()
        try store.mergeFlowSessions([session("old", "h0", expiresIn: 1)], cleared: [], now: now.addingTimeInterval(-10))
        try store.mergeFlowSessions([session("f2", "h2", expiresIn: 600), session("f1", "h1")], cleared: [], now: now)
        StubBackend.reply("/flow/execute", #"{"executionId":"f-9","flowStatus":"INCOMPLETE"}"#)
        _ = try await client.switchOrganizationUnit("ou-2")
        let body = StubBackend.requests(to: "/flow/execute").first?.json
        XCTAssertEqual(body?["ouId"] as? String, "ou-2")
        XCTAssertEqual(
            body?["sessionData"] as? [[String: String]],
            [["flowIdentifier": "f1", "sessionHandle": "h1"], ["flowIdentifier": "f2", "sessionHandle": "h2"]]
        )
    }

    func testEmbeddedSwitchWithNoSessionsSendsNone() async throws {
        try await makeClient(clientId: nil, applicationId: "app-1")
        StubBackend.reply("/flow/execute", #"{"executionId":"f-9","flowStatus":"INCOMPLETE"}"#)
        _ = try await client.switchOrganizationUnit("ou-2")
        let body = StubBackend.requests(to: "/flow/execute").first?.json
        XCTAssertEqual(body?["ouId"] as? String, "ou-2")
        XCTAssertNil(body?["sessionData"])
    }

    func testEmbeddedSwitchKeepsTheDeviceSecretAndTheSessions() async throws {
        try await makeClient(clientId: nil, applicationId: "app-1")
        try storeSession(["sub": "u1", "ouId": "ou-1"], refreshToken: "old", deviceSecret: "ds-1")
        try store.mergeFlowSessions([session("f1", "h1")], cleared: [])
        let assertion = Self.jwt(["sub": "u1", "ouId": "ou-2"])
        StubBackend.reply(
            "/flow/execute",
            #"{"executionId":"f-1","flowStatus":"COMPLETE","assertion":"\#(assertion)","sessionData":[{"flowIdentifier":"f2","sessionHandle":"h2"}]}"#
        )
        let result = try await client.switchOrganizationUnit("ou-2")
        guard case .switched(let user) = result else { return XCTFail("Expected a switch") }
        XCTAssertEqual(user.claims["ouId"]?.value as? String, "ou-2")
        XCTAssertNil(store.refreshToken(), "nothing of the previous session's tokens carries over")
        XCTAssertEqual(store.deviceSecret(), "ds-1")
        XCTAssertEqual(store.flowSessions().map(\.flowIdentifier), ["f1", "f2"])
    }

    func testBrowserSwitchKeepsTheSessions() async throws {
        try await makeClient()
        try storeSession(["sub": "u1", "ouId": "ou-1"], refreshToken: "old")
        try store.mergeFlowSessions([session("f1", "h1")], cleared: [])
        StubBackend.reply("/ou/ou-2/oauth2/token", tokenJSON(["sub": "u1", "ouId": "ou-2"], refresh: "new"))
        _ = try await client.switchOrganizationUnit("ou-2", options: .init { _ in URL(string: "myapp://callback?code=c-2")! })
        XCTAssertEqual(store.refreshToken(), "new")
        XCTAssertEqual(store.flowSessions(), [session("f1", "h1")])
    }

    func testSignOutClearsTheDeviceSecretAndTheSessions() async throws {
        try await makeClient()
        try storeSession(["sub": "u1"], deviceSecret: "ds-1")
        try store.mergeFlowSessions([session("f1", "h1")], cleared: [])
        _ = try await client.signOut()
        XCTAssertNil(store.deviceSecret())
        XCTAssertEqual(store.flowSessions(), [])
    }
}
