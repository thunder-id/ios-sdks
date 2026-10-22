// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers the reactive management wrappers against the real `HTTPClient` path, through
/// `MockURLProtocol`.
@MainActor
final class AdminStateTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeState(accessToken: String = "test-access-token") async throws -> ThunderIDState {
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "test-client")
        let storage = InMemoryStorageAdapter()
        try TokenStore(storage: storage).save(
            TokenResponse(accessToken: accessToken, tokenType: "Bearer", expiresIn: 3600)
        )
        let client = ThunderIDClient()
        _ = try await client.initialize(config: config, storage: storage, session: MockURLProtocol.makeSession())
        return ThunderIDState(client: client, i18n: ThunderIDI18n())
    }

    private func respond(_ json: String, status: Int = 200) {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testAddingMembersRefetchesTheGroupsMembersAndMemberships() async throws {
        let state = try await makeState()
        respond(
            #"{"id":"g-1","name":"Admins","ouId":"ou","totalResults":0,"startIndex":1,"count":0,"# +
            #""members":[],"groups":[]}"#
        )
        let members = state.groupMembersQuery(groupId: "g-1")
        let userGroups = state.userGroupsQuery(userId: "u-1")
        let otherGroup = state.groupMembersQuery(groupId: "g-2")
        await members.refetch()
        await userGroups.refetch()
        await otherGroup.refetch()

        let mutation = state.addGroupMembersMutation()
        let group = await mutation.mutate((groupId: "g-1", members: [GroupMemberInput(id: "u-1", type: .user)]))

        XCTAssertEqual(group?.name, "Admins")
        await waitFor {
            MockURLProtocol.requestCount(forPath: "/groups/g-1/members") == 2
                && MockURLProtocol.requestCount(forPath: "/users/u-1/groups") == 2
        }
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/groups/g-1/members/add"), 1)
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/groups/g-1/members"), 2)
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/users/u-1/groups"), 2)
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/groups/g-2/members"), 1)
    }

    func testFailedMutationReportsItsErrorWithoutThrowing() async throws {
        let state = try await makeState()
        respond(#"{"message":"denied by policy"}"#, status: 403)
        let mutation = state.removeRoleAssignmentsMutation()

        let result: Void? = await mutation.mutate((roleId: "r-1", assignments: [RoleAssignmentInput(id: "u", type: .user)]))

        XCTAssertNil(result)
        XCTAssertEqual((mutation.error as? ThunderIDError)?.code, .forbidden)
        XCTAssertFalse(mutation.isLoading)
    }

    func testRoleQueryExposesNotFoundAsItsOwnCode() async throws {
        let state = try await makeState()
        respond("{}", status: 404)
        let role = state.roleQuery(id: "missing")

        await role.refetch()

        XCTAssertNil(role.data)
        XCTAssertEqual((role.error as? ThunderIDError)?.code, .notFound)
    }

    func testGrantedPermissionsComeFromTheAccessToken() async throws {
        let payload = Data(#"{"scope":"openid system:user"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let state = try await makeState(accessToken: "e30.\(payload).sig")
        let granted = state.grantedPermissions()

        await granted.refresh()

        XCTAssertEqual(granted.permissions, ["openid", "system:user"])
        XCTAssertTrue(granted.can("system:user:view"))
        XCTAssertFalse(granted.can("system:group:view"))
        XCTAssertEqual(MockURLProtocol.requestCount, 0)
    }
}
