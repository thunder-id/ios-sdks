// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class OrganizationUnitTests: OAuthTestCase {
    private let units = #"""
    {"current":"ou-1","totalResults":3,"startIndex":11,"count":2,"links":[],
     "organizationUnits":[{"id":"ou-1","handle":"acme-1","name":"Acme 1"},
                          {"id":"ou-2","handle":"acme-2","name":"Acme 2","logoUrl":"https://x/l.png"}]}
    """#

    // MARK: - Account data layer

    func testAccessibleOrganizationUnitsReadsUsersMeOusWithTheUsersToken() async throws {
        try await makeClient()
        try storeSession(["sub": "u1"])
        StubBackend.reply("/users/me/ous", units)
        let list = try await client.getAccessibleOrganizationUnits(scope: .siblings, limit: 2, offset: 10)
        let request = try XCTUnwrap(StubBackend.requests(to: "/users/me/ous").first)
        XCTAssertEqual(request.request.url?.query, "scope=siblings&limit=2&offset=10")
        XCTAssertEqual(request.header("Authorization"), "Bearer \(store.accessToken()!)")
        XCTAssertEqual(list.current, "ou-1")
        XCTAssertEqual(list.organizationUnits.map(\.handle), ["acme-1", "acme-2"])
        XCTAssertEqual(list.totalResults, 3)
        XCTAssertEqual(list.startIndex, 11)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.organizationUnits[1].logoUrl, "https://x/l.png")
    }

    func testAccessibleOrganizationUnitsWithoutOptionsSendsNoQuery() async throws {
        try await makeClient()
        try storeSession(["sub": "u1"])
        StubBackend.reply("/users/me/ous", units)
        _ = try await client.getAccessibleOrganizationUnits()
        XCTAssertNil(StubBackend.requests(to: "/users/me/ous").first?.request.url?.query)
    }

    func testAccessibleOrganizationUnitsMapsServerErrors() async throws {
        try await makeClient()
        try storeSession(["sub": "u1"])
        StubBackend.reply("/users/me/ous", status: 400, #"{"code":"USR-1036","message":"Invalid scope parameter"}"#)
        let error = await assertThrowing { _ = try await self.client.getAccessibleOrganizationUnits() }
        XCTAssertEqual(error?.code, .invalidInput)
        XCTAssertEqual(error?.serverError?.code, "USR-1036")
        StubBackend.reset()
        StubBackend.reply("/users/me/ous", status: 403, "{}")
        await assertThrows(.forbidden) { _ = try await self.client.getAccessibleOrganizationUnits() }
    }

    func testCurrentOrganizationUnitComesFromTheSessionClaims() async throws {
        try await makeClient()
        try storeSession(["sub": "u1", "ouId": "ou-1", "ouHandle": "acme-1", "ouName": "Acme 1"])
        let unit = try await client.getCurrentOrganizationUnit()
        XCTAssertEqual(unit, CurrentOrganizationUnit(id: "ou-1", handle: "acme-1", name: "Acme 1"))
    }

    func testCurrentOrganizationUnitIsNilWithoutTheClaims() async throws {
        try await makeClient()
        try storeSession(["sub": "u1"])
        let unit = try await client.getCurrentOrganizationUnit()
        XCTAssertNil(unit)
    }

    // MARK: - Redirect sign-in bounded to a unit

    func testSignInWithoutAUnitKeepsTheAuthorizeEndpoint() async throws {
        try await makeClient()
        let url = try client.buildSignInURL()
        XCTAssertEqual(url.path, "/oauth2/authorize")
        XCTAssertNil(client.pendingOrganizationUnitId)
    }

    func testSignInBoundedToAUnitAuthorizesAtTheUnitAndEncodesItsId() async throws {
        try await makeClient()
        let url = try client.buildSignInURL(options: SignInOptions(organizationUnitId: "a/b c"))
        XCTAssertTrue(url.absoluteString.hasPrefix("\(base)/ou/a%2Fb%20c/oauth2/authorize?"), url.absoluteString)
        XCTAssertEqual(client.pendingOrganizationUnitId, "a/b c")
    }

    func testBoundedCodeIsRedeemedAtTheUnitsTokenEndpointAndReplacesTheSession() async throws {
        try await makeClient()
        try storeSession(["sub": "u1", "ouId": "ou-1"], refreshToken: "old-refresh")
        _ = try client.buildSignInURL(options: SignInOptions(organizationUnitId: "ou-2"))
        StubBackend.reply("/ou/ou-2/oauth2/token", tokenJSON(["sub": "u1", "ouId": "ou-2"]))
        let user = try await client.handleRedirectCallback(url: URL(string: "myapp://callback?code=c-1")!)
        let request = try XCTUnwrap(StubBackend.requests(to: "/ou/ou-2/oauth2/token").first)
        XCTAssertEqual(request.header("Content-Type"), "application/x-www-form-urlencoded")
        let fields = form(request)
        XCTAssertEqual(fields["grant_type"], "authorization_code")
        XCTAssertEqual(fields["code"], "c-1")
        XCTAssertEqual(fields["client_id"], "client-1")
        XCTAssertNotNil(fields["code_verifier"])
        XCTAssertEqual(user.claims["ouId"]?.value as? String, "ou-2")
        XCTAssertNil(store.refreshToken(), "the previous unit's refresh token must not carry over")
        XCTAssertNil(client.pendingOrganizationUnitId)
    }

    func testRefusedUnitLeavesTheSessionAsItWas() async throws {
        try await makeClient()
        try storeSession(["sub": "u1", "ouId": "ou-1"], refreshToken: "old-refresh")
        let before = store.accessToken()
        _ = try client.buildSignInURL(options: SignInOptions(organizationUnitId: "ou-x"))
        await assertThrows(.organizationUnitUnavailable) {
            _ = try await self.client.handleRedirectCallback(
                url: URL(string: "myapp://callback?error=unauthorized_client")!
            )
        }
        XCTAssertEqual(store.accessToken(), before)
        XCTAssertEqual(store.refreshToken(), "old-refresh")
        XCTAssertTrue(StubBackend.requests.isEmpty)
    }

    func testCodeNotIssuedForTheUnitIsAnInvalidGrant() async throws {
        try await makeClient()
        try storeSession(["sub": "u1"])
        let before = store.accessToken()
        _ = try client.buildSignInURL(options: SignInOptions(organizationUnitId: "ou-2"))
        StubBackend.reply("/ou/ou-2/oauth2/token", status: 400, #"{"error":"invalid_grant"}"#)
        await assertThrows(.invalidGrant) {
            _ = try await self.client.handleRedirectCallback(url: URL(string: "myapp://callback?code=c")!)
        }
        XCTAssertEqual(store.accessToken(), before)
    }

    // MARK: - App-native sign-in bounded to a unit

    func testEmbeddedSignInSendsTheUnitOnlyWhenTheAuthenticationFlowStarts() async throws {
        try await makeClient(applicationId: "app-1")
        StubBackend.reply("/flow/execute", #"{"executionId":"f-1","flowStatus":"INCOMPLETE"}"#)
        let request = EmbeddedFlowRequestConfig(applicationId: "app-1", organizationUnitId: "ou-2")
        _ = try await client.signIn(payload: EmbeddedSignInPayload(), request: request)
        _ = try await client.signIn(payload: EmbeddedSignInPayload(flowId: "f-1", actionId: "a"), request: request)
        let registration = EmbeddedFlowRequestConfig(
            applicationId: "app-1",
            flowType: .registration,
            organizationUnitId: "ou-2"
        )
        _ = try await client.signUp(request: registration)
        let bodies = StubBackend.requests(to: "/flow/execute").map(\.json)
        XCTAssertEqual(bodies[0]?["ouId"] as? String, "ou-2")
        XCTAssertNil(bodies[1]?["ouId"])
        XCTAssertNil(bodies[2]?["ouId"])
    }

    func testEmbeddedSignInWithoutAUnitSendsNone() async throws {
        try await makeClient(applicationId: "app-1")
        StubBackend.reply("/flow/execute", #"{"executionId":"f-1","flowStatus":"INCOMPLETE"}"#)
        _ = try await client.signIn(
            payload: EmbeddedSignInPayload(),
            request: EmbeddedFlowRequestConfig(applicationId: "app-1")
        )
        XCTAssertNil(StubBackend.requests(to: "/flow/execute").first?.json?["ouId"])
    }

    // MARK: - Helpers

    private func assertThrowing(_ body: () async throws -> Void) async -> ThunderIDError? {
        do {
            try await body()
            XCTFail("Expected an error")
        } catch {
            return error as? ThunderIDError
        }
        return nil
    }
}
