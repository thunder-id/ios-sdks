// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

/// Performs HTTP requests against the ThunderID server. Enforces HTTPS and log sanitization (spec §11.5–11.6).
final class HTTPClient {
    private static let logger = Logger(subsystem: "dev.thunderid.sdk", category: "HTTPClient")
    private let baseUrl: String
    private let session: URLSession
    private var accessTokenProvider: (() async throws -> String)?

    init(baseUrl: String, session: URLSession? = nil) {
        self.baseUrl = baseUrl
        self.session = session ?? LocalhostPinnedURLSession.make(for: baseUrl)
    }

    func setAccessTokenProvider(_ provider: @escaping () async throws -> String) {
        accessTokenProvider = provider
    }

    func get<T: Decodable>(path: String, requiresAuth: Bool = true) async throws -> T {
        let request = try await buildRequest(method: "GET", path: path, body: nil, requiresAuth: requiresAuth)
        return try await perform(request)
    }

    func post<T: Decodable>(
        path: String,
        body: [String: Any],
        requiresAuth: Bool = true,
        headers: [String: String] = [:]
    ) async throws -> T {
        var request = try await buildRequest(method: "POST", path: path, body: body, requiresAuth: requiresAuth)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return try await perform(request)
    }

    func put<T: Decodable>(
        path: String,
        body: [String: Any],
        requiresAuth: Bool = true,
        headers: [String: String] = [:]
    ) async throws -> T {
        var request = try await buildRequest(method: "PUT", path: path, body: body, requiresAuth: requiresAuth)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return try await perform(request)
    }

    func delete(path: String, requiresAuth: Bool = true) async throws {
        let request = try await buildRequest(method: "DELETE", path: path, body: nil, requiresAuth: requiresAuth)
        let _: EmptyResponse = try await perform(request)
    }

    /// Resolves `path` against `baseUrl`, for callers that build absolute URLs themselves.
    func url(forPath path: String) -> URL? {
        URL(string: baseUrl + path)
    }

    /// Sends an authenticated request to an absolute URL, which may live on a different host from `baseUrl`.
    /// When `fetcher` is set it replaces the `URLSession` transport for this request; the access token is
    /// already attached to the request it receives.
    func send<T: Decodable>(
        method: String,
        url: URL,
        body: Data? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> T {
        guard url.scheme == "https" else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Request URL must use HTTPS")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.assumesHTTP3Capable = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        if let provider = accessTokenProvider {
            let token = try await provider()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        debugLogRequest(request, body: nil)
        return try await perform(request, fetcher: fetcher)
    }

    private func buildRequest(
        method: String, path: String, body: [String: Any]?, requiresAuth: Bool
    ) async throws -> URLRequest {
        guard let url = URL(string: baseUrl + path) else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Invalid URL: \(baseUrl)\(path)")
        }
        guard url.scheme == "https" else {
            throw ThunderIDError(code: .invalidConfiguration, message: "baseUrl must use HTTPS")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        // HTTP/3 (QUIC) connections never invoke URLSessionDelegate's server-trust challenge,
        // so a self-signed dev cert always fails trust evaluation. Force HTTP/1.1 or HTTP/2
        // over TLS instead, which correctly routes through LocalhostPinnedURLSession's delegate.
        request.assumesHTTP3Capable = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if requiresAuth, let provider = accessTokenProvider {
            let token = try await provider()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        debugLogRequest(request, body: body)
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest, fetcher: ThunderIDFetcher? = nil) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            if let fetcher {
                (data, response) = try await fetcher(request)
            } else {
                (data, response) = try await session.data(for: request)
            }
            debugLogResponse(response, data: data)
        } catch {
            let nsError = error as NSError
            let details = "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
            let urlStr = request.url?.absoluteString ?? ""
            debugLog("HTTP network error for \(request.httpMethod ?? "?") \(urlStr) -> \(details)")
            throw ThunderIDError(
                code: .networkError,
                message: "Network request failed: \(details)",
                underlyingError: error
            )
        }
        guard let http = response as? HTTPURLResponse else {
            throw ThunderIDError(code: .networkError, message: "Invalid response")
        }
        return try handleResponse(http, data: data)
    }

    private func handleResponse<T: Decodable>(_ http: HTTPURLResponse, data: Data) throws -> T {
        switch http.statusCode {
        case 200...299:
            return try decodeSuccess(data)
        case 400:
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("[DEBUG][HTTPClient] 400 response body: \(rawBody)")
            let msgBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let detail = msgBody?["message"] as? String ?? "Bad request"
            throw ThunderIDError(code: .invalidInput, message: detail)
        case 401:
            throw ThunderIDError(code: .authenticationFailed, message: "Unauthorized")
        case 403:
            throw ThunderIDError(code: .forbidden, message: "Forbidden")
        case 404:
            throw ThunderIDError(code: .notFound, message: "Not found")
        case 409:
            throw ThunderIDError(code: .userAlreadyExists, message: "Conflict")
        case 500...599:
            throw ThunderIDError(code: .serverError, message: "Server error: \(http.statusCode)")
        default:
            throw ThunderIDError(code: .unknownError, message: "Unexpected status: \(http.statusCode)")
        }
    }

    private func decodeSuccess<T: Decodable>(_ data: Data) throws -> T {
        if T.self == EmptyResponse.self {
            guard let result = EmptyResponse() as? T else {
                throw ThunderIDError(code: .unknownError, message: "Type mismatch")
            }
            return result
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let raw = String(data: data, encoding: .utf8) {
                debugLog("HTTP decode failure payload: \(raw)")
            }
            throw ThunderIDError(
                code: .unknownError,
                message: "Failed to decode response",
                underlyingError: error
            )
        }
    }
}

/// Marker type for a `204 No Content` (or otherwise empty-body) response. `decodeSuccess`
/// special-cases it so callers never try to JSON-decode an empty body.
struct EmptyResponse: Decodable {}

private extension HTTPClient {
    func debugLogRequest(_ request: URLRequest, body: [String: Any]?) {
        #if DEBUG
        let method = request.httpMethod ?? "?"
        let url = request.url?.absoluteString ?? ""
        if let body {
            debugLog("HTTP request: \(method) \(url) body=\(body)")
        } else {
            debugLog("HTTP request: \(method) \(url)")
        }
        #endif
    }

    func debugLogResponse(_ response: URLResponse, data: Data) {
        #if DEBUG
        guard let http = response as? HTTPURLResponse else {
            debugLog("HTTP response: non-HTTP response")
            return
        }
        let preview = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        debugLog("HTTP response: status=\(http.statusCode) body=\(preview)")
        #endif
    }

    func debugLog(_ message: String) {
        #if DEBUG
        // os.Logger rather than print(): the simulator's unified log (what Maestro's CI debug
        // artifact actually captures) never sees plain stdout from a simctl-launched process.
        // .debug()/.info() levels aren't persisted to the log store by default, only replayed to
        // an attached debugger, so a log pulled after the fact would never show them - .notice()
        // (Logger's default level) is what actually survives to `log show`/`log collect`.
        HTTPClient.logger.notice("\(message, privacy: .public)")
        #endif
    }
}
