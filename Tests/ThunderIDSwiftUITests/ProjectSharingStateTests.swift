// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers the project, organization unit and sharing wrappers against the real `HTTPClient` path, through
/// `MockURLProtocol`, and the current project the state keeps.
@MainActor
final class ProjectSharingStateTests: XCTestCase {
    private let storageKey = "project_sharing_state_tests_current_project"

    private final class Captured<Value>: @unchecked Sendable {
        var value: Value?
    }

    override func tearDown() {
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: storageKey)
        super.tearDown()
    }

    private func makeState() async throws -> ThunderIDState {
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "test-client")
        let storage = InMemoryStorageAdapter()
        try TokenStore(storage: storage).save(
            TokenResponse(accessToken: "test-access-token", tokenType: "Bearer", expiresIn: 3600)
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

    private func project(_ id: String = "p-1") throws -> Project {
        try JSONDecoder().decode(
            Project.self,
            from: Data(#"{"id":"\#(id)","handle":"shop","displayName":"Online shop"}"#.utf8)
        )
    }

    // MARK: - Current project

    func testCurrentProjectIsKeptAndIsNotAnOrganizationUnit() async throws {
        let state = ThunderIDState(client: ThunderIDClient(), i18n: ThunderIDI18n())
        state.restoreCurrentProject(storageKey: storageKey)
        state.setCurrentProject(try project())

        // A project id is not an organization unit id, so it never becomes the default unit.
        let projectDefault = await state.defaultOuId()
        XCTAssertNil(projectDefault)
        let restored = ThunderIDState(client: ThunderIDClient(), i18n: ThunderIDI18n())
        restored.restoreCurrentProject(storageKey: storageKey)
        XCTAssertEqual(restored.currentProject?.displayName, "Online shop")

        state.setCurrentProject(nil)
        XCTAssertNil(UserDefaults.standard.data(forKey: storageKey))
    }

    func testDeletingTheCurrentProjectClearsIt() async throws {
        let state = try await makeState()
        state.setCurrentProject(try project())
        respond("")

        let deleted: Void? = await state.deleteProjectMutation().mutate("p-1")

        XCTAssertNotNil(deleted)
        XCTAssertNil(state.currentProject)
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/projects/p-1"), 1)
    }

    func testApplicationAndAgentListsTakeTheProject() async throws {
        let state = try await makeState()
        let urls = Captured<[URL]>()
        urls.value = []
        MockURLProtocol.handler = { request in
            urls.value?.append(request.url!)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = request.url!.path.hasSuffix("agents")
                ? #"{"totalResults":0,"startIndex":1,"count":0,"agents":[]}"#
                : #"{"totalResults":0,"count":0,"applications":[]}"#
            return (response, Data(body.utf8))
        }

        await state.applicationsQuery(limit: 5, projectId: "p-1").refetch()
        await state.agentsQuery(limit: 5, projectId: "p-1").refetch()
        await state.applicationsQuery(limit: 5).refetch()

        let queries = (urls.value ?? []).map { $0.query ?? "" }
        XCTAssertEqual(queries, ["limit=5&projectId=p-1", "limit=5&projectId=p-1&include=display", "limit=5"])
    }

    // MARK: - Organization units

    func testOrganizationUnitsListRootsOrChildren() async throws {
        let state = try await makeState()
        respond(#"{"totalResults":1,"organizationUnits":[{"id":"ou-2","handle":"eng","name":"Engineering"}]}"#)

        let roots = state.organizationUnitsQuery(limit: 5)
        let children = state.organizationUnitsQuery(parentId: "ou-1", limit: 5)
        await roots.refetch()
        await children.refetch()

        XCTAssertEqual(children.data?.organizationUnits.first?.name, "Engineering")
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/organization-units"), 1)
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/organization-units/ou-1/ous"), 1)
    }

    func testCreatingAnOrganizationUnitRefetchesTheLists() async throws {
        let state = try await makeState()
        respond(#"{"id":"ou-3","handle":"ops","name":"Ops","parent":"ou-1","organizationUnits":[]}"#)
        let children = state.organizationUnitsQuery(parentId: "ou-1")
        await children.refetch()

        let created = await state.createOrganizationUnitMutation()
            .mutate(OrganizationUnitRequest(handle: "ops", name: "Ops", parent: "ou-1"))

        XCTAssertEqual(created?.id, "ou-3")
        await waitFor { MockURLProtocol.requestCount(forPath: "/organization-units/ou-1/ous") == 2 }
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/organization-units/ou-1/ous"), 2)
    }

    // MARK: - Sharing

    func testSharingRunsThroughTheResourceTypesOwnOperations() async throws {
        let state = try await makeState()
        respond(#"{"totalResults":0,"policies":[],"ouId":"ou-1","visible":true}"#)

        for type in SharingResourceType.allCases {
            await state.sharingPoliciesQuery(resourceType: type, resourceId: "r-1").refetch()
        }
        await state.overlayRulesQuery(resourceType: .role, resourceId: "r-1", ouId: "ou-1").refetch()

        for collection in ["users", "applications", "roles", "flows"] {
            XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/\(collection)/r-1/sharing-policies"), 1, collection)
        }
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/roles/r-1/overlay-rules"), 1)
    }

    func testCreatingAPolicyRefetchesThatResourcesPolicies() async throws {
        let state = try await makeState()
        respond(#"{"id":"pol-1","version":1,"totalResults":0,"policies":[]}"#)
        let policies = state.sharingPoliciesQuery(resourceType: .application, resourceId: "app-1")
        let other = state.sharingPoliciesQuery(resourceType: .application, resourceId: "app-2")
        await policies.refetch()
        await other.refetch()

        let created = await state.createSharingPolicyMutation(resourceType: .application)
            .mutate((resourceId: "app-1", request: SharingPolicyRequest(childUnits: .all())))

        XCTAssertEqual(created?.id, "pol-1")
        await waitFor { MockURLProtocol.requestCount(forPath: "/applications/app-1/sharing-policies") == 3 }
        // One list read, the create, then the refetch, all on the same path.
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/applications/app-1/sharing-policies"), 3)
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/applications/app-2/sharing-policies"), 1)
    }

    func testRefusalsTheUserCanActOnGetTheirOwnMessages() {
        let i18n = ThunderIDI18n(language: "en-US", storageKey: "project_sharing_state_tests_locale")
        let inUse = ThunderIDError(code: .invalidInput, message: "x", serverError: ServerError(code: "OU-1006"))
        let declarative = ThunderIDError(code: .invalidInput, message: "x", serverError: ServerError(code: "OU-1012"))
        let other = ThunderIDError(code: .invalidInput, message: "x", serverError: ServerError(code: "OU-1001"))
        let keys = AdminHierarchyErrors.organizationUnitDeleteKeys

        XCTAssertEqual(
            i18n.managementErrorMessage(inUse, fallbackKey: "admin.organization_units.details.delete.error", codeKeys: keys),
            "This organization unit still has child units, users, groups or other resources. Remove them first."
        )
        XCTAssertEqual(
            i18n.managementErrorMessage(
                declarative,
                fallbackKey: "admin.organization_units.details.delete.error",
                codeKeys: keys
            ),
            "This organization unit is defined in declarative configuration and cannot be changed."
        )
        XCTAssertEqual(
            i18n.managementErrorMessage(other, fallbackKey: "admin.organization_units.details.delete.error", codeKeys: keys),
            "Could not delete the organization unit. Please try again."
        )
        XCTAssertNil(i18n.managementErrorMessage(nil, fallbackKey: "x", codeKeys: keys))
    }
}
