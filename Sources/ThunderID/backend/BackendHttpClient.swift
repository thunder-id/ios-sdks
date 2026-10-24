// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The transport used when sign-in runs on the backend. It sends each request under the API base through
/// the backend's proxy with the session handle instead of a token, and refreshes the session once when the
/// backend reports it expired. Requests under `bypass` go straight there, with the access token the backend
/// issued unless that is turned off, and never with the session handle.
struct BackendHttpClient {
    let backend: BackendClient
    /// Sends the requests. It logs nothing, as each one carries the session handle or a token.
    let http: HTTPClient

    /// Sends `request` and returns the response whatever its status, so a `401` that is the API's own
    /// answer reaches the caller untouched.
    ///
    /// - Parameter fetcher: The caller's own transport for the final hop, when it passed one.
    /// - Throws: `unsupportedOperation` for a URL outside the API base and outside `bypass`, which is
    ///   refused rather than sent without the session.
    func send(_ request: URLRequest, fetcher: ThunderIDFetcher? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else {
            throw ThunderIDError(code: .invalidInput, message: "The request has no URL")
        }
        let endpoints = backend.endpoints
        if endpoints.isBypassed(url) {
            return try await sendBypassed(request, fetcher: fetcher)
        }
        guard let proxyURL = endpoints.proxyURL(for: url) else {
            throw ThunderIDError(
                code: .unsupportedOperation,
                message: "A request outside the API base cannot be sent when sign-in runs on a backend"
            )
        }
        var proxied = request
        proxied.url = proxyURL
        return try await sendProxied(proxied, fetcher: fetcher)
    }

    private func sendProxied(
        _ request: URLRequest,
        fetcher: ThunderIDFetcher?
    ) async throws -> (Data, HTTPURLResponse) {
        let first = try await sendWithHandle(request, fetcher: fetcher)
        guard first.1.statusCode == 401 else { return first }
        switch BackendClient.errorCode(first.0) {
        case "session_expired":
            // Only the backend's own `session_expired` calls for a refresh. Any other 401 is the API's answer.
            guard try await backend.refresh() else { return first }
            let retry = try await sendWithHandle(request, fetcher: fetcher)
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
        fetcher: ThunderIDFetcher?
    ) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if let handle = await backend.sessionHandle() {
            request.setValue(handle, forHTTPHeaderField: backendSessionHandleHeader)
        }
        return try await http.rawData(for: request, fetcher: fetcher)
    }

    /// Sends a request straight to its URL, skipping the proxy. With `attachToken` on it carries the access
    /// token, and when the API rejects it, gets a new one and retries once.
    private func sendBypassed(
        _ request: URLRequest,
        fetcher: ThunderIDFetcher?
    ) async throws -> (Data, HTTPURLResponse) {
        guard backend.endpoints.attachToken else {
            return try await http.rawData(for: request, fetcher: fetcher)
        }
        let send = { (renew: Bool) async throws -> (Data, HTTPURLResponse) in
            var authorized = request
            let token = try await backend.accessToken(renew: renew)
            authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return try await http.rawData(for: authorized, fetcher: fetcher)
        }
        let first = try await send(false)
        guard first.1.statusCode == 401 else { return first }
        return try await send(true)
    }
}
