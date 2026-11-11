// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class BackendOrganizationUnitSwitchTests: BackendTestCase {
    private let switchPath = "/api/auth/switch"
    private let switchedSession = #"{"isSignedIn":true,"user":{"sub":"u1","ouId":"ou 2"}}"#

    /// A browser that fails the test when the switch opens it.
    private let noBrowser = SwitchOrganizationUnitOptions(authorize: { _ in
        XCTFail("The browser was opened")
        throw CancellationError()
    })

    private func refusal(_ body: () async throws -> Void) async -> ThunderIDError? {
        do {
            try await body()
            XCTFail("Expected the switch to fail")
            return nil
        } catch {
            return error as? ThunderIDError
        }
    }

    func testSwitchPostsTheUnitToTheBackendAndReadsTheSessionAgainWithoutTheBrowser() async throws {
        try await makeClient()
        StubBackend.reply(switchPath)
        StubBackend.reply("/api/auth/session", switchedSession)

        let result = try await client.switchOrganizationUnit("ou 2", options: noBrowser)

        guard case .switched(let user) = result else { return XCTFail("Expected a switch") }
        XCTAssertEqual(user.claims["ouId"]?.value as? String, "ou 2")
        let sent = try XCTUnwrap(StubBackend.requests(to: switchPath).first)
        XCTAssertEqual(sent.request.httpMethod, "POST")
        let query = URLComponents(url: try XCTUnwrap(sent.request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "ouId" }?.value, "ou 2")
        XCTAssertEqual(sent.json?["ouId"] as? String, "ou 2")
        XCTAssertEqual(sent.header(backendSessionHandleHeader), "h1")
        XCTAssertEqual(storedHandle, "h1")
    }

    func testSwitchRefreshesAnExpiredSessionOnceAndSwitchesAgain() async throws {
        try await makeClient()
        StubBackend.reply(switchPath, status: 401, #"{"error":"session_expired"}"#)
        StubBackend.reply(switchPath)
        StubBackend.reply("/api/auth/refresh")
        StubBackend.reply("/api/auth/session", switchedSession)

        let result = try await client.switchOrganizationUnit("ou 2")

        guard case .switched(let user) = result else { return XCTFail("Expected a switch") }
        XCTAssertEqual(user.claims["ouId"]?.value as? String, "ou 2")
        XCTAssertEqual(StubBackend.requests(to: switchPath).count, 2)
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/refresh").count, 1)
    }

    func testRefusedSwitchKeepsTheSessionAndDoesNotOpenTheBrowser() async throws {
        try await makeClient()
        StubBackend.reply(switchPath, status: 400, #"{"error":"unauthorized_client"}"#)

        let refused = await refusal { _ = try await self.client.switchOrganizationUnit("ou-2", options: self.noBrowser) }

        XCTAssertEqual(refused?.code, .organizationUnitUnavailable)
        XCTAssertEqual(refused?.serverError?.code, "unauthorized_client")
        XCTAssertEqual(storedHandle, "h1")
        let signedIn = try await client.isSignedIn()
        XCTAssertTrue(signedIn)
    }

    func testBackendWithoutASwitchEndpointRefusesTheSwitch() async throws {
        try await makeClient()
        StubBackend.reply(switchPath, status: 404, "")

        await assertThrows(.authenticationFailed) {
            _ = try await self.client.switchOrganizationUnit("ou-2", options: self.noBrowser)
        }
        XCTAssertEqual(storedHandle, "h1")
    }

    func testSwitchThatNeedsTheUserSignsInToTheUnitThroughTheBrowser() async throws {
        try await makeClient()
        StubBackend.reply(switchPath, status: 400, #"{"error":"interaction_required"}"#)

        let withoutBrowser = await refusal { _ = try await self.client.switchOrganizationUnit("ou-2") }
        XCTAssertEqual(withoutBrowser?.code, .authenticationFailed)
        XCTAssertEqual(withoutBrowser?.serverError?.code, "interaction_required")

        StubBackend.reply("/api/auth/session", #"{"isSignedIn":true,"handle":"h2","user":{"sub":"u1","ouId":"ou-2"}}"#)
        var opened: URL?
        let options = SwitchOrganizationUnitOptions(authorize: { url in
            opened = url
            return URL(string: "myapp://callback?session_code=c2")!
        })
        let result = try await client.switchOrganizationUnit("ou-2", options: options)

        guard case .switched(let user) = result else { return XCTFail("Expected a switch") }
        XCTAssertEqual(user.claims["ouId"]?.value as? String, "ou-2")
        let openedQuery = URLComponents(url: try XCTUnwrap(opened), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(openedQuery?.first { $0.name == "ouId" }?.value, "ou-2")
        XCTAssertEqual(storedHandle, "h2")
    }

    func testSwitchWhoseSessionHasEndedSignsOut() async throws {
        try await makeClient()
        // A 401 means the backend has no session to switch, whatever its body says.
        StubBackend.reply(switchPath, status: 401, #"{"error":"invalid_token"}"#)

        let refused = await refusal { _ = try await self.client.switchOrganizationUnit("ou-2") }

        XCTAssertEqual(refused?.code, .authenticationFailed)
        XCTAssertEqual(refused?.serverError?.code, "login_required")
        XCTAssertNil(storedHandle)
        XCTAssertEqual(signOuts, 1)
    }
}
