// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// The telemetry the client wires up: the endpoint check, the token rules, the request observer and the
/// sign-in reported once per session.
final class ClientTelemetryTests: XCTestCase {
    let base = "https://id.example.com"
    var telemetryPathOverride: String?
    var telemetryPath: String { telemetryPathOverride ?? "/telemetry" }
    var storage: InMemoryStorageAdapter!

    override func setUp() {
        super.setUp()
        StubBackend.reset()
        storage = InMemoryStorageAdapter()
    }

    override func tearDown() {
        StubBackend.reset()
        super.tearDown()
    }

    private func makeClient(
        endpoint: String? = nil,
        token: TelemetryToken = .app,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ThunderIDClient {
        let config = ThunderIDConfig(
            baseUrl: base,
            clientId: "client-1",
            tokenValidation: .init(validate: false),
            http: .init(fetcher: fetcher),
            telemetry: TelemetryConfig(
                endpoint: endpoint ?? "\(base)\(telemetryPath)",
                format: .json,
                token: token
            )
        )
        let client = ThunderIDClient()
        _ = try await client.initialize(config: config, storage: storage, session: StubBackend.makeSession())
        return client
    }

    private func signIn(_ claims: [String: Any] = ["sub": "u1", "ouId": "ou1"]) throws {
        try TokenStore(storage: storage).save(TokenResponse(
            accessToken: OAuthTestCase.jwt(claims),
            tokenType: "Bearer",
            expiresIn: 3600
        ))
    }

    /// The events sent to the telemetry endpoint, by name.
    private var sentNames: [String] {
        StubBackend.requests(to: telemetryPath).flatMap { recorded -> [String] in
            let events = recorded.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }
            return (events ?? []).compactMap { $0["name"] as? String }
        }
    }

    // MARK: - Endpoint

    func testStaysOffWithoutAnHttpsEndpointAndNeverFailsInitialization() async throws {
        for endpoint in ["http://collector.example.com/v1/logs", "collector", "ftp://collector.example.com", " "] {
            let client = try await makeClient(endpoint: endpoint)
            XCTAssertNil(client.telemetryClient, endpoint)
            client.track("item.open")
            client.trackPageView("applications")
            client.trackLink(URL(string: "https://docs.example.com")!)
        }
        let plain = ThunderIDClient()
        _ = try await plain.initialize(
            config: ThunderIDConfig(baseUrl: base, clientId: "c"),
            storage: storage,
            session: StubBackend.makeSession()
        )
        XCTAssertNil(plain.telemetryClient)
        XCTAssertTrue(StubBackend.requests.isEmpty)
    }

    // MARK: - Token rules

    private func dependencies(backend: Bool = false) -> ClientTelemetryDependencies {
        ClientTelemetryDependencies(
            apiBases: [base],
            baseUrl: base,
            backend: backend,
            vendor: "acme",
            claims: { nil },
            accessToken: { "app-token" }
        )
    }

    private func token(_ rule: TelemetryToken, endpoint: String, backend: Bool = false) async -> String? {
        let config = TelemetryConfig(endpoint: endpoint, token: rule)
        let tokenRule = ClientTelemetry.tokenRule(
            config: config,
            endpoint: URL(string: endpoint)!,
            dependencies: dependencies(backend: backend)
        )
        return await tokenRule()
    }

    func testSendsTheAppTokenOnlyToTheOriginOfBaseUrl() async {
        let sameOrigin = await token(.app, endpoint: "\(base)/telemetry")
        XCTAssertEqual(sameOrigin, "app-token")
        let otherOrigin = await token(.app, endpoint: "https://collector.example.com/v1/logs")
        XCTAssertNil(otherOrigin)
        let otherPort = await token(.app, endpoint: "https://id.example.com:8443/telemetry")
        XCTAssertNil(otherPort)
        let backend = await token(.app, endpoint: "\(base)/telemetry", backend: true)
        XCTAssertNil(backend)
    }

    func testSendsOnlyAConfiguredTokenAndNoneWhenDisabled() async {
        let fixed = await token(.fixed("collector-token"), endpoint: "\(base)/telemetry")
        XCTAssertEqual(fixed, "collector-token")
        let fixedElsewhere = await token(.fixed("collector-token"), endpoint: "https://collector.example.com")
        XCTAssertEqual(fixedElsewhere, "collector-token")
        let disabled = await token(.disabled, endpoint: "\(base)/telemetry")
        XCTAssertNil(disabled)
    }

    func testAttachesTheRuleTokenToTheRequest() async throws {
        try signIn()
        StubBackend.reply(telemetryPath, "{}")
        let client = try await makeClient()
        client.track("item.open")
        await client.telemetryClient?.telemetry.flush()
        let sent = try XCTUnwrap(StubBackend.requests(to: telemetryPath).first)
        XCTAssertEqual(sent.header("Authorization"), "Bearer \(TokenStore(storage: storage).accessToken()!)")

        StubBackend.reset()
        StubBackend.reply(telemetryPath, "{}")
        let fixed = try await makeClient(token: .fixed("collector-token"))
        fixed.track("item.open")
        await fixed.telemetryClient?.telemetry.flush()
        XCTAssertEqual(StubBackend.requests(to: telemetryPath).first?.header("Authorization"), "Bearer collector-token")

        StubBackend.reset()
        StubBackend.reply(telemetryPath, "{}")
        let disabled = try await makeClient(token: .disabled)
        disabled.track("item.open")
        await disabled.telemetryClient?.telemetry.flush()
        XCTAssertNil(StubBackend.requests(to: telemetryPath).first?.header("Authorization"))
    }

    // MARK: - Request observer

    func testNeverReportsItsOwnRequestsAsApiEvents() async throws {
        try signIn()
        telemetryPathOverride = "/events"
        StubBackend.reply("/events", "{}")
        let client = try await makeClient(endpoint: "\(base)/events")
        client.track("item.open")
        await client.telemetryClient?.telemetry.flush()
        client.track("item.close")
        await client.telemetryClient?.telemetry.flush()
        try await Task.sleep(nanoseconds: 50_000_000)
        await client.telemetryClient?.telemetry.flush()
        XCTAssertEqual(sentNames, ["item.open", "item.close"])
    }

    func testReportsManagementWritesThroughTheTransportButNotReads() async throws {
        try signIn()
        StubBackend.reply(telemetryPath, "{}")
        let server = ManagementTestServer()
        let client = try await makeClient(fetcher: server.fetcher)
        try await client.applications.delete(id: "a1")
        server.resourceStatus = 404
        server.resource = #"{"code":"APP-1003","message":"Application Ada not found"}"#
        await assertThrowsThunderIDError(.notFound) { try await client.applications.delete(id: "a2") }
        server.resourceStatus = 200
        server.resource = #"{"applications":[],"totalResults":0}"#
        _ = try? await client.applications.list()
        await client.telemetryClient?.telemetry.flush()

        XCTAssertEqual(sentNames, ["application.delete", "application.delete-failed"])
        let body = String(data: StubBackend.requests(to: telemetryPath)[0].body ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("APP-1003"))
        XCTAssertTrue(body.contains("/applications/{id}"))
        XCTAssertFalse(body.contains("Ada"))
    }

    func testReportsRequestsSentWithHttpRequest() async throws {
        try signIn()
        StubBackend.reply(telemetryPath, "{}")
        StubBackend.reply("/groups", status: 201, "{}")
        let client = try await makeClient()
        var request = URLRequest(url: URL(string: "\(base)/groups")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"name":"Admins"}"#.utf8)
        _ = try await client.httpRequest(request)
        await client.telemetryClient?.telemetry.flush()
        XCTAssertEqual(sentNames, ["group.create"])
    }

    func testNeverReportsTheSdksOwnTokenAndFlowRequests() async throws {
        try signIn()
        StubBackend.reply(telemetryPath, "{}")
        StubBackend.reply("/oauth2/token", #"{"access_token":"a","token_type":"Bearer","expires_in":3600}"#)
        StubBackend.reply("/oauth2/token", #"{"access_token":"b","token_type":"Bearer","expires_in":3600}"#)
        StubBackend.reply("/flow/execute", #"{"flowId":"f1","flowStatus":"INCOMPLETE"}"#)
        StubBackend.reply("/flow/execute", #"{"flowId":"f1","flowStatus":"INCOMPLETE"}"#)
        StubBackend.reply("/groups", status: 201, "{}")
        let client = try await makeClient()
        let http = try XCTUnwrap(client.httpClient)
        let flow = try XCTUnwrap(client.flowClient)
        let _: TokenResponse? = try? await http.postForm(path: "/oauth2/token", form: [("grant_type", "refresh_token")])
        let _: TokenResponse? = try? await client.postForm("\(base)/oauth2/token", form: [("grant_type", "x")])
        _ = try? await flow.submit(flowId: "f1", actionId: "a1", inputs: ["code": "123456"], challengeToken: nil)
        _ = try? await flow.executeSelfFlow(url: URL(string: "\(base)/flow/execute")!, body: ["flowType": "SELF"])
        var request = URLRequest(url: URL(string: "\(base)/groups")!)
        request.httpMethod = "POST"
        _ = try await client.httpRequest(request)
        await client.telemetryClient?.telemetry.flush()
        XCTAssertEqual(StubBackend.requests(to: "/oauth2/token").count, 2)
        XCTAssertEqual(StubBackend.requests(to: "/flow/execute").count, 2)
        XCTAssertEqual(sentNames, ["group.create"])
    }

    // MARK: - Auth events

    func testReportsASignInOncePerSignInSessionUnderTheVendorsKey() async throws {
        let suite = "telemetry-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var claims: [String: Any]? = ["sub": "u1", "auth_time": 1_700_000_000]
        StubBackend.reply("/", "{}")
        var deps = dependencies()
        deps.claims = { claims }
        deps.defaults = defaults
        deps.session = StubBackend.makeSession()
        let telemetry = try XCTUnwrap(ClientTelemetry(
            config: TelemetryConfig(endpoint: "https://collector.example.com/", format: .json),
            dependencies: deps
        ))

        await telemetry.signedIn()
        await telemetry.signedIn()
        XCTAssertEqual(defaults.string(forKey: "acme-telemetry-sign-in"), "u1:1700000000")
        XCTAssertNil(defaults.string(forKey: "thunderid-telemetry-sign-in"))
        claims = ["sub": "u1", "auth_time": 1_700_000_500]
        await telemetry.signedIn()
        await telemetry.signedOut()
        XCTAssertNil(defaults.string(forKey: "acme-telemetry-sign-in"))
        await telemetry.signedIn()
        claims = ["sub": "u1"]
        await telemetry.signedIn()
        await telemetry.signedIn()
        claims = nil
        await telemetry.signedIn()
        await telemetry.telemetry.flush()

        let names = StubBackend.requests(to: "/").flatMap { recorded -> [String] in
            let events = recorded.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }
            return (events ?? []).compactMap { $0["name"] as? String }
        }
        XCTAssertEqual(names, ["auth.sign-in", "auth.sign-in", "auth.sign-out", "auth.sign-in", "auth.sign-in"])
    }

    func testReportsAnEmbeddedSignInFlowErrorWithOnlyAWellFormedCode() async throws {
        StubBackend.reply(telemetryPath, "{}")
        StubBackend.reply(
            "/flow/execute",
            #"{"flowStatus":"ERROR","error":{"code":"AUTH-1001","message":{"defaultValue":"Ada is locked"}}}"#
        )
        StubBackend.reply(
            "/flow/execute",
            #"{"flowStatus":"ERROR","error":{"code":"ada@example.com","message":{"defaultValue":"No"}}}"#
        )
        let client = try await makeClient()
        let request = EmbeddedFlowRequestConfig(applicationId: "app-1")
        _ = try await client.signIn(payload: EmbeddedSignInPayload(), request: request)
        _ = try await client.signIn(payload: EmbeddedSignInPayload(), request: request)
        await client.telemetryClient?.telemetry.flush()
        let events = StubBackend.requests(to: telemetryPath)
            .compactMap { $0.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } }
            .flatMap { $0 }
        XCTAssertEqual(events.compactMap { $0["name"] as? String }, ["auth.sign-in-failed", "auth.sign-in-failed"])
        let data = events.map { ($0["attributes"] as? [String: Any])?["data"] as? [String: String] ?? [:] }
        XCTAssertEqual(data, [["error_code": "AUTH-1001"], [:]])
        let body = String(data: StubBackend.requests(to: telemetryPath)[0].body ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(body.contains("Ada"))
        XCTAssertFalse(body.contains("ada@"))
    }

    func testNeverReportsASilentOrganizationUnitSwitchAsASignIn() async throws {
        let authTime = Int.random(in: 1_000_000...9_000_000)
        let session = { (ouId: String) in
            OAuthTestCase.jwt(["sub": "u-silent", "ouId": ouId, "auth_time": authTime])
        }
        try TokenStore(storage: storage).save(TokenResponse(
            accessToken: session("ou-1"),
            tokenType: "Bearer",
            expiresIn: 3600,
            deviceSecret: "ds-1"
        ))
        StubBackend.reply(telemetryPath, "{}")
        for ouId in ["ou-2", "ou-3"] {
            StubBackend.reply(
                "/ou/\(ouId)/oauth2/token",
                #"{"access_token":"\#(session(ouId))","token_type":"Bearer","expires_in":3600}"#
            )
        }
        let client = try await makeClient()
        _ = try await client.switchOrganizationUnit("ou-2")
        _ = try await client.switchOrganizationUnit("ou-3")
        await client.telemetryClient?.telemetry.flush()
        client.track("item.open")
        await client.telemetryClient?.telemetry.flush()
        XCTAssertEqual(StubBackend.requests(to: "/ou/ou-3/oauth2/token").count, 1)
        // A switch of organization unit is not a new sign-in.
        XCTAssertEqual(sentNames, ["item.open"])
    }

    func testReportsAFailedSignInWithItsCodeOnly() async throws {
        StubBackend.reply(telemetryPath, "{}")
        let client = try await makeClient()
        let callback = URL(string: "myapp://callback?error=access_denied&error_description=Ada")!
        _ = try? await client.handleRedirectCallback(url: callback)
        _ = try? await client.handleRedirectCallback(url: URL(string: "myapp://callback")!)
        await client.telemetryClient?.telemetry.flush()
        XCTAssertEqual(sentNames, ["auth.sign-in-failed", "auth.sign-in-failed"])
        let body = String(data: StubBackend.requests(to: telemetryPath)[0].body ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("INVALID_GRANT"))
        XCTAssertFalse(body.contains("Ada"))
    }

    func testReportsASignOutWithTheUserBeforeTheSessionIsCleared() async throws {
        try signIn(["sub": "u1", "ouId": "ou1"])
        StubBackend.reply(telemetryPath, "{}")
        StubBackend.reply("/oauth2/revoke", "{}")
        let client = try await makeClient()
        _ = try await client.signOut()
        let events = StubBackend.requests(to: telemetryPath)
            .compactMap { $0.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } }
            .flatMap { $0 }
        XCTAssertEqual(events.compactMap { $0["name"] as? String }, ["auth.sign-out"])
        let attributes = events.first?["attributes"] as? [String: Any]
        XCTAssertEqual(attributes?["user"] as? [String: String], ["id": "u1"])
        XCTAssertEqual(attributes?["organization"] as? [String: String], ["id": "ou1"])
    }

    func testWatchesTheManagementCollectionsConfiguredElsewhere() {
        let config = ThunderIDConfig(
            baseUrl: base,
            endpoints: .init(applications: "https://mgmt.example.com/api/applications", users: "\(base)/users")
        )
        XCTAssertEqual(ThunderIDClient.telemetryApiBases(config), [base, "https://mgmt.example.com/api"])
    }
}
