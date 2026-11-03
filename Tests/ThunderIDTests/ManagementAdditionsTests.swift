// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class ManagementAdditionsTests: XCTestCase {
    private let baseUrl = ManagementTestServer.baseUrl
    private let userType = #"{"id":"t-1","handle":"staff","displayName":"Staff","ouId":"ou-1","#
        + #""allowSelfRegistration":false,"schema":{"email":{"type":"email","required":true}}}"#
    private let agentType = #"{"id":"a-1","handle":"bot","displayName":"Bot","ouId":"ou-1","schema":{}}"#

    // MARK: - New operations

    func testUserUsagesAndCredentials() async throws {
        let server = ManagementTestServer()
        server.resource = #"{"count":1,"totalResults":null,"summary":{"agent":1},"#
            + #""usages":[{"id":"ag-1","displayName":"Bot","resourceType":"agent","behaviorOnDelete":"fallback"}]}"#
        let client = try await server.makeClient()

        let usages = try await client.users.usages(id: "u-1")
        try await client.users.updateCredentials(
            id: "u-1",
            UpdateUserCredentialsRequest(credentials: ["password": "p"])
        )

        XCTAssertEqual(usages.usages.first?.behaviorOnDelete, "fallback")
        XCTAssertNil(usages.totalResults)
        XCTAssertEqual(usages.summary, ["agent": 1])
        XCTAssertEqual(server.calls, [
            "GET \(baseUrl)/users/u-1/usages",
            "POST \(baseUrl)/users/u-1/update-credentials"
        ])
        XCTAssertNil(server.requests[0].httpBody)
        XCTAssertEqual(server.body(of: "POST")?["credentials"] as? [String: String], ["password": "p"])
    }

    func testUserTypeCrud() async throws {
        let server = ManagementTestServer()
        server.resource = #"{"totalResults":0,"startIndex":1,"count":0,"types":[]}"#
        let client = try await server.makeClient()

        _ = try await client.userTypes.list(limit: 10)
        server.resource = userType
        let fetched = try await client.userTypes.get(id: "t-1")
        _ = try await client.userTypes.create(
            CreateUserTypeRequest(handle: "staff", displayName: "Staff", ouId: "ou-1", schema: [:])
        )
        _ = try await client.userTypes.update(
            id: "t-1",
            UpdateUserTypeRequest(displayName: "Staff", ouId: "ou-1", schema: [:])
        )
        try await client.userTypes.delete(id: "t-1")

        XCTAssertEqual(fetched.schema["email"], PropertyDefinition(type: "email", required: true))
        XCTAssertEqual(server.calls, [
            "GET \(baseUrl)/user-types?include=display&limit=10",
            "GET \(baseUrl)/user-types/t-1?include=display",
            "POST \(baseUrl)/user-types",
            "PUT \(baseUrl)/user-types/t-1",
            "DELETE \(baseUrl)/user-types/t-1"
        ])
        XCTAssertEqual(
            NSDictionary(dictionary: try XCTUnwrap(ManagementTestServer.json(server.requests[2].httpBody))),
            NSDictionary(dictionary: ["displayName": "Staff", "handle": "staff", "ouId": "ou-1", "schema": [:]])
        )
        XCTAssertEqual(
            NSDictionary(dictionary: try XCTUnwrap(ManagementTestServer.json(server.requests[3].httpBody))),
            NSDictionary(dictionary: ["displayName": "Staff", "ouId": "ou-1", "schema": [:]])
        )
    }

    func testAgentTypeReadAndUpdate() async throws {
        let server = ManagementTestServer()
        server.resource = agentType
        let client = try await server.makeClient()

        _ = try await client.agentTypes.get(id: "a-1")
        _ = try await client.agentTypes.update(
            id: "a-1",
            UpdateAgentTypeRequest(displayName: "Bot", ouId: "ou-1", schema: [:])
        )
        server.resource = #"{"totalResults":0,"startIndex":1,"count":0,"types":[]}"#
        _ = try await client.agentTypes.list(offset: 5)

        XCTAssertEqual(server.calls, [
            "GET \(baseUrl)/agent-types/a-1?include=display",
            "PUT \(baseUrl)/agent-types/a-1",
            "GET \(baseUrl)/agent-types?include=display&offset=5"
        ])
        XCTAssertEqual(
            NSDictionary(dictionary: try XCTUnwrap(server.body(of: "PUT"))),
            NSDictionary(dictionary: ["displayName": "Bot", "ouId": "ou-1", "schema": [:]])
        )
    }

    func testPropertyDefinitionsKeepTheirNestedShape() throws {
        let schema = try JSONDecoder().decode(EntityTypeSchema.self, from: Data("""
        {"tags": {"type": "array", "items": {"type": "string", "enum": ["a", "b"]}},
         "address": {"type": "object", "properties": {"city": {"type": "string", "regex": "^[A-Z]"}}},
         "password": {"type": "string", "credential": true}}
        """.utf8))

        XCTAssertEqual(schema["tags"]?.items?.enumValues, ["a", "b"])
        XCTAssertEqual(schema["address"]?.properties?["city"]?.regex, "^[A-Z]")
        XCTAssertEqual(schema["password"]?.credential, true)
        let encoded = try XCTUnwrap(ManagementTestServer.json(try JSONEncoder().encode(schema)))
        XCTAssertEqual((encoded["tags"] as? [String: Any])?["items"] as? NSDictionary, ["type": "string", "enum": ["a", "b"]])
    }

    func testPreviewCimdDocumentPostsToTheServer() async throws {
        let server = ManagementTestServer()
        server.resource = #"{"name":"Client","inboundAuthConfig":[{"type":"oauth2","#
            + #""config":{"grantTypes":["authorization_code"],"responseTypes":["code"]}}]}"#
        let client = try await server.makeClient()

        let preview = try await client.applications.previewCimdDocument(clientId: "https://client.example/cimd.json")

        XCTAssertEqual(preview.name, "Client")
        XCTAssertEqual(server.calls, ["POST \(baseUrl)/cimd/preview"])
        XCTAssertEqual(server.body(of: "POST")?["clientId"] as? String, "https://client.example/cimd.json")
    }

    // MARK: - Secret regeneration

    private let application = #"{"id":"app-1","createdAt":"yesterday","name":"Shop","inboundAuthConfig":[{"#
        + #""type":"oauth2","config":{"clientId":"client","clientSecret":"old","grantTypes":["client_credentials"],"#
        + #""responseTypes":[]}}]}"#

    func testRegenerateClientSecretSavesANewSecretOnTheApplication() async throws {
        let server = ManagementTestServer()
        server.resource = application
        let client = try await server.makeClient()

        let result = try await client.applications.regenerateClientSecret(id: "app-1")

        XCTAssertNotNil(result.application)
        XCTAssertNotNil(result.clientSecret.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression))
        XCTAssertEqual(server.calls, ["GET \(baseUrl)/applications/app-1", "PUT \(baseUrl)/applications/app-1"])
        let put = try XCTUnwrap(server.body(of: "PUT"))
        XCTAssertNil(put["id"])
        XCTAssertNil(put["createdAt"])
        let inbound = try XCTUnwrap((put["inboundAuthConfig"] as? [[String: Any]])?.first)
        let config = try XCTUnwrap(inbound["config"] as? [String: Any])
        XCTAssertEqual(config["clientSecret"] as? String, result.clientSecret)
        XCTAssertEqual(config["clientId"] as? String, "client")
    }

    func testRegeneratedSecretsDiffer() async throws {
        let first = try SecretGenerator.generate()
        let second = try SecretGenerator.generate()

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.count, 43)
        XCTAssertFalse(first.contains("="))
    }

    func testRegenerateClientSecretRefusesAnApplicationWithoutAnOAuthClient() async throws {
        let server = ManagementTestServer()
        server.resource = #"{"id":"app-1","name":"Shop","inboundAuthConfig":[]}"#
        let client = try await server.makeClient()

        await assertThrowsThunderIDError(.invalidInput) {
            _ = try await client.applications.regenerateClientSecret(id: "app-1")
        }
        XCTAssertFalse(server.calls.contains { $0.hasPrefix("PUT") })
    }

    func testRegenerateFlowSecretSavesANewSecretOnTheApplication() async throws {
        let server = ManagementTestServer()
        server.resource = application
        let client = try await server.makeClient()

        let result = try await client.applications.regenerateFlowSecret(id: "app-1")

        let put = try XCTUnwrap(server.body(of: "PUT"))
        XCTAssertEqual(put["flowSecret"] as? String, result.flowSecret)
        XCTAssertEqual(put["name"] as? String, "Shop")
        XCTAssertNil(put["id"])
    }

    func testRegenerateAgentSecretLeavesServerAndDisplayFieldsOut() async throws {
        let server = ManagementTestServer()
        server.resource = #"{"id":"a-1","clientId":"client","display":"Bot","ouId":"ou-1","ouHandle":"default","#
            + #""type":"bot","inboundAuthConfig":[{"type":"oauth2","config":{"grantTypes":["client_credentials"],"#
            + #""responseTypes":[]}}]}"#
        let client = try await server.makeClient()

        let result = try await client.agents.regenerateSecret(id: "a-1")

        XCTAssertEqual(server.calls, ["GET \(baseUrl)/agents/a-1?include=display", "PUT \(baseUrl)/agents/a-1"])
        let put = try XCTUnwrap(server.body(of: "PUT"))
        XCTAssertEqual(Set(put.keys), ["delegated", "inboundAuthConfig", "ouId", "type"])
        XCTAssertEqual(put["delegated"] as? Bool, false)
        let inbound = try XCTUnwrap((put["inboundAuthConfig"] as? [[String: Any]])?.first)
        XCTAssertEqual((inbound["config"] as? [String: Any])?["clientSecret"] as? String, result.clientSecret)
    }

    func testRegenerateAgentSecretKeepsADelegatedAgentDelegated() async throws {
        let server = ManagementTestServer()
        server.resource = #"{"id":"a-1","attributes":{"name":"Assistant"},"ouId":"ou-1","type":"bot","#
            + #""inboundAuthConfig":[{"#
            + #""type":"oauth2","config":{"grantTypes":["authorization_code","refresh_token"],"responseTypes":[]}}]}"#
        let client = try await server.makeClient()

        _ = try await client.agents.regenerateSecret(id: "a-1")

        XCTAssertEqual(server.body(of: "PUT")?["delegated"] as? Bool, true)
    }

    func testDelegationFollowsTheGrantTypes() {
        func agent(_ grants: [String]) -> [AgentInboundAuthConfig] {
            [AgentInboundAuthConfig(config: OAuth2Config(grantTypes: grants, responseTypes: []))]
        }
        XCTAssertTrue(DelegationGrantTypes.isDelegated(agent(["urn:openid:params:grant-type:ciba"])))
        XCTAssertTrue(DelegationGrantTypes.isDelegated(agent(["urn:ietf:params:oauth:grant-type:token-exchange"])))
        XCTAssertFalse(DelegationGrantTypes.isDelegated(agent(["client_credentials"])))
        XCTAssertFalse(DelegationGrantTypes.isDelegated(nil))
    }

    func testRegenerateAgentSecretRefusesAnAgentWithoutAnOAuthClient() async throws {
        let server = ManagementTestServer()
        server.resource = #"{"id":"a-1","name":"Bot","ouId":"ou-1","type":"bot"}"#
        let client = try await server.makeClient()

        await assertThrowsThunderIDError(.invalidInput) {
            _ = try await client.agents.regenerateSecret(id: "a-1")
        }
        XCTAssertFalse(server.calls.contains { $0.hasPrefix("PUT") })
    }
}
