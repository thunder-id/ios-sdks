// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Covers the signed-in user's own agents (`/users/me/agents`): the requests, the models they decode, and the
/// helpers that decide which actions an owner and an organization can take.
final class PersonalAgentsTests: OAuthTestCase {
    private let agent = #"""
    {"id":"a-1","ouId":"ou-1","type":"assistant","kind":"personal-assistant","clientId":"c-1",
     "owner":{"id":"u-1","idType":"uuid","isLocal":true},
     "attributes":{"name":"Spending assistant","model":"gpt","limits":{"daily":5}},
     "inboundAuthConfig":[{"type":"oauth2","config":{"grantTypes":["urn:openid:params:grant-type:ciba"]}}],
     "status":{"value":"SUSPENDED","details":{"reason":"OWNER_SUSPENSION","appliedBy":["owner","organization"]}},
     "isReadOnly":false}
    """#

    private func signIn() async throws {
        try await makeClient()
        try storeSession(["sub": "u-1"])
    }

    private func decodeAgent(_ json: String) throws -> Agent {
        try JSONDecoder().decode(Agent.self, from: Data(json.utf8))
    }

    // MARK: - Requests

    func testListsTheUsersAgentsWithTheirOwnToken() async throws {
        try await signIn()
        StubBackend.reply(
            "/users/me/agents",
            #"{"totalResults":3,"startIndex":11,"count":1,"agents":[{"id":"a-1","ouId":"ou-1","type":"assistant","# +
                #""kind":"personal-assistant","status":{"value":"ACTIVE"}}]}"#
        )

        let page = try await client.getMeAgents(kind: .personal, limit: 1, offset: 10)

        let request = try XCTUnwrap(StubBackend.requests(to: "/users/me/agents").first)
        XCTAssertEqual(request.request.httpMethod, "GET")
        XCTAssertEqual(request.request.url?.query, "kind=personal-assistant&limit=1&offset=10")
        XCTAssertEqual(request.header("Authorization"), "Bearer \(store.accessToken()!)")
        XCTAssertEqual(page.totalResults, 3)
        XCTAssertEqual(page.agents.first?.kind, .personal)
        XCTAssertEqual(page.agents.first?.isPersonal, true)
        XCTAssertEqual(page.agents.first?.status?.value, .active)
    }

    func testListsWithoutOptionsSendsNoQuery() async throws {
        try await signIn()
        StubBackend.reply("/users/me/agents", #"{"totalResults":0,"startIndex":1,"count":0,"agents":[]}"#)

        _ = try await client.getMeAgents()

        XCTAssertNil(StubBackend.requests(to: "/users/me/agents").first?.request.url?.query)
    }

    func testReadsOneAgentWithItsDisplayNameAndEncodesItsId() async throws {
        try await signIn()
        StubBackend.reply("/users/me/agents/a 1", agent)

        let read = try await client.getMeAgent(id: "a 1")

        let request = try XCTUnwrap(StubBackend.requests(to: "/users/me/agents/a 1").first)
        XCTAssertTrue(request.request.url?.absoluteString.hasSuffix("/users/me/agents/a%201?include=display") == true)
        XCTAssertEqual(read.owner, AgentOwner(id: "u-1", idType: .uuid, isLocal: true))
        XCTAssertEqual(read.status?.details?.reason, .ownerSuspension)
        XCTAssertEqual(read.status?.suspendedBy, [.owner, .organization])
        XCTAssertEqual(read.oauthConfig?.grantTypes, [PersonalAgentGrantTypes.ciba])
        XCTAssertEqual(read.oauthConfig?.responseTypes, [], "An empty list the server leaves out reads as empty")
    }

    func testUpdatesTheEditablePartAndAlwaysSendsTheLists() async throws {
        try await signIn()
        StubBackend.reply("/users/me/agents/a-1", agent)
        let request = UpdateMeAgentRequest(
            attributes: ["name": AnyCodable("Renamed")],
            description: "",
            grantTypes: [],
            redirectUris: []
        )

        _ = try await client.updateMeAgent(id: "a-1", request)

        let sent = try XCTUnwrap(StubBackend.requests(to: "/users/me/agents/a-1").first)
        XCTAssertEqual(sent.request.httpMethod, "PUT")
        let body = try XCTUnwrap(sent.json)
        XCTAssertEqual((body["attributes"] as? [String: Any])?["name"] as? String, "Renamed")
        XCTAssertEqual(body["description"] as? String, "")
        XCTAssertEqual(body["grantTypes"] as? [String], [])
        XCTAssertEqual(body["redirectUris"] as? [String], [])
    }

    func testDeletesSuspendsAndUnsuspendsOneAgent() async throws {
        try await signIn()
        StubBackend.reply("/users/me/agents/a-1", status: 204, "")
        StubBackend.reply("/users/me/agents/a-1/suspend", status: 204, "")
        StubBackend.reply("/users/me/agents/a-1/unsuspend", status: 204, "")

        try await client.deleteMeAgent(id: "a-1")
        try await client.suspendMeAgent(id: "a-1")
        try await client.unsuspendMeAgent(id: "a-1")

        XCTAssertEqual(
            StubBackend.requests.map { "\($0.request.httpMethod ?? "") \($0.path)" },
            ["DELETE /users/me/agents/a-1", "POST /users/me/agents/a-1/suspend", "POST /users/me/agents/a-1/unsuspend"]
        )
    }

    func testSuspendsAllAgentsAndReportsHowMany() async throws {
        try await signIn()
        StubBackend.reply("/users/me/agents/suspend", #"{"suspendedCount":2}"#)

        let result = try await client.suspendAllMeAgents()

        XCTAssertEqual(result.suspendedCount, 2)
        XCTAssertEqual(StubBackend.requests(to: "/users/me/agents/suspend").first?.request.httpMethod, "POST")
    }

    func testRefusesABlankIdWithoutCallingTheServer() async throws {
        try await signIn()

        await assertThrows(.invalidInput) { try await self.client.suspendMeAgent(id: " ") }
        await assertThrows(.invalidInput) { try await self.client.getMeAgent(id: "\n") }
        await assertThrows(.invalidInput) { try await self.client.deleteMeAgent(id: " \t\n") }

        XCTAssertTrue(StubBackend.requests.isEmpty)
    }

    func testMapsAMissingPermissionAndAMissingAgentToDistinctCodes() async throws {
        try await signIn()
        StubBackend.reply("/users/me/agents/a-1", status: 403, "{}")
        await assertThrows(.forbidden) { _ = try await self.client.getMeAgent(id: "a-1") }

        StubBackend.reset()
        StubBackend.reply("/users/me/agents/a-1", status: 404, #"{"code":"AGT-1003","message":"Agent not found"}"#)
        await assertThrows(.notFound) { _ = try await self.client.getMeAgent(id: "a-1") }
    }

    func testFailsBeforeInitialization() async {
        await assertThrows(.sdkNotInitialized) { _ = try await ThunderIDClient().getMeAgents() }
    }

    // MARK: - Owner suspension

    func testOffersTheOwnerToLiftOnlyTheirOwnSuspension() {
        let held = { (parties: [SuspensionAppliedBy]) in
            AccessStatus(
                value: .suspended,
                details: AccessStatusDetails(
                    reason: nil,
                    since: nil,
                    operatorNote: nil,
                    appliedBy: parties,
                    lockedMethods: nil
                )
            )
        }

        XCTAssertEqual(MeAgentSuspensionAction.available(for: nil), .suspend)
        XCTAssertEqual(MeAgentSuspensionAction.available(for: AccessStatus(value: .active)), .suspend)
        XCTAssertEqual(MeAgentSuspensionAction.available(for: held([.owner])), .unsuspend)
        XCTAssertEqual(MeAgentSuspensionAction.available(for: held([.organization, .owner])), .unsuspend)
        XCTAssertEqual(MeAgentSuspensionAction.available(for: held([.organization])), .suspend)
        XCTAssertEqual(MeAgentSuspensionAction.available(for: held([.cascade])), .suspend)
    }

    // MARK: - Organization lifecycle

    func testTheOrganizationLiftsOnlyItsOwnSuspension() {
        let flows: [AdministrationFlowConfigKey: String] = [.agentSuspend: "suspend", .agentUnsuspend: "unsuspend"]
        let available = { (parties: [SuspensionAppliedBy]?) in
            AccountLifecycleAction.available(for: .agent, status: .suspended, configuredFlows: flows, appliedBy: parties)
        }

        XCTAssertEqual(available(nil), [.unsuspend], "A server that reports no party holds its own")
        XCTAssertEqual(available([]), [.unsuspend])
        XCTAssertEqual(available([.organization, .owner]), [.unsuspend])
        XCTAssertEqual(available([.owner]), [.suspend], "Only the owner holds it, so the organization can add its own")
        XCTAssertEqual(available([.cascade]), [.suspend])
        XCTAssertEqual(
            AccountLifecycleAction.available(for: .agent, status: .suspended, configuredFlows: [:], appliedBy: [.owner]),
            [],
            "An action whose flow is not configured is never offered"
        )
    }

    // MARK: - Edit form

    func testTheFormStartsFromTheAgentAndKeepsWhatItDoesNotEdit() throws {
        let read = try decodeAgent(agent)
        var values = PersonalAgentFormValues(agent: read)

        XCTAssertEqual(values.name, "Spending assistant")
        XCTAssertEqual(values.attributes, ["model": "gpt"], "Only the text attributes other than the name")
        XCTAssertEqual(values.grantTypes, [PersonalAgentGrantTypes.ciba])

        values.name = "  Renamed  "
        values.attributes["model"] = "claude"
        values.description = " Pays bills "
        values.redirectUris = "https://a.example/cb?pair=a,b\n\n https://b.example/cb \nhttps://c.example/cb"
        let request = values.updateRequest(for: read)

        XCTAssertEqual(request.attributes["name"]?.value as? String, "Renamed")
        XCTAssertEqual(request.attributes["model"]?.value as? String, "claude")
        XCTAssertEqual((request.attributes["limits"]?.value as? [String: AnyCodable])?["daily"]?.value as? Int, 5)
        XCTAssertEqual(request.description, "Pays bills")
        XCTAssertEqual(request.redirectUris, ["https://a.example/cb?pair=a,b", "https://b.example/cb", "https://c.example/cb"])
    }

    func testTheFormKeepsARedirectUriThatHoldsAComma() throws {
        let read = try decodeAgent(#"{"id":"a-3","ouId":"ou-1","type":"bot","inboundAuthConfig":[{"type":"oauth2","# +
            #""config":{"grantTypes":["authorization_code"],"# +
            #""redirectUris":["https://a.example/cb?pair=a,b","https://b.example/cb"]}}]}"#)

        let request = PersonalAgentFormValues(agent: read).updateRequest(for: read)

        XCTAssertEqual(request.redirectUris, ["https://a.example/cb?pair=a,b", "https://b.example/cb"])
    }

    func testTheFormNeedsANameAndARedirectUriForTheCodeGrant() throws {
        var values = PersonalAgentFormValues(agent: try decodeAgent(agent))
        XCTAssertTrue(values.isValid)

        values.name = "   "
        XCTAssertFalse(values.isValid)

        values.name = "Assistant"
        values.grantTypes.append(PersonalAgentGrantTypes.authorizationCode)
        XCTAssertFalse(values.isValid)

        values.redirectUris = " \n "
        XCTAssertFalse(values.isValid)

        values.redirectUris = "https://a.example/cb"
        XCTAssertTrue(values.isValid)
    }

    func testAnOrdinaryAgentIsNotPersonalAndReadsAnOwnerWithoutLocality() throws {
        let ordinary = try decodeAgent(#"{"id":"a-2","ouId":"ou-1","type":"bot","owner":{"id":"jo@example.com","# +
            #""idType":"email","isLocal":false}}"#)

        XCTAssertFalse(ordinary.isPersonal)
        XCTAssertNil(ordinary.kind)
        XCTAssertEqual(ordinary.owner?.idType, .email)
        XCTAssertEqual(ordinary.owner?.isLocal, false)
    }
}
