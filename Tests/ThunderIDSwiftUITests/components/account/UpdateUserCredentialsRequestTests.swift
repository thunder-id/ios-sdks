// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Covers the body `updateUserCredentials` sends to `POST /users/me/update-credentials`.
final class UpdateUserCredentialsRequestTests: XCTestCase {
    private let lock = NSLock()
    private var bodies: [[String: String]] = []

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient() async throws -> ThunderIDClient {
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "test-client")
        let storage = InMemoryStorageAdapter()
        // Mirrors TokenStore's private storage key; seeding it directly skips a real sign-in.
        storage.store(key: "thunder.access_token", value: "test-access-token")
        let client = ThunderIDClient()
        _ = try await client.initialize(config: config, storage: storage, session: MockURLProtocol.makeSession())
        MockURLProtocol.handler = { [self] request in
            let data = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
            if let body = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                lock.lock()
                bodies.append(body)
                lock.unlock()
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        return client
    }

    func testSendsTheNameAndBothValues() async throws {
        let client = try await makeClient()

        try await client.updateUserCredentials(attribute: "password", currentValue: "0ldP@ss", newValue: "n3wP@ss")

        XCTAssertEqual(bodies, [["name": "password", "currentValue": "0ldP@ss", "newValue": "n3wP@ss"]])
    }

    func testLeavesOutABlankCurrentValue() async throws {
        let client = try await makeClient()

        try await client.updateUserCredentials(attribute: "pin", currentValue: "", newValue: "1234")

        XCTAssertEqual(bodies, [["name": "pin", "newValue": "1234"]])
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
