// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Minimal `URLProtocol` stub so a test can exercise the real HTTP path (`HTTPClient` ->
/// `URLSession`) without a real network. Each test installs its own `handler` and reads
/// `requestCount` to assert on how many times the mocked endpoint was actually hit.
final class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var _requestCount = 0
    private static var _pathCounts: [String: Int] = [:]

    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _requestCount
    }

    /// Requests observed for `path` (matched against `URL.path`), independent of any unrelated
    /// requests another call (e.g. `refresh()`'s own `getUser`/`getUserProfile` side effects) fires
    /// at the same time.
    static func requestCount(forPath path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return _pathCounts[path] ?? 0
    }

    static func reset() {
        lock.lock()
        _requestCount = 0
        _pathCounts = [:]
        _handler = nil
        lock.unlock()
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lock.lock()
        MockURLProtocol._requestCount += 1
        if let path = request.url?.path {
            MockURLProtocol._pathCounts[path, default: 0] += 1
        }
        MockURLProtocol.lock.unlock()

        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
