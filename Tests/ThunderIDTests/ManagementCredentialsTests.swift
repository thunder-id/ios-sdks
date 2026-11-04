// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Credential configurations (OpenID4VCI), presentation definitions (OpenID4VP), dynamic client
/// registration (RFC 7591 / 7592) and a gateway's master.
final class ManagementCredentialsTests: XCTestCase {
    private let base = ManagementTestServer.baseUrl

    private func json(_ request: URLRequest) -> NSDictionary? {
        ManagementTestServer.json(request.httpBody).map { NSDictionary(dictionary: $0) }
    }

    // MARK: - Credential configurations

    func testCredentialConfigurationOperations() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        let api = try client.credentialConfigurations
        let request = CredentialConfigurationRequest(
            handle: "pid",
            ouId: "ou-1",
            vct: "urn:example:pid:1",
            claims: [CredentialClaim(name: "given_name", displayName: "Given name")],
            display: CredentialDisplay(locale: "en"),
            validitySeconds: 60
        )

        server.resource = #"[{"id":"c-1","handle":"pid","ouId":"ou-1","ouHandle":"root","format":"dc+sd-jwt","vct":"v"}]"#
        let list = try await api.list()
        server.resource = #"{"id":"c-1","handle":"pid","ouId":"ou-1","format":"dc+sd-jwt","vct":"v","#
            + #""claims":[{"name":"given_name","displayName":"Given name"}],"validitySeconds":60}"#
        let fetched = try await api.get(id: "c 1")
        _ = try await api.create(request)
        _ = try await api.update(id: "c-1", request)
        try await api.delete(id: "c-1")

        XCTAssertEqual(list.first?.ouHandle, "root")
        XCTAssertEqual(fetched.claims, [CredentialClaim(name: "given_name", displayName: "Given name")])
        XCTAssertEqual(fetched.validitySeconds, 60)
        XCTAssertEqual(server.calls, [
            "GET \(base)/openid4vci/credential-configurations",
            "GET \(base)/openid4vci/credential-configurations/c%201",
            "POST \(base)/openid4vci/credential-configurations",
            "PUT \(base)/openid4vci/credential-configurations/c-1",
            "DELETE \(base)/openid4vci/credential-configurations/c-1"
        ])
        let body: NSDictionary = [
            "handle": "pid", "ouId": "ou-1", "vct": "urn:example:pid:1",
            "claims": [["name": "given_name", "displayName": "Given name"]],
            "display": ["locale": "en"], "validitySeconds": 60
        ]
        XCTAssertEqual(json(server.requests[2]), body)
        XCTAssertEqual(json(server.requests[3]), body)
    }

    // MARK: - Presentation definitions

    func testPresentationDefinitionOperations() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        let api = try client.presentationDefinitions
        let request = PresentationDefinitionRequest(
            handle: "pid",
            ouId: "ou-1",
            vct: "v",
            mandatoryClaims: ["given_name"],
            claimValues: ["country": ["LK"]],
            enforceTrustedIssuer: true
        )

        server.resource = #"[{"id":"p-1","handle":"pid","ouId":"ou-1","vct":"v","format":"dc+sd-jwt"}]"#
        let list = try await api.list()
        server.resource = #"{"id":"p-1","handle":"pid","ouId":"ou-1","vct":"v","format":"dc+sd-jwt","#
            + #""mandatoryClaims":["given_name"],"claimValues":{"country":["LK"]},"enforceTrustedIssuer":true}"#
        let fetched = try await api.get(id: "p-1")
        _ = try await api.create(request)
        _ = try await api.update(id: "p-1", request)
        try await api.delete(id: "p-1")

        XCTAssertEqual(list.first?.format, "dc+sd-jwt")
        XCTAssertEqual(fetched.claimValues, ["country": ["LK"]])
        XCTAssertEqual(fetched.enforceTrustedIssuer, true)
        XCTAssertEqual(server.calls, [
            "GET \(base)/openid4vp/presentation-definitions",
            "GET \(base)/openid4vp/presentation-definitions/p-1",
            "POST \(base)/openid4vp/presentation-definitions",
            "PUT \(base)/openid4vp/presentation-definitions/p-1",
            "DELETE \(base)/openid4vp/presentation-definitions/p-1"
        ])
        let body: NSDictionary = [
            "handle": "pid", "ouId": "ou-1", "vct": "v", "mandatoryClaims": ["given_name"],
            "claimValues": ["country": ["LK"]], "enforceTrustedIssuer": true
        ]
        XCTAssertEqual(json(server.requests[2]), body)
        XCTAssertEqual(json(server.requests[3]), body)
    }

    // MARK: - Client registrations

    func testClientRegistrationOperationsUseSnakeCase() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        let api = try client.clientRegistrations
        var request = ClientRegistrationRequest(
            redirectUris: ["https://app/cb"],
            grantTypes: ["authorization_code"],
            clientName: "App",
            tokenEndpointAuthMethod: "client_secret_basic"
        )
        request.postLogoutRedirectUris = ["https://app/out"]
        request.requirePushedAuthorizationRequests = true

        server.resource = #"{"client_id":"c-1","client_secret":"s3cret","client_secret_expires_at":0,"#
            + #""app_id":"a-1","client_name":"App","redirect_uris":["https://app/cb"],"#
            + #""token_endpoint_auth_method":"client_secret_basic"}"#
        let registered = try await api.register(request)
        server.resource = #"{"client_id":"c-1","client_secret_expires_at":0,"client_name":"App"}"#
        let fetched = try await api.get(clientId: "c/1")
        _ = try await api.update(clientId: "c-1", request)
        try await api.delete(clientId: "c-1")

        XCTAssertEqual(registered.clientId, "c-1")
        XCTAssertEqual(registered.clientSecret, "s3cret")
        XCTAssertEqual(registered.clientSecretExpiresAt, 0)
        XCTAssertEqual(registered.appId, "a-1")
        XCTAssertEqual(registered.redirectUris, ["https://app/cb"])
        XCTAssertEqual(registered.tokenEndpointAuthMethod, "client_secret_basic")
        XCTAssertNil(fetched.clientSecret)
        XCTAssertEqual(server.calls, [
            "POST \(base)/oauth2/dcr/register",
            "GET \(base)/oauth2/dcr/register/c%2F1",
            "PUT \(base)/oauth2/dcr/register/c-1",
            "DELETE \(base)/oauth2/dcr/register/c-1"
        ])
        let metadata: [String: Any] = [
            "redirect_uris": ["https://app/cb"], "grant_types": ["authorization_code"], "client_name": "App",
            "token_endpoint_auth_method": "client_secret_basic", "post_logout_redirect_uris": ["https://app/out"],
            "require_pushed_authorization_requests": true
        ]
        XCTAssertEqual(json(server.requests[0]), NSDictionary(dictionary: metadata))
        var update = metadata
        update["client_id"] = "c-1"
        XCTAssertEqual(json(server.requests[2]), NSDictionary(dictionary: update))
    }

    func testClientRegistrationUpdateSendsTheCurrentSecretOnlyWhenGiven() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        let api = try client.clientRegistrations
        let request = ClientRegistrationRequest(redirectUris: ["https://app/cb"])
        server.resource = #"{"client_id":"c-1","client_secret_expires_at":0}"#

        _ = try await api.update(clientId: "c-1", request, clientSecret: "current")
        _ = try await api.update(clientId: "c-1", request)

        XCTAssertEqual(json(server.requests[0])?["client_secret"] as? String, "current")
        XCTAssertNil(json(server.requests[1])?["client_secret"])
    }

    func testClientRegistrationKeepsItsSecretOutOfPrintedOutput() throws {
        let body = #"{"client_id":"c-1","client_secret":"s3cret","client_secret_expires_at":0,"client_name":"App"}"#
        let registration = try JSONDecoder().decode(ClientRegistration.self, from: Data(body.utf8))
        var dumped = ""
        dump(registration, to: &dumped)

        for output in [registration.description, registration.debugDescription, "\(registration)", dumped] {
            XCTAssertFalse(output.contains("s3cret"), output)
            XCTAssertTrue(output.contains("c-1"), output)
        }
        XCTAssertEqual(registration.clientSecret, "s3cret")
    }

    func testClientRegistrationMapsTheOAuthErrorAndKeepsStatusesDistinct() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        let api = try client.clientRegistrations

        server.resource = #"{"error":"invalid_redirect_uri","error_description":"The redirect URI is invalid"}"#
        server.resourceStatus = 400
        let invalid = await assertThrowsThunderIDError(.invalidInput) {
            _ = try await api.register(ClientRegistrationRequest(redirectUris: ["x"]))
        }
        server.resource = #"{"error":"invalid_token"}"#
        server.resourceStatus = 401
        let unauthorized = await assertThrowsThunderIDError(.authenticationFailed) {
            _ = try await api.get(clientId: "c-1")
        }
        server.resourceStatus = 403
        await assertThrowsThunderIDError(.forbidden) { _ = try await api.get(clientId: "c-1") }
        server.resource = #"{"error":"invalid_client_id","error_description":"No such client"}"#
        server.resourceStatus = 404
        let missing = await assertThrowsThunderIDError(.notFound) { try await api.delete(clientId: "c-1") }

        XCTAssertEqual(invalid?.message, "The redirect URI is invalid")
        XCTAssertEqual(invalid?.serverError, ServerError(
            code: "invalid_redirect_uri",
            message: ServerErrorMessage(defaultValue: "The redirect URI is invalid")
        ))
        XCTAssertEqual(unauthorized?.serverError, ServerError(code: "invalid_token"))
        XCTAssertEqual(missing?.serverError?.code, "invalid_client_id")
        XCTAssertEqual(missing?.serverError?.message?.defaultValue, "No such client")
    }

    func testClientRegistrationsAreNeverLogged() async throws {
        let client = try await ManagementTestServer().makeClient()

        XCTAssertTrue(try client.clientRegistrations.transport.isSensitive)
        XCTAssertFalse(try client.credentialConfigurations.transport.isSensitive)
        XCTAssertFalse(try client.presentationDefinitions.transport.isSensitive)
    }

    // MARK: - Gateway master

    func testGatewayMasterOperations() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        let api = try client.gateways

        server.resource = #"{"gatewayId":"g-1","number":2,"master":"h2","createdBy":{"id":"u","name":"Ada"},"#
            + #""summary":{"deployed":1,"failed":1,"removed":0},"entries":[{"key":"application/a","#
            + #""state":"failed","failure":{"code":"E1","message":"Refused"}}]}"#
        let master = try await api.master(id: "g-1")
        server.resource = #"[{"number":2,"master":"h2"},{"number":1,"master":"h1"}]"#
        let history = try await api.masterHistory(id: "g-1")
        server.resource = #"{"gatewayId":"g-1","key":"application/a","history":[{"master":"h2","number":2,"#
            + #""entry":{"key":"application/a","state":"deployed"}}]}"#
        let resource = try await api.masterResource(id: "g-1", resourceType: "application", resourceId: "a/b c")

        XCTAssertEqual(master.number, 2)
        XCTAssertEqual(master.createdBy?.name, "Ada")
        XCTAssertEqual(master.summary, GatewayMasterSummary(deployed: 1, failed: 1, removed: 0))
        XCTAssertEqual(master.entries?.first?.failure?.code, "E1")
        XCTAssertEqual(history.map(\.master), ["h2", "h1"])
        XCTAssertEqual(resource.history?.first?.entry?.state, "deployed")
        XCTAssertEqual(server.calls, [
            "GET \(base)/gateways/g-1/master",
            "GET \(base)/gateways/g-1/master/history",
            "GET \(base)/gateways/g-1/master/resources/application/a%2Fb%20c"
        ])
    }

    // MARK: - Endpoint overrides

    func testNewCollectionsFollowTheirEndpointOverrides() async throws {
        let server = ManagementTestServer()
        let host = "https://mgmt.example.com"
        let client = try await server.makeClient(endpoints: ThunderIDEndpoints(
            clientRegistrations: "\(host)/dcr/",
            credentialConfigurations: "\(host)/vci",
            presentationDefinitions: "\(host)/vp"
        ))
        let attempts: [() async throws -> Void] = [
            { _ = try await client.credentialConfigurations.get(id: "x") },
            { _ = try await client.presentationDefinitions.get(id: "x") },
            { _ = try await client.clientRegistrations.get(clientId: "x") }
        ]
        for attempt in attempts {
            // The canned body does not decode as each type; only the URL matters here.
            _ = try? await attempt()
        }

        XCTAssertEqual(server.calls, ["GET \(host)/vci/x", "GET \(host)/vp/x", "GET \(host)/dcr/x"])
    }
}
