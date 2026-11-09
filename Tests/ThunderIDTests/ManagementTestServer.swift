// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// A fetcher that answers like the server: the `flow` server-config section, the flow listing, flow
/// execution, and one resource for every other request. It records every request it receives.
final class ManagementTestServer: @unchecked Sendable {
    static let baseUrl = "https://localhost:8090"

    /// The `flow` server-config section, as JSON: the configured handle for each operation.
    var config = "{}"
    /// The administration flows the listing returns, as `(handle, id)`.
    var flows: [(handle: String, id: String)] = []
    /// The response of `POST /flow/execute`.
    var execution = #"{"flowStatus":"COMPLETE","data":{"additionalData":{}}}"#
    var executionStatus = 200
    /// The response of any other request.
    var resource = "{}"
    var resourceStatus = 200
    /// Answers a flow listing page itself, when set.
    var listing: ((URL) -> String)?

    private(set) var requests: [URLRequest] = []

    var fetcher: ThunderIDFetcher {
        { [self] request in
            requests.append(request)
            let url = request.url!
            let (body, status) = answer(url)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    private func answer(_ url: URL) -> (String, Int) {
        let base = Self.baseUrl
        let absolute = url.absoluteString
        if absolute == "\(base)/server-config/flow" {
            return (#"{"merged":\#(config)}"#, 200)
        }
        if absolute.hasPrefix("\(base)/flows?") {
            if let listing { return (listing(url), 200) }
            let items = flows.map { #"{"flowType":"ADMINISTRATION","handle":"\#($0.handle)","id":"\#($0.id)"}"# }
            return (#"{"flows":[\#(items.joined(separator: ","))]}"#, 200)
        }
        if absolute == "\(base)/flow/execute" {
            return (execution, executionStatus)
        }
        return (resource, resourceStatus)
    }

    /// Each request as `METHOD url`.
    var calls: [String] {
        requests.map { "\($0.httpMethod ?? "?") \($0.url?.absoluteString ?? "")" }
    }

    /// The JSON bodies sent to `POST /flow/execute`, in order.
    var executions: [[String: Any]] {
        requests
            .filter { $0.url?.absoluteString == "\(Self.baseUrl)/flow/execute" }
            .compactMap { Self.json($0.httpBody) }
    }

    /// The JSON body of the first request with `method`.
    func body(of method: String) -> [String: Any]? {
        Self.json(requests.first { $0.httpMethod == method }?.httpBody)
    }

    static func json(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// A signed-in client whose management calls go through this server.
    func makeClient(
        baseUrl: String = ManagementTestServer.baseUrl,
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
}

/// Asserts that `operation` throws a `ThunderIDError` with `code`, and returns it.
@discardableResult
func assertThrowsThunderIDError(
    _ code: ThunderIDErrorCode,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () async throws -> Void
) async -> ThunderIDError? {
    do {
        try await operation()
        XCTFail("Expected \(code.rawValue)", file: file, line: line)
    } catch let error as ThunderIDError {
        XCTAssertEqual(error.code, code, file: file, line: line)
        return error
    } catch {
        XCTFail("Unexpected error \(error)", file: file, line: line)
    }
    return nil
}
