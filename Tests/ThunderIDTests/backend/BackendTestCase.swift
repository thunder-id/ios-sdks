// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Sets up a client whose sign-in runs on a stubbed backend.
class BackendTestCase: XCTestCase {
    let apiBase = "https://api.example.com"
    let backendBase = "https://app.example.com"
    let dataPlane = "https://dp.example.com/api"
    let signedIn = #"{"isSignedIn":true,"user":{"sub":"u1","name":"Ada"},"expiresAt":1900000000}"#

    var storage: InMemoryStorageAdapter!
    var client: ThunderIDClient!
    var signOuts = 0

    override func setUp() {
        super.setUp()
        StubBackend.reset()
        storage = InMemoryStorageAdapter()
        signOuts = 0
    }

    override func tearDown() {
        StubBackend.reset()
        super.tearDown()
    }

    /// Initializes the client. With `handle`, a session is already stored and read once, after which the
    /// recorded requests and queued replies are cleared.
    func makeClient(
        handle: String? = "h1",
        attachToken: Bool = true,
        checkInterval: TimeInterval = 0,
        readSession: Bool = true
    ) async throws {
        if let handle { try TokenStore(storage: storage).saveSessionHandle(handle) }
        let config = ThunderIDConfig(
            baseUrl: apiBase,
            afterSignInUrl: "myapp://callback",
            afterSignOutUrl: "myapp://signedout",
            session: .init(checkInterval: checkInterval),
            endpoints: .init(
                backend: .init(baseUrl: backendBase, bypass: .init(urls: [dataPlane], attachToken: attachToken))
            )
        )
        client = ThunderIDClient()
        _ = try await client.initialize(config: config, storage: storage, session: StubBackend.makeSession())
        client.onSignOut { [weak self] in self?.signOuts += 1 }
        if readSession {
            StubBackend.reply("/api/auth/session", signedIn)
            _ = try await client.isSignedIn()
            StubBackend.reset()
        }
    }

    func request(_ url: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        return request
    }

    var storedHandle: String? { TokenStore(storage: storage).sessionHandle() }
    var storedToken: String? { TokenStore(storage: storage).accessToken() }

    func assertThrows(
        _ code: ThunderIDErrorCode,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected \(code.rawValue)", file: file, line: line)
        } catch {
            XCTAssertEqual((error as? ThunderIDError)?.code, code, "\(error)", file: file, line: line)
        }
    }
}
