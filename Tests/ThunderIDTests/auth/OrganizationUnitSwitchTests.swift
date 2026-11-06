// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class OrganizationUnitSwitchTests: OAuthTestCase {
    func testSwitchExchangesTheDeviceSecretAtTheUnitWithoutTheBrowser() async throws {
        try await makeClient()
        try storeSession(["sub": "u1", "ouId": "ou-1"], refreshToken: "old", deviceSecret: "ds-1")
        try store.mergeFlowSessions([EmbeddedFlowSessionData(flowIdentifier: "f1", sessionHandle: "h1")], cleared: [])
        StubBackend.reply("/ou/ou-2/oauth2/token", tokenJSON(["sub": "u1", "ouId": "ou-2"], refresh: "new"))
        let result = try await client.switchOrganizationUnit("ou-2")
        guard case .switched(let user) = result else { return XCTFail("Expected a switch") }
        XCTAssertEqual(user.claims["ouId"]?.value as? String, "ou-2")
        let fields = form(StubBackend.requests(to: "/ou/ou-2/oauth2/token").first)
        XCTAssertEqual(fields["grant_type"], "urn:ietf:params:oauth:grant-type:token-exchange")
        XCTAssertEqual(fields["subject_token"], "ds-1")
        XCTAssertEqual(fields["subject_token_type"], "urn:ietf:params:oauth:token-type:jwt")
        XCTAssertEqual(fields["client_id"], "client-1")
        XCTAssertEqual(fields["scope"], "openid profile")
        XCTAssertEqual(store.refreshToken(), "new")
        XCTAssertEqual(store.deviceSecret(), "ds-1", "the device secret belongs to the SSO session and is kept")
        XCTAssertEqual(store.flowSessions(), [EmbeddedFlowSessionData(flowIdentifier: "f1", sessionHandle: "h1")])
        let current = try await client.getCurrentOrganizationUnit()
        XCTAssertEqual(current?.id, "ou-2")
    }

    func testFailedSwitchLeavesThePreviousSessionIntact() async throws {
        try await makeClient()
        try storeSession(["sub": "u1", "ouId": "ou-1"], refreshToken: "old", deviceSecret: "ds-1")
        let before = store.accessToken()
        _ = try await client.getUser()
        StubBackend.reply("/ou/ou-x/oauth2/token", status: 400, #"{"error":"unauthorized_client"}"#)
        await assertThrows(.organizationUnitUnavailable) { _ = try await self.client.switchOrganizationUnit("ou-x") }
        XCTAssertEqual(store.accessToken(), before)
        XCTAssertEqual(store.refreshToken(), "old")
        let user = try await client.getUser()
        XCTAssertEqual(user.claims["ouId"]?.value as? String, "ou-1")
    }

    func testSwitchThroughTheBrowserAuthorizesAndRedeemsAtTheUnit() async throws {
        try await makeClient()
        try storeSession(["sub": "u1", "ouId": "ou-1"])
        var opened: URL?
        let options = SwitchOrganizationUnitOptions { url in
            opened = url
            return URL(string: "myapp://callback?code=c-2")!
        }
        StubBackend.reply("/ou/ou-2/oauth2/token", tokenJSON(["sub": "u1", "ouId": "ou-2"]))
        let result = try await client.switchOrganizationUnit("ou-2", options: options)
        guard case .switched = result else { return XCTFail("Expected a switch") }
        XCTAssertEqual(opened?.path, "/ou/ou-2/oauth2/authorize")
        XCTAssertEqual(form(StubBackend.requests(to: "/ou/ou-2/oauth2/token").first)["code"], "c-2")
    }

    func testDeviceSecretThatNeedsTheUserFallsBackToTheBrowser() async throws {
        try await makeClient()
        try storeSession(["sub": "u1"], deviceSecret: "ds-1")
        StubBackend.reply("/ou/ou-2/oauth2/token", status: 400, #"{"error":"interaction_required"}"#)
        StubBackend.reply("/ou/ou-2/oauth2/token", tokenJSON(["sub": "u1", "ouId": "ou-2"]))
        var opened = false
        let options = SwitchOrganizationUnitOptions { _ in
            opened = true
            return URL(string: "myapp://callback?code=c-3")!
        }
        _ = try await client.switchOrganizationUnit("ou-2", options: options)
        XCTAssertTrue(opened)
        XCTAssertEqual(StubBackend.requests(to: "/ou/ou-2/oauth2/token").count, 2)
        XCTAssertEqual(store.deviceSecret(), "ds-1", "interaction_required keeps the device secret")
    }

    func testUnusableDeviceSecretIsDroppedAndTheSwitchGoesOnThroughTheBrowser() async throws {
        for error in ["invalid_request", "invalid_grant"] {
            StubBackend.reset()
            storage = InMemoryStorageAdapter()
            try await makeClient()
            try storeSession(["sub": "u1", "ouId": "ou-1"], deviceSecret: "ds-1")
            StubBackend.reply("/ou/ou-2/oauth2/token", status: 400, #"{"error":"\#(error)"}"#)
            StubBackend.reply("/ou/ou-2/oauth2/token", tokenJSON(["sub": "u1", "ouId": "ou-2"]))
            var opened = false
            let options = SwitchOrganizationUnitOptions { _ in
                opened = true
                return URL(string: "myapp://callback?code=c-4")!
            }
            let result = try await client.switchOrganizationUnit("ou-2", options: options)
            guard case .switched = result else { return XCTFail("Expected a switch after \(error)") }
            XCTAssertTrue(opened, "\(error) goes on to the browser")
            XCTAssertNil(store.deviceSecret(), "\(error) drops the device secret")
        }
    }

    func testUnusableDeviceSecretWithoutABrowserGoesOnToTheBoundedFlow() async throws {
        try await makeClient(applicationId: "app-1")
        try storeSession(["sub": "u1", "ouId": "ou-1"], refreshToken: "old", deviceSecret: "ds-1")
        StubBackend.reply("/ou/ou-2/oauth2/token", status: 400, #"{"error":"invalid_grant"}"#)
        StubBackend.reply("/flow/execute", #"{"executionId":"f-2","flowStatus":"INCOMPLETE"}"#)
        let result = try await client.switchOrganizationUnit("ou-2")
        guard case .signInRequired = result else { return XCTFail("Expected the bounded flow") }
        XCTAssertEqual(StubBackend.requests(to: "/flow/execute").first?.json?["ouId"] as? String, "ou-2")
        XCTAssertNil(store.deviceSecret())
        XCTAssertEqual(store.refreshToken(), "old", "the session stays until the flow completes")
    }

    func testUnavailableUnitFromTheExchangeIsThrownWithoutTheBrowser() async throws {
        try await makeClient()
        try storeSession(["sub": "u1", "ouId": "ou-1"], deviceSecret: "ds-1")
        StubBackend.reply("/ou/ou-x/oauth2/token", status: 400, #"{"error":"unauthorized_client"}"#)
        var opened = false
        let options = SwitchOrganizationUnitOptions { _ in
            opened = true
            return URL(string: "myapp://callback?code=c-5")!
        }
        await assertThrows(.organizationUnitUnavailable) {
            _ = try await self.client.switchOrganizationUnit("ou-x", options: options)
        }
        XCTAssertFalse(opened)
        XCTAssertEqual(store.deviceSecret(), "ds-1", "an unavailable unit says nothing about the device secret")
    }

    func testOtherExchangeFailureGoesOnAsIfNoDeviceSecretWereHeld() async throws {
        try await makeClient()
        try storeSession(["sub": "u1", "ouId": "ou-1"], deviceSecret: "ds-1")
        StubBackend.reply("/ou/ou-2/oauth2/token", status: 503, #"{"error":"temporarily_unavailable"}"#)
        StubBackend.reply("/ou/ou-2/oauth2/token", tokenJSON(["sub": "u1", "ouId": "ou-2"], refresh: "new"))
        var opened = false
        let options = SwitchOrganizationUnitOptions { _ in
            opened = true
            return URL(string: "myapp://callback?code=c-6")!
        }
        let result = try await client.switchOrganizationUnit("ou-2", options: options)
        guard case .switched = result else { return XCTFail("Expected a switch") }
        XCTAssertTrue(opened)
        XCTAssertEqual(store.refreshToken(), "new")
        XCTAssertEqual(store.deviceSecret(), "ds-1", "only invalid_request and invalid_grant drop the device secret")
    }

    func testExchangeFailureWithNoOtherWayLeftIsThrown() async throws {
        try await makeClient()
        try storeSession(["sub": "u1", "ouId": "ou-1"], deviceSecret: "ds-1")
        StubBackend.reply("/ou/ou-2/oauth2/token", status: 400, #"{"error":"interaction_required"}"#)
        await assertThrows(.authenticationFailed) { _ = try await self.client.switchOrganizationUnit("ou-2") }
        XCTAssertEqual(store.deviceSecret(), "ds-1")
    }

    func testCancelledBrowserSwitchKeepsTheSession() async throws {
        try await makeClient()
        try storeSession(["sub": "u1", "ouId": "ou-1"])
        let before = store.accessToken()
        struct Cancelled: Error {}
        do {
            _ = try await client.switchOrganizationUnit("ou-2", options: .init { _ in throw Cancelled() })
            XCTFail("Expected the cancellation")
        } catch is Cancelled {}
        XCTAssertEqual(store.accessToken(), before)
        XCTAssertNil(client.pendingOrganizationUnitId)
    }

    func testEmbeddedSwitchReturnsTheFlowAndSwitchesOnlyWhenItCompletes() async throws {
        try await makeClient(clientId: nil, applicationId: "app-1")
        try storeSession(["sub": "u1", "ouId": "ou-1"], refreshToken: "old")
        let before = store.accessToken()
        StubBackend.reply("/flow/execute", #"{"executionId":"f-9","flowStatus":"INCOMPLETE"}"#)
        let result = try await client.switchOrganizationUnit("ou-2")
        guard case .signInRequired(let response) = result else { return XCTFail("Expected a sign-in step") }
        XCTAssertEqual(StubBackend.requests(to: "/flow/execute").first?.json?["ouId"] as? String, "ou-2")
        XCTAssertEqual(store.accessToken(), before, "the old session stays until the flow completes")

        let assertion = Self.jwt(["sub": "u1", "ouId": "ou-2"])
        StubBackend.reset()
        StubBackend.reply("/flow/execute", #"{"executionId":"f-9","flowStatus":"COMPLETE","assertion":"\#(assertion)"}"#)
        _ = try await client.signIn(
            payload: EmbeddedSignInPayload(flowId: response.flowId, actionId: "submit"),
            request: EmbeddedFlowRequestConfig(applicationId: "app-1")
        )
        XCTAssertEqual(store.accessToken(), assertion)
        XCTAssertNil(store.refreshToken(), "a unit-bounded sign-in replaces the whole session")
        let user = try await client.getUser()
        XCTAssertEqual(user.claims["ouId"]?.value as? String, "ou-2")
    }

    func testEmbeddedSwitchThatCompletesAtOnceSwitches() async throws {
        try await makeClient(clientId: nil, applicationId: "app-1")
        let assertion = Self.jwt(["sub": "u1", "ouId": "ou-2"])
        StubBackend.reply("/flow/execute", #"{"executionId":"f-1","flowStatus":"COMPLETE","assertion":"\#(assertion)"}"#)
        let result = try await client.switchOrganizationUnit("ou-2")
        guard case .switched(let user) = result else { return XCTFail("Expected a switch") }
        XCTAssertEqual(user.claims["ouId"]?.value as? String, "ou-2")
    }

    func testSwitchNeedsAWayToSignIn() async throws {
        try await makeClient()
        await assertThrows(.invalidConfiguration) { _ = try await self.client.switchOrganizationUnit("ou-2") }
        await assertThrows(.invalidInput) { _ = try await self.client.switchOrganizationUnit(" ") }
    }
}

final class OrganizationUnitBackendTests: BackendTestCase {
    func testBackendSignInPassesTheUnitAsOuId() async throws {
        try await makeClient()
        let url = try client.buildSignInURL(options: SignInOptions(organizationUnitId: "ou-2"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "ouId" }?.value, "ou-2")
        let plain = try client.buildSignInURL()
        XCTAssertFalse(plain.absoluteString.contains("ouId"))
    }

    func testCurrentOrganizationUnitReadsTheBackendSession() async throws {
        StubBackend.reply("/api/auth/session", #"{"isSignedIn":true,"user":{"sub":"u1","ouId":"ou-7","ouName":"Seven"}}"#)
        try await makeClient(readSession: false)
        let unit = try await client.getCurrentOrganizationUnit()
        XCTAssertEqual(unit, CurrentOrganizationUnit(id: "ou-7", name: "Seven"))
    }
}
