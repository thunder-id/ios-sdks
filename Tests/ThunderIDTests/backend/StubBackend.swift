// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A `URLProtocol` stub that answers by request path from per-path queues of canned responses and records
/// every request it sees, so a test can drive the backend and the APIs without a network.
final class StubBackend: URLProtocol {
    struct Reply {
        let status: Int
        let body: String
        /// Seconds the stub waits before answering, to let concurrent callers overlap.
        var delay: TimeInterval = 0
    }

    struct Recorded {
        let request: URLRequest
        let body: Data?

        var path: String { request.url?.path ?? "" }
        var json: [String: Any]? {
            body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }

        func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }
    }

    private static let lock = NSLock()
    private static var queues: [String: [Reply]] = [:]
    private static var recorded: [Recorded] = []
    /// When set, a request to this path waits on it before answering.
    static var gate: (path: String, semaphore: DispatchSemaphore)?

    static func reset() {
        lock.lock()
        queues = [:]
        recorded = []
        gate = nil
        lock.unlock()
    }

    /// Queues `body` as the next answer for `path`. The last answer queued for a path repeats.
    static func reply(_ path: String, status: Int = 200, _ body: String = "{}", delay: TimeInterval = 0) {
        lock.lock()
        queues[path, default: []].append(Reply(status: status, body: body, delay: delay))
        lock.unlock()
    }

    static var requests: [Recorded] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    static func requests(to path: String) -> [Recorded] {
        requests.filter { $0.path == path }
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubBackend.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        if let gate = StubBackend.gate, gate.path == path {
            gate.semaphore.wait()
        }
        StubBackend.lock.lock()
        StubBackend.recorded.append(Recorded(request: request, body: Self.body(of: request)))
        var queue = StubBackend.queues[path] ?? []
        let reply = queue.count > 1 ? queue.removeFirst() : queue.first
        StubBackend.queues[path] = queue
        StubBackend.lock.unlock()

        guard let reply else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        if reply.delay > 0 {
            Thread.sleep(forTimeInterval: reply.delay)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// `URLSession` hands a protocol the body as a stream, not as `httpBody`.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
