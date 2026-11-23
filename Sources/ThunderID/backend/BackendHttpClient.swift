// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The transport used when sign-in runs on the backend. It sends each API call (a path, or a URL already
/// under the proxy) through the backend's proxy with the session handle instead of a token, and refreshes
/// the session once when the backend reports it expired. Requests under `bypass` go straight there, with
/// the access token the backend issued unless that is turned off, and never with the session handle.
struct BackendHttpClient {
    let backend: BackendClient
    /// Sends the requests. It logs nothing, as each one carries the session handle or a token.
    let http: HTTPClient

    /// Sends `request` and returns the response whatever its status, so a `401` that is the API's own
    /// answer reaches the caller untouched.
    ///
    /// - Parameters:
    ///   - fetcher: The caller's own transport for the final hop, when it passed one.
    ///   - observe: Whether the request observer sees it. Off for the SDK's own sign-in and flow requests.
    /// - Throws: `unsupportedOperation` for an absolute URL outside the proxy and outside `bypass`, which is
    ///   refused rather than sent without the session.
    func send(
        _ request: URLRequest,
        fetcher: ThunderIDFetcher? = nil,
        observe: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        var sent = request
        let observer = observe ? http.requestObserver : nil
        let attempt = BackendSendAttempt()
        do {
            let result = try await route(request, fetcher: fetcher, sent: &sent, attempt: attempt)
            observer?(sent, .response(result.1, result.0))
            return result
        } catch {
            if let response = attempt.response {
                // The API answered, and a step after its answer failed, such as renewing the token or the
                // session after a `401`: its answer is what is reported.
                observer?(sent, .response(response.1, response.0))
            } else if attempt.started, (error as? ThunderIDError)?.code == .networkError {
                // Only a request that left and got no answer fails. One that never left, such as one refused or
                // whose token could not be read, is not reported.
                observer?(sent, .failed)
            }
            throw error
        }
    }

    /// Sends `request` through the proxy or straight to a bypassed URL, setting `sent` to the request as it
    /// left, for the request observer, which sees it once whatever the retries.
    private func route(
        _ request: URLRequest,
        fetcher: ThunderIDFetcher?,
        sent: inout URLRequest,
        attempt: BackendSendAttempt
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else {
            throw ThunderIDError(code: .invalidInput, message: "The request has no URL")
        }
        let endpoints = backend.endpoints
        if endpoints.isBypassed(url) {
            return try await sendBypassed(request, fetcher: fetcher, attempt: attempt)
        }
        guard let proxyURL = endpoints.proxyURL(for: url) else {
            throw ThunderIDError(
                code: .unsupportedOperation,
                message: "A request outside the backend's proxy cannot be sent when sign-in runs on a backend"
            )
        }
        var proxied = request
        proxied.url = proxyURL
        sent = proxied
        return try await sendProxied(proxied, fetcher: fetcher, attempt: attempt)
    }

    private func sendProxied(
        _ request: URLRequest,
        fetcher: ThunderIDFetcher?,
        attempt: BackendSendAttempt
    ) async throws -> (Data, HTTPURLResponse) {
        let first = try await sendWithHandle(request, fetcher: fetcher, attempt: attempt)
        guard first.1.statusCode == 401 else { return first }
        switch BackendClient.errorCode(first.0) {
        case "session_expired":
            // Only the backend's own `session_expired` calls for a refresh. Any other 401 is the API's answer.
            guard try await backend.refresh() else { return first }
            let retry = try await sendWithHandle(request, fetcher: fetcher, attempt: attempt)
            if retry.1.statusCode == 401,
               ["session_expired", "login_required"].contains(BackendClient.errorCode(retry.0)) {
                await backend.markSignedOut()
            }
            return retry
        case "login_required":
            await backend.markSignedOut()
            return first
        default:
            return first
        }
    }

    private func sendWithHandle(
        _ request: URLRequest,
        fetcher: ThunderIDFetcher?,
        attempt: BackendSendAttempt
    ) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if let handle = await backend.sessionHandle() {
            request.setValue(handle, forHTTPHeaderField: backendSessionHandleHeader)
        }
        return try await transmit(request, fetcher: fetcher, attempt: attempt)
    }

    /// Sends `request` as it is, recording on `attempt` that it left and the answer it got.
    private func transmit(
        _ request: URLRequest,
        fetcher: ThunderIDFetcher?,
        attempt: BackendSendAttempt
    ) async throws -> (Data, HTTPURLResponse) {
        attempt.started = true
        let result = try await http.rawData(for: request, fetcher: fetcher, observe: false)
        attempt.response = result
        return result
    }

    /// Sends a request straight to its URL, skipping the proxy. With `attachToken` on it carries the access
    /// token, and when the API rejects it, gets a new one and retries once.
    private func sendBypassed(
        _ request: URLRequest,
        fetcher: ThunderIDFetcher?,
        attempt: BackendSendAttempt
    ) async throws -> (Data, HTTPURLResponse) {
        guard backend.endpoints.attachToken else {
            return try await transmit(request, fetcher: fetcher, attempt: attempt)
        }
        let send = { (renew: Bool) async throws -> (Data, HTTPURLResponse) in
            var authorized = request
            let token = try await backend.accessToken(renew: renew)
            authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return try await transmit(authorized, fetcher: fetcher, attempt: attempt)
        }
        let first = try await send(false)
        guard first.1.statusCode == 401 else { return first }
        return try await send(true)
    }
}

/// Whether a request through the backend transport has left the client, and the last answer it got, so that
/// a step before it fails silently, such as reading a token, a step after an answer, such as renewing the
/// token, reports that answer, and only a request that got no answer is reported as a failed call.
final class BackendSendAttempt: @unchecked Sendable {
    private let lock = NSLock()
    private var _started = false
    private var _response: (Data, HTTPURLResponse)?

    var started: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _started
        }
        set {
            lock.lock()
            _started = newValue
            lock.unlock()
        }
    }

    /// The last answer the API gave, if any.
    var response: (Data, HTTPURLResponse)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _response
        }
        set {
            lock.lock()
            _response = newValue
            lock.unlock()
        }
    }
}
