// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class ThunderIDPermissionsTests: XCTestCase {
    private func token(_ claims: [String: Any]) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: claims)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJub25lIn0.\(payload).sig"
    }

    func testReadsTheScopeClaim() throws {
        let permissions = ThunderIDPermissions.fromAccessToken(try token(["scope": "openid  system:user:view"]))
        XCTAssertEqual(permissions, ["openid", "system:user:view"])
    }

    func testPrefersTheScopesListClaim() throws {
        let permissions = ThunderIDPermissions.fromAccessToken(
            try token(["scopes": ["system", 7, "system:group"], "scope": "ignored"])
        )
        XCTAssertEqual(permissions, ["system", "system:group"])
    }

    func testMalformedOrMissingTokensGrantNothing() {
        XCTAssertEqual(ThunderIDPermissions.fromAccessToken(nil), [])
        XCTAssertEqual(ThunderIDPermissions.fromAccessToken("opaque-token"), [])
        XCTAssertEqual(ThunderIDPermissions.fromAccessToken("a.%%%.c"), [])
    }

    func testHierarchicalMatch() {
        XCTAssertTrue(ThunderIDPermissions.has(["system"], "system:user:view"))
        XCTAssertTrue(ThunderIDPermissions.has(["system:user"], "system:user:view"))
        XCTAssertTrue(ThunderIDPermissions.has(["system:user:view"], "system:user:view"))
        XCTAssertFalse(ThunderIDPermissions.has(["system:user:view"], "system:user"))
        XCTAssertFalse(ThunderIDPermissions.has(["system:user"], "system:users:view"))
        XCTAssertFalse(ThunderIDPermissions.has(["sys"], "system:user:view"))
        XCTAssertFalse(ThunderIDPermissions.has([], "system"))
        XCTAssertTrue(ThunderIDPermissions.has([], ""))
    }

    func testClientReadsThePermissionsOfTheStoredAccessToken() async throws {
        let storage = InMemoryStorageAdapter()
        try TokenStore(storage: storage).save(
            TokenResponse(accessToken: try token(["scope": "system"]), tokenType: "Bearer", expiresIn: 3600)
        )
        let client = ThunderIDClient()
        _ = try await client.initialize(
            config: ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "client"),
            storage: storage
        )

        let granted = await client.getGrantedPermissions()

        XCTAssertEqual(granted, ["system"])
        XCTAssertTrue(ThunderIDPermissions.has(granted, "system:user:view"))
    }

    func testManagedIdentityNameFallsBackThroughDisplayNameAttributesAndId() {
        XCTAssertEqual(resolveManagedIdentityName(id: "u-1", display: "Alice"), "Alice")
        XCTAssertEqual(resolveManagedIdentityName(id: "a-1", name: "Concierge"), "Concierge")
        XCTAssertEqual(
            resolveManagedIdentityName(
                id: "u-1",
                attributes: ["given_name": AnyCodable("Ada"), "family_name": AnyCodable("Lovelace")]
            ),
            "Ada Lovelace"
        )
        XCTAssertEqual(resolveManagedIdentityName(id: "u-1", attributes: ["username": AnyCodable("ada")]), "ada")
        XCTAssertEqual(resolveManagedIdentityName(id: "u-1", display: ""), "u-1")
    }
}
