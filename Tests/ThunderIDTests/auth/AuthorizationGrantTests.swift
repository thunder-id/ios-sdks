// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class CIBATests: OAuthTestCase {
    private let discovery = "/.well-known/openid-configuration"
    private var metadata: String {
        #"{"token_endpoint":"\#(base)/oauth2/token","backchannel_authentication_endpoint":"\#(base)/oauth2/bc-authorize"}"#
    }

    func testInitiateCIBAPostsToTheDiscoveredEndpointAsAPublicClient() async throws {
        try await makeClient()
        StubBackend.reply(discovery, metadata)
        StubBackend.reply("/oauth2/bc-authorize", #"{"auth_req_id":"r-1","expires_in":90,"interval":3}"#)
        let response = try await client.initiateCIBA(options: CIBAInitiateOptions(
            loginHint: "ada@example.com",
            bindingMessage: "Approve 1234",
            authorizationDetails: [["type": "payment"]]
        ))
        XCTAssertEqual(response, CIBAInitiateResponse(authReqId: "r-1", expiresIn: 90, interval: 3))
        let request = try XCTUnwrap(StubBackend.requests(to: "/oauth2/bc-authorize").first)
        let fields = form(request)
        XCTAssertEqual(fields["client_id"], "client-1")
        XCTAssertEqual(fields["scope"], "openid profile")
        XCTAssertEqual(fields["login_hint"], "ada@example.com")
        XCTAssertEqual(fields["binding_message"], "Approve 1234")
        XCTAssertEqual(fields["authorization_details"], #"[{"type":"payment"}]"#)
        XCTAssertNil(fields["client_secret"])
        XCTAssertNil(request.header("Authorization"))
    }

    func testInitiateCIBAWithoutAnAdvertisedEndpointFails() async throws {
        try await makeClient()
        StubBackend.reply(discovery, #"{"token_endpoint":"\#(base)/oauth2/token"}"#)
        await assertThrows(.endpointNotAdvertised) {
            _ = try await self.client.initiateCIBA(options: .init(loginHint: "ada"))
        }
    }

    func testInitiateCIBANeedsExactlyOneHint() async throws {
        try await makeClient()
        StubBackend.reply(discovery, metadata)
        await assertThrows(.invalidInput) { _ = try await self.client.initiateCIBA(options: .init()) }
        await assertThrows(.invalidInput) {
            _ = try await self.client.initiateCIBA(options: .init(loginHint: "a", idTokenHint: "t"))
        }
    }

    func testCIBAIsRefusedForAConfidentialClient() async throws {
        try await makeClient(clientSecret: "s3cret")
        await assertThrows(.unsupportedOperation) {
            _ = try await self.client.initiateCIBA(options: .init(loginHint: "ada"))
        }
        await assertThrows(.unsupportedOperation) { _ = try await self.client.pollCIBA(authReqId: "r", interval: 1) }
    }

    func testPollCIBAWaitsSlowsDownAndStoresTheTokens() async throws {
        try await makeClient()
        StubBackend.reply(discovery, metadata)
        StubBackend.reply("/oauth2/token", status: 400, #"{"error":"authorization_pending"}"#)
        StubBackend.reply("/oauth2/token", status: 400, #"{"error":"slow_down"}"#)
        StubBackend.reply("/oauth2/token", tokenJSON(["sub": "u1"], refresh: "rt"))
        let tokens = try await client.pollCIBA(authReqId: "r-1", interval: 2)
        XCTAssertEqual(sleeps, [2, 2, 7])
        XCTAssertEqual(tokens.refreshToken, "rt")
        XCTAssertEqual(store.accessToken(), tokens.accessToken)
        let fields = form(StubBackend.requests(to: "/oauth2/token").last)
        XCTAssertEqual(fields["grant_type"], "urn:openid:params:grant-type:ciba")
        XCTAssertEqual(fields["auth_req_id"], "r-1")
        XCTAssertEqual(fields["client_id"], "client-1")
    }

    func testPollCIBAReportsADenialAndAnExpiry() async throws {
        try await makeClient()
        StubBackend.reply(discovery, metadata)
        StubBackend.reply("/oauth2/token", status: 400, #"{"error":"access_denied"}"#)
        await assertThrows(.authorizationDenied) { _ = try await self.client.pollCIBA(authReqId: "r", interval: 1) }
        StubBackend.reset()
        StubBackend.reply(discovery, metadata)
        StubBackend.reply("/oauth2/token", status: 400, #"{"error":"expired_token"}"#)
        await assertThrows(.authorizationExpired) { _ = try await self.client.pollCIBA(authReqId: "r", interval: 1) }
        XCTAssertNil(store.accessToken())
    }
}

final class DeviceAuthorizationTests: OAuthTestCase {
    private let started = #"""
    {"device_code":"secret-device-code","user_code":"BCDF-GHJK","verification_uri":"https://id.example.com/gate/device",
     "verification_uri_complete":"https://id.example.com/gate/device?user_code=BCDF-GHJK","expires_in":600,"interval":5}
    """#

    func testStartDeviceAuthorizationFallsBackToTheDefaultEndpoint() async throws {
        try await makeClient()
        StubBackend.reply("/oauth2/device-authorize", started)
        let response = try await client.startDeviceAuthorization(resource: "https://api.example.com")
        XCTAssertEqual(response.userCode, "BCDF-GHJK")
        XCTAssertEqual(response.deviceCode, "secret-device-code")
        let fields = form(StubBackend.requests(to: "/oauth2/device-authorize").first)
        XCTAssertEqual(fields["client_id"], "client-1")
        XCTAssertEqual(fields["scope"], "openid profile")
        XCTAssertEqual(fields["resource"], "https://api.example.com")
    }

    func testTheDeviceCodeNeverReachesADescription() throws {
        let response = try JSONDecoder().decode(DeviceAuthorizationResponse.self, from: Data(started.utf8))
        var dumped = ""
        dump(response, to: &dumped)
        for text in [String(describing: response), String(reflecting: response), "\(response)", dumped] {
            XCTAssertFalse(text.contains("secret-device-code"), text)
            XCTAssertTrue(text.contains("BCDF-GHJK"))
        }
    }

    func testPollDeviceAuthorizationUsesTheDeviceCodeGrant() async throws {
        try await makeClient()
        StubBackend.reply("/oauth2/token", status: 400, #"{"error":"authorization_pending"}"#)
        StubBackend.reply("/oauth2/token", tokenJSON(["sub": "u1"]))
        let tokens = try await client.pollDeviceAuthorization(deviceCode: "dc", interval: 5)
        XCTAssertEqual(sleeps, [5, 5])
        XCTAssertEqual(store.accessToken(), tokens.accessToken)
        let fields = form(StubBackend.requests(to: "/oauth2/token").first)
        XCTAssertEqual(fields["grant_type"], "urn:ietf:params:oauth:grant-type:device_code")
        XCTAssertEqual(fields["device_code"], "dc")
    }

    func testPollingStopsWhenTheTaskIsCancelled() async throws {
        try await makeClient()
        StubBackend.reply("/oauth2/token", status: 400, #"{"error":"authorization_pending"}"#)
        client.pollSleep = { _ in throw CancellationError() }
        do {
            _ = try await client.pollDeviceAuthorization(deviceCode: "dc", interval: 5)
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
    }

    // MARK: - User side

    func testVerifyDeviceCodeStartsTheDeviceGrantFlowWithTheUserCode() async throws {
        try await makeClient(applicationId: "app-1")
        StubBackend.reply("/flow/execute", #"{"executionId":"f-1","flowStatus":"INCOMPLETE"}"#)
        let response = try await client.verifyDeviceCode(userCode: "BCDF-GHJK")
        XCTAssertEqual(response.flow.flowId, "f-1")
        XCTAssertNil(response.redirectUrl)
        let body = try XCTUnwrap(StubBackend.requests(to: "/flow/execute").first?.json)
        XCTAssertEqual(body["flowType"] as? String, "DEVICE_GRANT")
        XCTAssertEqual(body["applicationId"] as? String, "app-1")
        XCTAssertEqual((body["inputs"] as? [String: String])?["user_code"], "BCDF-GHJK")
        XCTAssertTrue(StubBackend.requests(to: "/oauth2/auth/callback").isEmpty)
    }

    func testCompletedDeviceGrantIsHandedToTheCallback() async throws {
        try await makeClient(applicationId: "app-1")
        StubBackend.reply("/flow/execute", #"""
        {"executionId":"f-1","flowStatus":"COMPLETE","assertion":"a-1",
         "data":{"additionalData":{"authId":"auth-1","callbackType":"DEVICE_CODE"}}}
        """#)
        StubBackend.reply("/oauth2/auth/callback", #"{"redirect_uri":"https://id.example.com/gate/device/done"}"#)
        let response = try await client.verifyDeviceCode(
            payload: EmbeddedSignInPayload(flowId: "f-1", actionId: "device-code-submit", inputs: ["user_code": "X"])
        )
        XCTAssertEqual(response.flow.flowStatus, .complete)
        XCTAssertEqual(response.redirectUrl, "https://id.example.com/gate/device/done")
        let continuation = StubBackend.requests(to: "/flow/execute").first?.json
        XCTAssertEqual(continuation?["executionId"] as? String, "f-1")
        XCTAssertEqual(continuation?["action"] as? String, "device-code-submit")
        let callback = StubBackend.requests(to: "/oauth2/auth/callback").first?.json
        XCTAssertEqual(callback?["assertion"] as? String, "a-1")
        XCTAssertEqual(callback?["authId"] as? String, "auth-1")
        XCTAssertEqual(callback?["type"] as? String, "DEVICE_CODE")
        XCTAssertNil(store.accessToken(), "approving a device does not sign this app in")
    }

    func testDeniedDeviceGrantReportsTheErrorStep() async throws {
        try await makeClient(applicationId: "app-1")
        StubBackend.reply("/flow/execute", #"""
        {"executionId":"f-1","flowStatus":"ERROR","errorAssertion":"e-1","error":{"code":"FET-1"},
         "data":{"additionalData":{"authId":"auth-1","callbackType":"DEVICE_CODE"}}}
        """#)
        StubBackend.reply("/oauth2/auth/callback", status: 400, #"{"error":"access_denied"}"#)
        let response = try await client.verifyDeviceCode(payload: EmbeddedSignInPayload(flowId: "f-1"))
        XCTAssertEqual(response.flow.flowStatus, .error)
        XCTAssertEqual(StubBackend.requests(to: "/oauth2/auth/callback").first?.json?["assertion"] as? String, "e-1")
    }

    func testTerminalStepWithoutCallbackDataFails() async throws {
        try await makeClient(applicationId: "app-1")
        StubBackend.reply("/flow/execute", #"{"executionId":"f-1","flowStatus":"COMPLETE","assertion":"a"}"#)
        await assertThrows(.authenticationFailed) {
            _ = try await self.client.verifyDeviceCode(userCode: "X")
        }
    }

    func testVerifyDeviceCodeNeedsAnApplication() async throws {
        try await makeClient()
        await assertThrows(.invalidConfiguration) { _ = try await self.client.verifyDeviceCode(userCode: "X") }
        await assertThrows(.invalidInput) { _ = try await self.client.verifyDeviceCode(payload: .init()) }
    }
}

final class PushedAuthorizationTests: OAuthTestCase {
    private let discovery = "/.well-known/openid-configuration"

    func testConfiguredPARPushesAndRedirectsWithTheRequestUri() async throws {
        try await makeClient(pushedAuthorizationRequests: true)
        StubBackend.reply("/oauth2/par", status: 201, #"{"request_uri":"urn:ietf:params:oauth:request_uri:x","expires_in":60}"#)
        let url = try await client.signInURL(options: SignInOptions(loginHint: "ada"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(url.path, "/oauth2/authorize")
        XCTAssertEqual(Set(items.map(\.name)), ["client_id", "request_uri"])
        XCTAssertEqual(items.first { $0.name == "request_uri" }?.value, "urn:ietf:params:oauth:request_uri:x")
        let fields = form(StubBackend.requests(to: "/oauth2/par").first)
        XCTAssertEqual(fields["response_type"], "code")
        XCTAssertEqual(fields["code_challenge_method"], "S256")
        XCTAssertEqual(fields["login_hint"], "ada")
        XCTAssertEqual(fields["redirect_uri"], "myapp://callback")
        XCTAssertNotNil(client.pkceManager.codeVerifier)
        XCTAssertThrowsError(try client.buildSignInURL())
    }

    func testServerRequirementPushesEvenWhenTheAppDoesNotAsk() async throws {
        try await makeClient()
        StubBackend.reply(discovery, #"{"require_pushed_authorization_requests":true,"pushed_authorization_request_endpoint":"\#(base)/oauth2/par"}"#)
        StubBackend.reply("/oauth2/par", status: 201, #"{"request_uri":"urn:r"}"#)
        let url = try await client.signInURL(options: SignInOptions(organizationUnitId: "ou-2"))
        XCTAssertEqual(url.path, "/ou/ou-2/oauth2/authorize")
        XCTAssertEqual(StubBackend.requests(to: "/oauth2/par").count, 1)
        XCTAssertEqual(client.pendingOrganizationUnitId, "ou-2")
    }

    func testNoPARWhenNeitherAsks() async throws {
        try await makeClient()
        StubBackend.reply(discovery, #"{"require_pushed_authorization_requests":false}"#)
        let url = try await client.signInURL()
        XCTAssertTrue(url.query?.contains("code_challenge=") ?? false)
        XCTAssertTrue(StubBackend.requests(to: "/oauth2/par").isEmpty)
    }

    func testRefusedPushSurfacesTheOAuthError() async throws {
        try await makeClient(pushedAuthorizationRequests: true)
        StubBackend.reply("/oauth2/par", status: 400, #"{"error":"invalid_request","error_description":"bad"}"#)
        await assertThrows(.invalidInput) { _ = try await self.client.signInURL() }
        XCTAssertNil(client.pkceManager.codeVerifier)
    }
}
