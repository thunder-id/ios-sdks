// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers `ThunderIDState.getUserSchema()`'s cache/dedup behavior: the fix that lets `UserProfile`
/// and `ChangeCredential` share one `GET /users/me/meta` fetch instead of issuing one each. Uses
/// `MockURLProtocol` to exercise the real `HTTPClient` -> `URLSession` path, since nothing else in
/// this repo mocks the network layer.
@MainActor
final class ThunderIDStateTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private let schemaBody = Data(#"{"schema":{"password":{"credential":true}}}"#.utf8)

    /// Builds a `ThunderIDState` whose `ThunderIDClient` is already initialized against a mocked
    /// session and a pre-seeded access token, so `getUserSchema()`'s outbound request never touches
    /// real network or a real token refresh.
    private func makeState() async throws -> ThunderIDState {
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "test-client")
        let storage = InMemoryStorageAdapter()
        // Mirrors TokenStore's private storage key; seeding it directly skips a real sign-in.
        storage.store(key: "thunder.access_token", value: "test-access-token")
        let client = ThunderIDClient()
        _ = try await client.initialize(config: config, storage: storage, session: MockURLProtocol.makeSession())
        return ThunderIDState(client: client, i18n: ThunderIDI18n())
    }

    private func okResponse(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, schemaBody)
    }

    func testFetchesOnceAndCaches() async throws {
        let state = try await makeState()
        MockURLProtocol.handler = { [self] request in okResponse(request) }

        let first = try await state.getUserSchema()
        let second = try await state.getUserSchema()

        XCTAssertEqual(first["password"]?.credential, true)
        XCTAssertEqual(second["password"]?.credential, true)
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testIssuesOnlyOneNetworkCallForConcurrentCallers() async throws {
        let state = try await makeState()
        MockURLProtocol.handler = { [self] request in
            Thread.sleep(forTimeInterval: 0.05)
            return okResponse(request)
        }

        async let first = state.getUserSchema()
        async let second = state.getUserSchema()
        async let third = state.getUserSchema()
        _ = try await (first, second, third)

        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testDoesNotCacheAFailedFetch() async throws {
        let state = try await makeState()
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await state.getUserSchema()
            XCTFail("Expected the first fetch to fail")
        } catch {
            // Expected: the server error above surfaces as a thrown ThunderIDError.
        }

        MockURLProtocol.handler = { [self] request in okResponse(request) }
        let recovered = try await state.getUserSchema()

        XCTAssertEqual(recovered["password"]?.credential, true)
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testRefreshClearsCachedSchema() async throws {
        let state = try await makeState()
        MockURLProtocol.handler = { [self] request in okResponse(request) }
        let metaPath = "/users/me/meta"

        _ = try await state.getUserSchema()
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: metaPath), 1)

        // Marks the state initialized so refresh() doesn't early-return. The client is already
        // initialized (in makeState()), so this call's own client.initialize(config:) rejects with
        // .alreadyInitialized; ThunderIDState.initialize(config:) still sets isInitialized = true on
        // that error path, which is all this test needs. Being "signed in" (the seeded access token)
        // also makes refresh() fire its own getUser()/getUserProfile() calls, which is why the
        // schema endpoint is counted by path rather than by total request count.
        await state.initialize(config: ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "test-client"))
        await state.refresh()

        _ = try await state.getUserSchema()
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: metaPath), 2)
    }
}
