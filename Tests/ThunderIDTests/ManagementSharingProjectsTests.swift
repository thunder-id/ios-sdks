// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Role and flow sharing, flow variables, groups by path, projects, and authorization details types.
final class ManagementSharingProjectsTests: XCTestCase {
    private let base = ManagementTestServer.baseUrl

    private func json(_ request: URLRequest) -> NSDictionary? {
        ManagementTestServer.json(request.httpBody).map { NSDictionary(dictionary: $0) }
    }

    // MARK: - Sharing

    func testSharingPoliciesAndOverlayRulesForRolesAndFlows() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        let policy = #"{"id":"p-1","version":2,"childUnits":{"mode":"selected","units":[{"ouId":"o","reach":"unit"}]}}"#
        let create = SharingPolicyRequest(childUnits: .selected([SharingChildUnit(ouId: "o", reach: "subtree")]))
        let update = SharingPolicyUpdateRequest(version: 2, allUnits: SharingAllUnits(excludedOuIds: ["x"]))

        // A role answers with `isOwnedByOU`, a flow with `owned`.
        let overlays = [
            ("roles", "r 1", #"{"ouId":"o","isOwnedByOU":false,"visible":true,"rules":{"assignments":{"editable":true}}}"#),
            ("flows", "f/1", #"{"ouId":"o","owned":true,"visible":true,"rules":{"variables.mfa":{"editable":false}}}"#)
        ]
        var results: [ResolvedOverlay] = []
        for (collection, id, overlay) in overlays {
            server.resource = #"{"totalResults":1,"policies":[\#(policy)]}"#
            let list = collection == "roles"
                ? try await client.roles.sharingPolicies(id: id, limit: 5, offset: 5)
                : try await client.flows.sharingPolicies(id: id, limit: 5, offset: 5)
            XCTAssertEqual(list.policies.first?.childUnits?.units?.first?.reach, "unit")
            server.resource = policy
            if collection == "roles" {
                _ = try await client.roles.sharingPolicy(id: id, policyId: "p-1")
                _ = try await client.roles.createSharingPolicy(id: id, create)
                _ = try await client.roles.updateSharingPolicy(id: id, policyId: "p-1", update)
                try await client.roles.deleteSharingPolicy(id: id, policyId: "p-1")
                server.resource = overlay
                results.append(try await client.roles.overlayRules(id: id, ouId: "o"))
            } else {
                _ = try await client.flows.sharingPolicy(id: id, policyId: "p-1")
                _ = try await client.flows.createSharingPolicy(id: id, create)
                _ = try await client.flows.updateSharingPolicy(id: id, policyId: "p-1", update)
                try await client.flows.deleteSharingPolicy(id: id, policyId: "p-1")
                server.resource = overlay
                results.append(try await client.flows.overlayRules(id: id, ouId: "o"))
            }
        }

        let expected = [("roles", "r%201"), ("flows", "f%2F1")].flatMap { collection, id in [
            "GET \(base)/\(collection)/\(id)/sharing-policies?limit=5&offset=5",
            "GET \(base)/\(collection)/\(id)/sharing-policies/p-1",
            "POST \(base)/\(collection)/\(id)/sharing-policies",
            "PUT \(base)/\(collection)/\(id)/sharing-policies/p-1",
            "DELETE \(base)/\(collection)/\(id)/sharing-policies/p-1",
            "GET \(base)/\(collection)/\(id)/overlay-rules?ouId=o"
        ] }
        XCTAssertEqual(server.calls, expected)
        XCTAssertEqual(
            json(server.requests[2]),
            ["childUnits": ["mode": "selected", "units": [["ouId": "o", "reach": "subtree"]]]]
        )
        XCTAssertEqual(json(server.requests[3]), ["version": 2, "allUnits": ["excludedOuIds": ["x"]]])
        XCTAssertEqual(results[0].isOwned, false)
        XCTAssertEqual(results[0].rules?["assignments"]?.editable, true)
        XCTAssertEqual(results[1].isOwned, true)
        XCTAssertEqual(results[1].rules?["variables.mfa"]?.editable, false)
    }

    func testOverlayRulesStillReadIsOwned() throws {
        let overlay = try JSONDecoder().decode(ResolvedOverlay.self, from: Data(#"{"isOwned":true}"#.utf8))
        XCTAssertEqual(overlay.isOwned, true)
    }

    func testSharingIdentifiersAreRequired() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        await assertThrowsThunderIDError(.invalidInput) { _ = try await client.roles.sharingPolicies(id: " ") }
        await assertThrowsThunderIDError(.invalidInput) { try await client.flows.deleteSharingPolicy(id: "f", policyId: "") }
        XCTAssertTrue(server.calls.isEmpty)
    }

    // MARK: - Flow variables

    func testFlowVariablesReadAndReplaceAUnitsValues() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        server.resource = #"{"values":{"supportEmail":"help@acme.example","otp":120,"showLink":true}}"#

        let read = try await client.flows.variables(id: "f-1", ouId: "ou 1")
        let written = try await client.flows.updateVariables(
            id: "f-1",
            FlowVariablesRequest(ouId: "ou-1", values: ["supportEmail": AnyCodable("help@acme.example")])
        )

        XCTAssertEqual(server.calls, [
            "GET \(base)/flows/f-1/variables?ouId=ou%201",
            "PUT \(base)/flows/f-1/variables"
        ])
        XCTAssertEqual(json(server.requests[1]), ["ouId": "ou-1", "values": ["supportEmail": "help@acme.example"]])
        XCTAssertEqual(read.values["otp"]?.value as? Int, 120)
        XCTAssertEqual(read.values["showLink"]?.value as? Bool, true)
        XCTAssertEqual(written.values["supportEmail"]?.value as? String, "help@acme.example")
    }

    // MARK: - Groups by path

    func testGroupsByPathEncodeEachSegment() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()

        server.resource = #"{"totalResults":0,"startIndex":1,"count":0,"groups":[]}"#
        _ = try await client.groups.list(path: "/eng/front end/", limit: 10, offset: 0)
        server.resource = #"{"id":"g-1","name":"Web","ouId":"ou-2"}"#
        let group = try await client.groups.create(
            path: "eng/web",
            CreateGroupByPathRequest(name: "Web", members: [GroupMemberInput(id: "u-1", type: .user)])
        )

        XCTAssertEqual(server.calls, [
            "GET \(base)/groups/tree/eng/front%20end?limit=10&offset=0&include=display",
            "POST \(base)/groups/tree/eng/web"
        ])
        XCTAssertEqual(json(server.requests[1]), ["name": "Web", "members": [["id": "u-1", "type": "user"]]])
        XCTAssertEqual(group.ouId, "ou-2")
        await assertThrowsThunderIDError(.invalidInput) { _ = try await client.groups.list(path: "a//b") }
        await assertThrowsThunderIDError(.invalidInput) {
            _ = try await client.groups.create(path: " ", CreateGroupByPathRequest(name: "x"))
        }
        XCTAssertEqual(server.calls.count, 2)
    }

    // MARK: - Projects

    func testProjectOperations() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        let project = #"{"id":"p-1","handle":"shop","displayName":"Shop","createdAt":"2026-10-23T10:15:00Z"}"#

        server.resource = #"{"totalResults":1,"startIndex":1,"count":1,"projects":[\#(project)],"links":[]}"#
        let page = try await client.projects.list(limit: 2, offset: 0)
        server.resource = project
        _ = try await client.projects.get(id: "p-1")
        _ = try await client.projects.create(CreateProjectRequest(handle: "shop", displayName: "Shop"))
        let updated = try await client.projects.update(id: "p-1", UpdateProjectRequest(displayName: "Shop", description: "x"))
        try await client.projects.delete(id: "p-1")

        XCTAssertEqual(server.calls, [
            "GET \(base)/projects?limit=2&offset=0",
            "GET \(base)/projects/p-1",
            "POST \(base)/projects",
            "PUT \(base)/projects/p-1",
            "DELETE \(base)/projects/p-1"
        ])
        XCTAssertEqual(json(server.requests[2]), ["handle": "shop", "displayName": "Shop"])
        XCTAssertEqual(json(server.requests[3]), ["displayName": "Shop", "description": "x"])
        XCTAssertEqual(page.projects.first?.handle, "shop")
        XCTAssertEqual(updated.displayName, "Shop")
    }

    func testProjectErrorsKeepTheirStatus() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        server.resource = #"{"code":"PRJ-1004","message":{"key":"k","defaultValue":"Project not found"}}"#
        server.resourceStatus = 404
        let missing = await assertThrowsThunderIDError(.notFound) { _ = try await client.projects.get(id: "p-9") }
        server.resourceStatus = 403
        await assertThrowsThunderIDError(.forbidden) { try await client.projects.delete(id: "p-9") }
        server.resourceStatus = 401
        await assertThrowsThunderIDError(.authenticationFailed) { _ = try await client.projects.list() }
        XCTAssertEqual(missing?.serverError?.code, "PRJ-1004")
    }

    func testApplicationsAndAgentsTakeAProject() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()

        server.resource = #"{"totalResults":0,"count":0,"applications":[]}"#
        _ = try await client.applications.list(limit: 5, projectId: "p-1")
        server.resource = #"{"totalResults":0,"startIndex":1,"count":0,"agents":[]}"#
        _ = try await client.agents.list(limit: 5, projectId: "p-1")
        server.resource = #"{"id":"app-1","name":"Shop"}"#
        var application = ApplicationRequest(name: "Shop")
        application.projectId = "p-1"
        _ = try await client.applications.create(application)
        server.resource = #"{"id":"ag-1","ouId":"ou-root","type":"default"}"#
        _ = try await client.agents.create(CreateAgentRequest(ouId: nil, type: "default", projectId: "p-1"))

        XCTAssertEqual(server.calls, [
            "GET \(base)/applications?limit=5&projectId=p-1",
            "GET \(base)/agents?limit=5&projectId=p-1&include=display",
            "POST \(base)/applications",
            "POST \(base)/agents"
        ])
        XCTAssertEqual(json(server.requests[2]), ["name": "Shop", "projectId": "p-1"])
        XCTAssertEqual(json(server.requests[3]), ["type": "default", "projectId": "p-1"])
    }

    // MARK: - Authorization details types

    func testAuthorizationDetailTypeOperations() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        let type = #"{"id":"t-1","type":"payment_initiation","name":"Payment","version":1,"#
            + #""schema":{"type":"object"},"reuse":false,"isReadOnly":false,"#
            + #""processor":{"endpoint":"https://p.example","authentication":{"type":"bearer","properties":{"token":"******"}}}}"#
        let request = AuthorizationDetailTypeRequest(
            type: "payment_initiation",
            name: "Payment",
            schema: ["type": AnyCodable("object")],
            processor: AuthorizationDetailProcessor(
                endpoint: "https://p.example",
                authentication: OutboundAuthentication(type: "bearer", properties: ["token": "s"])
            )
        )

        server.resource = #"{"totalResults":1,"types":[\#(type)]}"#
        let page = try await client.authorizationDetailTypes.list(limit: 10)
        server.resource = type
        _ = try await client.authorizationDetailTypes.get(id: "t-1")
        _ = try await client.authorizationDetailTypes.create(request)
        _ = try await client.authorizationDetailTypes.update(id: "t-1", request)
        try await client.authorizationDetailTypes.delete(id: "t-1")

        XCTAssertEqual(server.calls, [
            "GET \(base)/authorization-detail-types?limit=10",
            "GET \(base)/authorization-detail-types/t-1",
            "POST \(base)/authorization-detail-types",
            "PUT \(base)/authorization-detail-types/t-1",
            "DELETE \(base)/authorization-detail-types/t-1"
        ])
        XCTAssertEqual(json(server.requests[2]), [
            "type": "payment_initiation",
            "name": "Payment",
            "schema": ["type": "object"],
            "processor": ["endpoint": "https://p.example", "authentication": ["type": "bearer", "properties": ["token": "s"]]]
        ])
        XCTAssertEqual(page.types.first?.processor?.authentication?.properties?["token"], "******")
        XCTAssertTrue(try client.authorizationDetailTypes.transport.isSensitive)
        XCTAssertFalse(try client.projects.transport.isSensitive)
    }

    func testSupportedAuthorizationDetailsTypesArePublic() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        let type = #"{"type":"https://acme.example/pay","name":"Pay","version":3,"schema":{"type":"object"},"#
            + #""modifications":[{"field":"amount","modification":"decrease"}]}"#

        server.resource = #"{"types":[\#(type)]}"#
        let all = try await client.getSupportedAuthorizationDetailsTypes()
        server.resource = type
        let one = try await client.getSupportedAuthorizationDetailsType("https://acme.example/pay")

        XCTAssertEqual(server.calls, [
            "GET \(base)/oauth2/authorization-details-types",
            "GET \(base)/oauth2/authorization-details-types/https:%2F%2Facme.example%2Fpay"
        ])
        XCTAssertTrue(server.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        XCTAssertEqual(all.types.first?.modifications?.first?.modification, "decrease")
        XCTAssertEqual(one.version, 3)

        server.resource = #"{"code":"RAR-1029","message":{"key":"k","defaultValue":"Authorization details type not found"}}"#
        server.resourceStatus = 404
        await assertThrowsThunderIDError(.notFound) { _ = try await client.getSupportedAuthorizationDetailsType("x") }
    }

    // MARK: - Endpoint overrides

    func testProjectsAndAuthorizationDetailTypesFollowTheirEndpointOverrides() async throws {
        let server = ManagementTestServer()
        let host = "https://cp.example.com"
        let client = try await server.makeClient(endpoints: ThunderIDEndpoints(
            authorizationDetailTypes: "\(host)/adt/",
            projects: "\(host)/prj"
        ))
        server.resource = #"{"projects":[]}"#
        _ = try await client.projects.list()
        server.resource = #"{"types":[]}"#
        _ = try await client.authorizationDetailTypes.list()

        XCTAssertEqual(server.calls, ["GET \(host)/prj", "GET \(host)/adt"])
    }
}
