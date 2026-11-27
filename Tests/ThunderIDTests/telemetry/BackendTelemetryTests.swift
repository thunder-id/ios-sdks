// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Telemetry when sign-in runs on a backend: API events come from the calls through its proxy, the user
/// from its session, and no token goes to the endpoint.
final class BackendTelemetryTests: XCTestCase {
    let base = "https://app.example.com"
    let proxyBase = "https://app.example.com/api/auth/proxy"
    let telemetryPath = "/telemetry"
    var client: ThunderIDClient!

    override func setUp() {
        super.setUp()
        StubBackend.reset()
    }

    override func tearDown() {
        StubBackend.reset()
        super.tearDown()
    }

    private func makeClient() async throws {
        let storage = InMemoryStorageAdapter()
        try TokenStore(storage: storage).saveSessionHandle("h1")
        let config = ThunderIDConfig(
            baseUrl: base,
            afterSignInUrl: "myapp://callback",
            endpoints: .init(backend: .init()),
            telemetry: TelemetryConfig(endpoint: "\(base)\(telemetryPath)", format: .json)
        )
        client = ThunderIDClient()
        StubBackend.reply("/api/auth/session", #"{"isSignedIn":true,"user":{"sub":"u1","ouId":"ou1"}}"#)
        StubBackend.reply(telemetryPath, "{}")
        _ = try await client.initialize(config: config, storage: storage, session: StubBackend.makeSession())
        _ = try await client.isSignedIn()
    }

    private var events: [[String: Any]] {
        StubBackend.requests(to: telemetryPath)
            .compactMap { $0.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } }
            .flatMap { $0 }
    }

    func testReportsACallThroughTheProxyOnceWhateverTheRetries() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/proxy/applications", status: 401, #"{"error":"session_expired"}"#)
        StubBackend.reply("/api/auth/proxy/applications", status: 201, "{}")
        StubBackend.reply("/api/auth/refresh")
        var request = URLRequest(url: URL(string: "\(proxyBase)/applications")!)
        request.httpMethod = "POST"
        _ = try await client.httpRequest(request)
        await client.telemetryClient?.telemetry.flush()

        XCTAssertEqual(events.compactMap { $0["name"] as? String }, ["application.create"])
        let attributes = events.first?["attributes"] as? [String: Any]
        XCTAssertEqual(attributes?["user"] as? [String: String], ["id": "u1"])
        XCTAssertEqual(attributes?["route"] as? String, "/applications")
        XCTAssertNil(StubBackend.requests(to: telemetryPath).first?.header("Authorization"))
    }

    func testNeverReportsTheSdksOwnFlowRequestsThroughTheProxy() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/proxy/flow/execute", #"{"flowId":"f1","flowStatus":"INCOMPLETE"}"#)
        StubBackend.reply("/api/auth/proxy/applications", status: 201, "{}")
        let flow = try XCTUnwrap(client.flowClient)
        _ = try? await flow.submit(flowId: "f1", actionId: "a1", inputs: ["code": "123456"], challengeToken: nil)
        var request = URLRequest(url: URL(string: "\(proxyBase)/applications")!)
        request.httpMethod = "POST"
        _ = try await client.httpRequest(request)
        await client.telemetryClient?.telemetry.flush()

        XCTAssertEqual(StubBackend.requests(to: "/api/auth/proxy/flow/execute").count, 1)
        XCTAssertEqual(events.compactMap { $0["name"] as? String }, ["application.create"])
    }

    func testReportsASessionThatEndedElsewhere() async throws {
        try await makeClient()
        StubBackend.reply("/api/auth/proxy/users/u2", status: 401, #"{"error":"login_required"}"#)
        var request = URLRequest(url: URL(string: "\(proxyBase)/users/u2")!)
        request.httpMethod = "DELETE"
        _ = try await client.httpRequest(request)
        await client.telemetryClient?.telemetry.flush()

        XCTAssertEqual(
            events.compactMap { $0["name"] as? String }.sorted(),
            ["auth.session-expired", "user.delete-failed"]
        )
    }
}
