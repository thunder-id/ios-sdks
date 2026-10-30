// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class BackendPermissionsTests: BackendTestCase {
    func testReadsTheGrantedPermissionsFromTheSessionWithoutTheAccessToken() async throws {
        StubBackend.reply(
            "/api/auth/session",
            #"{"isSignedIn":true,"user":{"sub":"u1"},"expiresAt":1900000000,"scope":"openid system:user  system:group:view"}"#
        )
        try await makeClient(readSession: false)

        let permissions = await client.getGrantedPermissions()

        XCTAssertEqual(permissions, ["openid", "system:user", "system:group:view"])
        XCTAssertEqual(StubBackend.requests(to: "/api/auth/session").count, 1)
        XCTAssertTrue(StubBackend.requests(to: "/api/auth/token").isEmpty)
    }

    func testGrantsNothingWhenTheSessionHasNoScopeWithoutAskingForTheAccessToken() async throws {
        try await makeClient()

        let permissions = await client.getGrantedPermissions()

        XCTAssertEqual(permissions, [])
        XCTAssertTrue(StubBackend.requests(to: "/api/auth/token").isEmpty)
    }

    func testGrantsNothingWhenSignedOut() async throws {
        try await makeClient(handle: nil, readSession: false)

        let permissions = await client.getGrantedPermissions()

        XCTAssertEqual(permissions, [])
        XCTAssertTrue(StubBackend.requests.isEmpty)
    }
}
