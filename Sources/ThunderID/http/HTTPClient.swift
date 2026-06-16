import Foundation

/// Performs HTTP requests against the ThunderID server. Enforces HTTPS and log sanitization (spec §11.5–11.6).
final class HTTPClient {
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

    func post<T: Decodable>(path: String, body: [String: Any], requiresAuth: Bool = true) async throws -> T {
        let request = try await buildRequest(method: "POST", path: path, body: body, requiresAuth: requiresAuth)
        return try await perform(request)
    }

    func delete(path: String, requiresAuth: Bool = true) async throws {
        let request = try await buildRequest(method: "DELETE", path: path, body: nil, requiresAuth: requiresAuth)
        let _: EmptyResponse = try await perform(request)
    }

    private func buildRequest(method: String, path: String, body: [String: Any]?, requiresAuth: Bool) async throws -> URLRequest {
        guard let url = URL(string: baseUrl + path) else {
            throw IAMError(code: .invalidConfiguration, message: "Invalid URL: \(baseUrl)\(path)")
        }
        guard url.scheme == "https" else {
            throw IAMError(code: .invalidConfiguration, message: "baseUrl must use HTTPS")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
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

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
            debugLogResponse(response, data: data)
        } catch {
            let nsError = error as NSError
            let details = "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
            debugLog("HTTP network error for \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "") -> \(details)")
            throw IAMError(
                code: .networkError,
                message: "Network request failed: \(details)",
                underlyingError: error
            )
        }
        guard let http = response as? HTTPURLResponse else {
            throw IAMError(code: .networkError, message: "Invalid response")
        }
        switch http.statusCode {
        case 200...299:
            do {
                if T.self == EmptyResponse.self {
                    guard let result = EmptyResponse() as? T else {
                        throw IAMError(code: .unknownError, message: "Type mismatch")
                    }
                    return result
                }
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                if let raw = String(data: data, encoding: .utf8) {
                    debugLog("HTTP decode failure payload: \(raw)")
                }
                throw IAMError(code: .unknownError, message: "Failed to decode response", underlyingError: error)
            }
        case 400:
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("[DEBUG][HTTPClient] 400 response body: \(rawBody)")
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? "Bad request"
            throw IAMError(code: .invalidInput, message: detail)
        case 401:
            throw IAMError(code: .authenticationFailed, message: "Unauthorized")
        case 409:
            throw IAMError(code: .userAlreadyExists, message: "Conflict")
        case 500...599:
            throw IAMError(code: .serverError, message: "Server error: \(http.statusCode)")
        default:
            throw IAMError(code: .unknownError, message: "Unexpected status: \(http.statusCode)")
        }
    }
}

private struct EmptyResponse: Decodable {}

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
        print("[ThunderID][HTTP] \(message)")
        #endif
    }
}
