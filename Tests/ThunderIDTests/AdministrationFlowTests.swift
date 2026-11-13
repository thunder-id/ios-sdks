// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class AdministrationFlowTests: XCTestCase {
    private let baseUrl = ManagementTestServer.baseUrl

    private func deletionServer() -> ManagementTestServer {
        let server = ManagementTestServer()
        server.config = #"{"userDeletionFlow":{"defaultHandle":"delete-user"}}"#
        server.flows = [("delete-user", "flow-1")]
        return server
    }

    func testConstantsMatchTheServer() {
        XCTAssertEqual(AdministrationFlowConfigKey.allCases.count, 18)
        XCTAssertEqual(
            AdministrationFlowConfigKey.adminAttributeVerification.rawValue,
            "adminAttributeVerificationFlow"
        )
        XCTAssertEqual(AdministrationFlowConfigKey.secretRegeneration.rawValue, "secretRegenerationFlow")
        XCTAssertEqual(AdministrationFlowConfigKey.groupMembershipRemoval.rawValue, "groupMembershipRemovalFlow")
        XCTAssertEqual(AdministrationFlowInput.subject, "subject")
        XCTAssertEqual(AdministrationFlowInput.permissions, "targetPermissions")
        XCTAssertEqual(AdministrationFlowData.clientSecret, "clientSecret")
        XCTAssertEqual(AdministrationFlowConstants.flowType, "ADMINISTRATION")
    }

    func testCallsTheAPIDirectlyByDefaultWithoutReadingTheFlowConfiguration() async throws {
        let server = deletionServer()
        let client = try await server.makeClient()

        try await client.users.delete(id: "u-1")

        XCTAssertEqual(server.calls, ["DELETE \(baseUrl)/users/u-1"])
    }

    func testRunsTheConfiguredFlowInFlowModeInsteadOfCallingTheAPI() async throws {
        let server = deletionServer()
        let client = try await server.makeClient()

        try await client.users.delete(id: "u-1", administrationMode: .flow)

        XCTAssertEqual(server.calls, [
            "GET \(baseUrl)/server-config/flow",
            "GET \(baseUrl)/flows?flowType=ADMINISTRATION&limit=100&offset=0",
            "POST \(baseUrl)/flow/execute"
        ])
        XCTAssertEqual(server.executions.first?["flowId"] as? String, "flow-1")
        XCTAssertEqual(server.executions.first?["inputs"] as? [String: String], ["subject": "u-1"])
    }

    func testCallsTheAPIDirectlyInFlowModeWhenNoFlowIsConfigured() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()

        try await client.groups.delete(id: "g-1", administrationMode: .flow)

        XCTAssertTrue(server.executions.isEmpty)
        XCTAssertEqual(server.calls, ["GET \(baseUrl)/server-config/flow", "DELETE \(baseUrl)/groups/g-1"])
    }

    func testRefusesWhenTheConfiguredFlowNoLongerExists() async throws {
        let server = ManagementTestServer()
        server.config = #"{"roleDeletionFlow":{"defaultHandle":"gone"}}"#
        let client = try await server.makeClient()

        let error = await assertThrowsThunderIDError(.administrationFlowNotFound) {
            try await client.roles.delete(id: "r-1", administrationMode: .flow)
        }

        XCTAssertEqual(error?.isAdministrationFlowError, true)
        XCTAssertFalse(server.calls.contains { $0.hasPrefix("DELETE") })
    }

    func testReportsARefusedStepWithTheStepsOwnCode() async throws {
        let server = ManagementTestServer()
        server.config = #"{"applicationDeletionFlow":{"defaultHandle":"delete-app"}}"#
        server.flows = [("delete-app", "flow-2")]
        server.execution = #"{"flowStatus":"ERROR","error":{"code":"FLW-4001","message":{"defaultValue":"Not allowed"}}}"#
        let client = try await server.makeClient()

        let error = await assertThrowsThunderIDError(.administrationFlowFailed) {
            try await client.applications.delete(id: "app-1", administrationMode: .flow)
        }

        XCTAssertEqual(error?.flowError?.code, "FLW-4001")
        XCTAssertEqual(error?.message.contains("Not allowed"), true)
        XCTAssertEqual(server.executions.first?["inputs"] as? [String: String], ["targetApplicationId": "app-1"])
        XCTAssertFalse(server.calls.contains { $0.hasPrefix("DELETE") })
    }

    func testRefusesAFlowThatAsksForMoreInput() async throws {
        let server = deletionServer()
        server.execution = #"{"flowStatus":"INCOMPLETE","executionId":"e-1"}"#
        let client = try await server.makeClient()

        await assertThrowsThunderIDError(.administrationFlowIncomplete) {
            try await client.users.delete(id: "u-1", administrationMode: .flow)
        }
        XCTAssertFalse(server.calls.contains { $0.hasPrefix("DELETE") })
    }

    func testNeedsTheServerURLToRunAFlow() async throws {
        let server = deletionServer()
        let transport = ManagementTransport(
            httpClient: HTTPClient(baseUrl: ""),
            baseUrl: "",
            collectionUrl: "\(baseUrl)/users",
            fetcher: server.fetcher
        )
        let users = UsersAPI(transport: transport, typesTransport: transport)

        await assertThrowsThunderIDError(.invalidConfiguration) {
            try await users.delete(id: "u-1", administrationMode: .flow)
        }
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testFlowRequestsGoToTheServerWhateverTheCollectionOverride() async throws {
        let server = deletionServer()
        let transport = ManagementTransport(
            httpClient: HTTPClient(baseUrl: baseUrl),
            baseUrl: baseUrl,
            collectionUrl: "https://rs.example.com/users",
            fetcher: server.fetcher
        )

        try await UsersAPI(transport: transport, typesTransport: transport).delete(id: "u-1", administrationMode: .flow)

        XCTAssertEqual(server.calls.last, "POST \(baseUrl)/flow/execute")
        XCTAssertFalse(server.calls.contains { $0.contains("rs.example.com") })
    }

    func testRunsTheRemovalFlowOnceForEachMemberAndForEachAssignee() async throws {
        let server = ManagementTestServer()
        server.config = #"{"groupMembershipRemovalFlow":{"defaultHandle":"remove-member"},"#
            + #""roleAssignmentRemovalFlow":{"defaultHandle":"remove-assignment"}}"#
        server.flows = [("remove-member", "flow-m"), ("remove-assignment", "flow-a")]
        server.resource = #"{"id":"g-1","name":"Admins","ouId":"ou-1"}"#
        let client = try await server.makeClient()

        let group = try await client.groups.removeMembers(
            id: "g-1",
            [GroupMemberInput(id: "u-1", type: .user), GroupMemberInput(id: "u-2", type: .user)],
            administrationMode: .flow
        )
        try await client.roles.removeAssignments(
            id: "r-1",
            [RoleAssignmentInput(id: "g-1", type: .group)],
            administrationMode: .flow
        )

        XCTAssertEqual(group.id, "g-1")
        XCTAssertTrue(server.calls.contains("GET \(baseUrl)/groups/g-1?include=display"))
        XCTAssertFalse(server.calls.contains { $0.contains("/members/remove") || $0.contains("/assignments/remove") })
        XCTAssertEqual(server.executions.map { $0["flowId"] as? String }, ["flow-m", "flow-m", "flow-a"])
        XCTAssertEqual(server.executions.map { $0["inputs"] as? [String: String] }, [
            ["targetGroupId": "g-1", "targetMemberId": "u-1"],
            ["targetGroupId": "g-1", "targetMemberId": "u-2"],
            ["targetAssigneeId": "g-1", "targetRoleId": "r-1"]
        ])
    }

    func testWalksTheFlowListingPageByPageUntilTheHandleIsFound() async throws {
        let server = ManagementTestServer()
        let firstPage = (0..<100)
            .map { #"{"flowType":"ADMINISTRATION","handle":"flow-\#($0)","id":"id-\#($0)"}"# }
            .joined(separator: ",")
        server.listing = { url in
            url.absoluteString.contains("offset=0")
                ? #"{"flows":[\#(firstPage)]}"#
                : #"{"flows":[{"flowType":"ADMINISTRATION","handle":"late","id":"id-late"}]}"#
        }
        let client = try await server.makeClient()

        let found = try await client.administrationFlows.find(handles: ["late"])

        XCTAssertEqual(found["late"]?.id, "id-late")
        XCTAssertEqual(server.calls, [
            "GET \(baseUrl)/flows?flowType=ADMINISTRATION&limit=100&offset=0",
            "GET \(baseUrl)/flows?flowType=ADMINISTRATION&limit=100&offset=100"
        ])
    }

    func testResolvesSeveralOperationsInOneReadAndOneWalk() async throws {
        let server = ManagementTestServer()
        server.config = #"{"userDeletionFlow":{"defaultHandle":"delete-user"},"#
            + #""groupDeletionFlow":{"defaultHandle":"gone"},"otherSetting":5}"#
        server.flows = [("delete-user", "flow-1")]
        let client = try await server.makeClient()

        let resolved = try await client.administrationFlows.resolve([.userDeletion, .groupDeletion, .roleDeletion])

        XCTAssertEqual(resolved, [.userDeletion: "flow-1"])
        XCTAssertEqual(server.requests.count, 2)
    }

    // MARK: - Role permissions

    private let role = #"{"id":"r-1","name":"Viewer","ouId":"ou-1","#
        + #""permissions":[{"resourceServerId":"rs-1","permissions":["read","write"]}]}"#

    private func permissionServer() -> ManagementTestServer {
        let server = ManagementTestServer()
        server.config = #"{"rolePermissionRemovalFlow":{"defaultHandle":"remove-permission"}}"#
        server.flows = [("remove-permission", "flow-p")]
        server.resource = role
        return server
    }

    func testUpdateRoleSavesDirectlyWhenNoPermissionIsRemoved() async throws {
        let server = permissionServer()
        let client = try await server.makeClient()
        let current = try JSONDecoder().decode(Role.self, from: Data(role.utf8))

        _ = try await client.roles.update(
            id: "r-1",
            UpdateRoleRequest(
                name: "Viewer",
                ouId: "ou-1",
                permissions: [RoleResourcePermissions(resourceServerId: "rs-1", permissions: ["read", "write", "admin"])]
            ),
            current: current,
            administrationMode: .flow
        )

        XCTAssertTrue(server.executions.isEmpty)
        XCTAssertEqual(server.calls, ["PUT \(baseUrl)/roles/r-1"])
    }

    func testUpdateRoleRunsTheFlowForARemovedPermissionAfterSavingTheOtherFields() async throws {
        let server = permissionServer()
        let client = try await server.makeClient()
        let permissions = [RoleResourcePermissions(resourceServerId: "rs-1", permissions: ["read"])]

        let updated = try await client.roles.update(
            id: "r-1",
            UpdateRoleRequest(name: "Reader", ouId: "ou-1", permissions: permissions),
            administrationMode: .flow
        )

        XCTAssertEqual(server.calls.first, "GET \(baseUrl)/roles/r-1?include=display")
        let put = try XCTUnwrap(server.body(of: "PUT"))
        XCTAssertEqual(put["name"] as? String, "Reader")
        let kept = try XCTUnwrap(put["permissions"] as? [[String: Any]])
        XCTAssertEqual(kept.first?["permissions"] as? [String], ["read", "write"])
        XCTAssertEqual(server.executions.map { $0["inputs"] as? [String: String] }, [[
            "targetPermissions": #"[{"permissions":["read"],"resourceServerId":"rs-1"}]"#,
            "targetRoleId": "r-1"
        ]])
        XCTAssertEqual(updated.permissions, permissions)
    }

    func testUpdateRoleSkipsThePutWhenOnlyPermissionsChange() async throws {
        let server = permissionServer()
        let client = try await server.makeClient()

        _ = try await client.roles.update(
            id: "r-1",
            UpdateRoleRequest(name: "Viewer", ouId: "ou-1", permissions: []),
            administrationMode: .flow
        )

        XCTAssertFalse(server.calls.contains { $0.hasPrefix("PUT") })
        XCTAssertEqual(server.executions.count, 1)
    }

    // MARK: - Secret regeneration flow

    func testReturnsTheSecretARegenerationFlowProduced() async throws {
        let server = ManagementTestServer()
        server.config = #"{"secretRegenerationFlow":{"defaultHandle":"rotate"}}"#
        server.flows = [("rotate", "flow-s")]
        server.execution = #"{"flowStatus":"COMPLETE","data":{"additionalData":{"clientSecret":"from-flow"}}}"#
        let client = try await server.makeClient()

        let result = try await client.applications.regenerateClientSecret(id: "app-1", administrationMode: .flow)

        XCTAssertEqual(result.clientSecret, "from-flow")
        XCTAssertNil(result.application)
        XCTAssertFalse(server.calls.contains { $0.hasPrefix("PUT") })
    }

    func testRefusesARegenerationFlowThatReturnsNoSecret() async throws {
        let server = ManagementTestServer()
        server.config = #"{"secretRegenerationFlow":{"defaultHandle":"rotate"}}"#
        server.flows = [("rotate", "flow-s")]
        let client = try await server.makeClient()

        await assertThrowsThunderIDError(.administrationFlowFailed) {
            _ = try await client.applications.regenerateClientSecret(id: "app-1", administrationMode: .flow)
        }
    }
}
