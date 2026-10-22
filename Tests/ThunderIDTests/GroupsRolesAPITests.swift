// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Records the requests a fetcher receives and answers each with a canned response.
private final class RecordingFetcher: @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    var status = 200
    var body = Data("{}".utf8)

    var fetcher: ThunderIDFetcher {
        { [self] request in
            requests.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (body, response)
        }
    }

    func respond(_ json: String, status: Int = 200) {
        body = Data(json.utf8)
        self.status = status
    }

    var urls: [String?] { requests.map { $0.url?.absoluteString } }

    func jsonBody(at index: Int) throws -> [String: Any] {
        let data = try XCTUnwrap(requests[index].httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

final class GroupsRolesAPITests: XCTestCase {
    private let baseUrl = "https://localhost:8090"
    private let emptyPage = #"{"totalResults":0,"startIndex":1,"count":0,"groups":[],"members":[],"roles":[],"#
        + #""assignments":[],"types":[]}"#
    private let group = #"{"id":"g-1","name":"Admins","ouId":"ou-1"}"#
    private let role = #"{"id":"r-1","name":"Viewer","ouId":"ou-1","permissions":[]}"#

    private func makeClient(
        fetcher: ThunderIDFetcher? = nil,
        endpoints: ThunderIDEndpoints = .init()
    ) async throws -> ThunderIDClient {
        let storage = InMemoryStorageAdapter()
        try TokenStore(storage: storage).save(
            TokenResponse(accessToken: "admin-token", tokenType: "Bearer", expiresIn: 3600)
        )
        let client = ThunderIDClient()
        let config = ThunderIDConfig(
            baseUrl: baseUrl,
            clientId: "client",
            endpoints: endpoints,
            http: .init(fetcher: fetcher)
        )
        _ = try await client.initialize(config: config, storage: storage)
        return client
    }

    // MARK: - Groups

    func testGroupCrudTargetsTheGroupsCollection() async throws {
        let recorder = RecordingFetcher()
        let client = try await makeClient(fetcher: recorder.fetcher)

        recorder.respond(emptyPage)
        _ = try await client.groups.list(limit: 10, offset: 20)
        recorder.respond(group)
        let fetched = try await client.groups.get(id: "g-1")
        _ = try await client.groups.create(CreateGroupRequest(name: "Admins", ouId: "ou-1"))
        _ = try await client.groups.update(id: "g-1", UpdateGroupRequest(name: "Admins", ouId: "ou-1", description: "d"))
        recorder.respond("", status: 204)
        try await client.groups.delete(id: "g-1")

        XCTAssertEqual(fetched.name, "Admins")
        XCTAssertEqual(recorder.requests.map(\.httpMethod), ["GET", "GET", "POST", "PUT", "DELETE"])
        XCTAssertEqual(recorder.urls, [
            "\(baseUrl)/groups?include=display&limit=10&offset=20",
            "\(baseUrl)/groups/g-1?include=display",
            "\(baseUrl)/groups",
            "\(baseUrl)/groups/g-1",
            "\(baseUrl)/groups/g-1"
        ])
        XCTAssertEqual(try recorder.jsonBody(at: 2)["name"] as? String, "Admins")
        XCTAssertNil(try recorder.jsonBody(at: 2)["members"])
        XCTAssertEqual(try recorder.jsonBody(at: 3)["description"] as? String, "d")
        for request in recorder.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        }
    }

    func testGroupMembersAreListedAddedAndRemovedThroughTheirOwnEndpoints() async throws {
        let recorder = RecordingFetcher()
        recorder.respond(
            #"{"totalResults":1,"startIndex":1,"count":1,"members":[{"id":"u-1","type":"user","display":"Alice"}]}"#
        )
        let client = try await makeClient(fetcher: recorder.fetcher)

        let page = try await client.groups.members(id: "g-1", limit: 100)
        recorder.respond(group)
        try await client.groups.addMembers(id: "g-1", [GroupMemberInput(id: "u-1", type: .user)])
        try await client.groups.removeMembers(id: "g-1", [GroupMemberInput(id: "a-1", type: .agent)])

        XCTAssertEqual(page.members.first, GroupMember(id: "u-1", type: .user, display: "Alice"))
        XCTAssertEqual(recorder.requests.map(\.httpMethod), ["GET", "POST", "POST"])
        XCTAssertEqual(recorder.urls, [
            "\(baseUrl)/groups/g-1/members?include=display&limit=100",
            "\(baseUrl)/groups/g-1/members/add",
            "\(baseUrl)/groups/g-1/members/remove"
        ])
        let added = try XCTUnwrap(try recorder.jsonBody(at: 1)["members"] as? [[String: String]])
        XCTAssertEqual(added, [["id": "u-1", "type": "user"]])
        let removed = try XCTUnwrap(try recorder.jsonBody(at: 2)["members"] as? [[String: String]])
        XCTAssertEqual(removed, [["id": "a-1", "type": "agent"]])
    }

    // MARK: - Roles

    func testRoleCrudTargetsTheRolesCollection() async throws {
        let recorder = RecordingFetcher()
        let client = try await makeClient(fetcher: recorder.fetcher)
        let permissions = [RoleResourcePermissions(resourceServerId: "rs-1", permissions: ["system:user:view"])]

        recorder.respond(emptyPage)
        _ = try await client.roles.list(limit: 5)
        recorder.respond(role)
        _ = try await client.roles.get(id: "r-1")
        _ = try await client.roles.create(
            CreateRoleRequest(
                name: "Viewer",
                ouId: "ou-1",
                permissions: permissions,
                assignments: [RoleAssignmentInput(id: "g-1", type: .group)]
            )
        )
        _ = try await client.roles.update(
            id: "r-1",
            UpdateRoleRequest(name: "Viewer", ouId: "ou-1", permissions: permissions)
        )
        recorder.respond("", status: 204)
        try await client.roles.delete(id: "r-1")

        XCTAssertEqual(recorder.requests.map(\.httpMethod), ["GET", "GET", "POST", "PUT", "DELETE"])
        XCTAssertEqual(recorder.urls, [
            "\(baseUrl)/roles?limit=5",
            "\(baseUrl)/roles/r-1",
            "\(baseUrl)/roles",
            "\(baseUrl)/roles/r-1",
            "\(baseUrl)/roles/r-1"
        ])
        let created = try recorder.jsonBody(at: 2)
        XCTAssertEqual(created["assignments"] as? [[String: String]], [["id": "g-1", "type": "group"]])
        let granted = try XCTUnwrap(created["permissions"] as? [[String: Any]])
        XCTAssertEqual(granted.first?["resourceServerId"] as? String, "rs-1")
        XCTAssertEqual(granted.first?["permissions"] as? [String], ["system:user:view"])
    }

    func testRoleAssignmentsAreListedAddedAndRemovedThroughTheirOwnEndpoints() async throws {
        let recorder = RecordingFetcher()
        recorder.respond(
            #"{"totalResults":1,"startIndex":1,"count":1,"assignments":[{"id":"app-1","type":"app"}]}"#
        )
        let client = try await makeClient(fetcher: recorder.fetcher)

        let page = try await client.roles.assignments(id: "r-1", type: .app, limit: 100, offset: 0)
        recorder.respond("", status: 204)
        try await client.roles.addAssignments(id: "r-1", [RoleAssignmentInput(id: "u-1", type: .user)])
        try await client.roles.removeAssignments(id: "r-1", [RoleAssignmentInput(id: "ag-1", type: .agent)])

        XCTAssertEqual(page.assignments, [RoleAssignment(id: "app-1", type: .app)])
        XCTAssertEqual(recorder.requests.map(\.httpMethod), ["GET", "POST", "POST"])
        XCTAssertEqual(recorder.urls, [
            "\(baseUrl)/roles/r-1/assignments?include=display&limit=100&offset=0&type=app",
            "\(baseUrl)/roles/r-1/assignments/add",
            "\(baseUrl)/roles/r-1/assignments/remove"
        ])
        XCTAssertEqual(try recorder.jsonBody(at: 1)["assignments"] as? [[String: String]], [["id": "u-1", "type": "user"]])
        XCTAssertEqual(
            try recorder.jsonBody(at: 2)["assignments"] as? [[String: String]],
            [["id": "ag-1", "type": "agent"]]
        )
    }

    // MARK: - Users and agents

    func testUserAndAgentRelationshipsAndTypes() async throws {
        let recorder = RecordingFetcher()
        recorder.respond(emptyPage)
        let client = try await makeClient(fetcher: recorder.fetcher)

        _ = try await client.users.groups(id: "u-1", limit: 100)
        _ = try await client.users.types(limit: 100)
        _ = try await client.agents.groups(id: "ag-1")
        _ = try await client.agents.types(offset: 10)
        recorder.respond(#"{"totalResults":1,"startIndex":1,"count":1,"roles":["Viewer"]}"#)
        let roles = try await client.agents.roles(id: "ag-1", limit: 5)

        XCTAssertEqual(roles.roles, ["Viewer"])
        XCTAssertTrue(recorder.requests.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertEqual(recorder.urls, [
            "\(baseUrl)/users/u-1/groups?limit=100",
            "\(baseUrl)/user-types?limit=100",
            "\(baseUrl)/agents/ag-1/groups",
            "\(baseUrl)/agent-types?offset=10",
            "\(baseUrl)/agents/ag-1/roles?limit=5"
        ])
    }

    func testEveryCollectionHonoursItsEndpointOverride() async throws {
        let recorder = RecordingFetcher()
        recorder.respond(emptyPage)
        let client = try await makeClient(
            fetcher: recorder.fetcher,
            endpoints: .init(
                agentTypes: "https://rs.example.com/agent-kinds",
                groups: "https://rs.example.com/teams/",
                roles: "https://rs.example.com/roles",
                userTypes: "https://rs.example.com/schemas"
            )
        )

        _ = try await client.groups.members(id: "g 1")
        _ = try await client.roles.list()
        _ = try await client.agents.types()
        _ = try await client.users.types()

        XCTAssertEqual(recorder.urls, [
            "https://rs.example.com/teams/g%201/members?include=display",
            "https://rs.example.com/roles",
            "https://rs.example.com/agent-kinds",
            "https://rs.example.com/schemas"
        ])
    }

    func testPerCallFetcherTakesPrecedenceForRelationships() async throws {
        let clientFetcher = RecordingFetcher()
        let callFetcher = RecordingFetcher()
        callFetcher.respond("", status: 204)
        let client = try await makeClient(fetcher: clientFetcher.fetcher)

        try await client.roles.addAssignments(
            id: "r-1",
            [RoleAssignmentInput(id: "u-1", type: .user)],
            fetcher: callFetcher.fetcher
        )

        XCTAssertEqual(callFetcher.requests.count, 1)
        XCTAssertTrue(clientFetcher.requests.isEmpty)
    }

    func testForbiddenAndNotFoundHaveDistinctCodesOnGroupsAndRoles() async throws {
        let recorder = RecordingFetcher()
        let client = try await makeClient(fetcher: recorder.fetcher)
        let calls: [() async throws -> Void] = [
            { _ = try await client.groups.members(id: "g-1") },
            { try await client.roles.addAssignments(id: "r-1", [RoleAssignmentInput(id: "u-1", type: .user)]) }
        ]

        for call in calls {
            for (status, code) in [(403, ThunderIDErrorCode.forbidden), (404, .notFound)] {
                recorder.respond(#"{"message":"server detail"}"#, status: status)
                do {
                    try await call()
                    XCTFail("Expected \(code)")
                } catch let error as ThunderIDError {
                    XCTAssertEqual(error.code, code)
                }
            }
        }
    }

    func testEmptyIdentifierFailsBeforeAnyRequest() async throws {
        let recorder = RecordingFetcher()
        let client = try await makeClient(fetcher: recorder.fetcher)

        do {
            try await client.groups.addMembers(id: "", [GroupMemberInput(id: "u-1", type: .user)])
            XCTFail("Expected invalidInput")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .invalidInput)
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }
}
