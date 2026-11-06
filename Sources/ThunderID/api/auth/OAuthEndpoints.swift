// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The parts of the server's OpenID provider metadata (`/.well-known/openid-configuration`) the client
/// reads: where the optional endpoints are, and whether authorization requests must be pushed.
struct ServerMetadata: Decodable {
    let tokenEndpoint: String?
    let backchannelAuthenticationEndpoint: String?
    let deviceAuthorizationEndpoint: String?
    let pushedAuthorizationRequestEndpoint: String?
    let requirePushedAuthorizationRequests: Bool?

    enum CodingKeys: String, CodingKey {
        case tokenEndpoint = "token_endpoint"
        case backchannelAuthenticationEndpoint = "backchannel_authentication_endpoint"
        case deviceAuthorizationEndpoint = "device_authorization_endpoint"
        case pushedAuthorizationRequestEndpoint = "pushed_authorization_request_endpoint"
        case requirePushedAuthorizationRequests = "require_pushed_authorization_requests"
    }
}

/// An OAuth error a form request answered with (RFC 6749 section 5.2), with the HTTP status.
struct OAuthFailure: Error {
    let status: Int
    let error: String?
    let description: String?
}

extension ThunderIDClient {
    /// The organization unit identifier as one path segment: a slash in it is encoded, so it cannot add one.
    static func organizationUnitSegment(_ ouId: String) throws -> String {
        let trimmed = ouId.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: ManagementPath.allowed) else {
            throw ThunderIDError(code: .invalidInput, message: "An organization unit identifier is required")
        }
        return encoded
    }

    /// `{baseUrl}{path}`, or `{baseUrl}/ou/{ouId}{path}` for a sign-in bounded to an organization unit.
    func oauthURL(_ path: String, organizationUnitId: String?, config: ThunderIDConfig) throws -> String {
        let base = config.baseUrl.hasSuffix("/") ? String(config.baseUrl.dropLast()) : config.baseUrl
        guard let ouId = organizationUnitId else { return base + path }
        return "\(base)/ou/\(try Self.organizationUnitSegment(ouId))\(path)"
    }

    /// Reads the server's metadata once and keeps it for the life of the client.
    func serverMetadata() async throws -> ServerMetadata {
        if let metadata = cachedServerMetadata { return metadata }
        let config = try requireConfig()
        let base = config.baseUrl.hasSuffix("/") ? String(config.baseUrl.dropLast()) : config.baseUrl
        guard let url = URL(string: base + "/.well-known/openid-configuration"), let httpClient else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Could not build the discovery URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.assumesHTTP3Capable = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await httpClient.rawData(for: request)
        guard (200...299).contains(response.statusCode) else {
            throw ThunderIDError(code: .serverError, message: "Could not read the server metadata")
        }
        do {
            let metadata = try JSONDecoder().decode(ServerMetadata.self, from: data)
            cachedServerMetadata = metadata
            return metadata
        } catch {
            throw ThunderIDError(
                code: .unknownError,
                message: "Could not read the server metadata",
                underlyingError: error
            )
        }
    }

    /// Posts `form` URL-encoded to an OAuth endpoint and decodes the answer. Neither the request nor the
    /// response is logged: both can carry a credential (a code, a device code, a token).
    /// Throws ``OAuthFailure`` for an error answer, so a caller can read the OAuth error code.
    func postForm<T: Decodable>(_ url: String, form: [(String, String)]) async throws -> T {
        guard let target = URL(string: url), target.scheme == "https", let httpClient else {
            throw ThunderIDError(code: .invalidConfiguration, message: "OAuth endpoint URL must use HTTPS")
        }
        var request = URLRequest(url: target)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(form).utf8)
        let (data, response) = try await httpClient.rawData(for: request)
        guard (200...299).contains(response.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw OAuthFailure(
                status: response.statusCode,
                error: body?["error"] as? String,
                description: body?["error_description"] as? String
            )
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ThunderIDError(code: .unknownError, message: "Failed to decode response", underlyingError: error)
        }
    }

    /// `application/x-www-form-urlencoded`, with every reserved character encoded.
    static func formEncode(_ form: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = form.map { name, value in
            let key = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
            let val = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(val)"
        }
        return pairs.joined(separator: "&")
    }

    /// Maps an OAuth error answer to the SDK's error. `unauthorized_client` from an endpoint qualified by
    /// an organization unit means the unit does not exist or the application cannot be used from it.
    static func mapOAuthFailure(_ failure: OAuthFailure, organizationUnitId: String? = nil) -> ThunderIDError {
        let message = failure.description ?? failure.error ?? "OAuth request failed with status \(failure.status)"
        let serverError = failure.error.map {
            ServerError(code: $0, message: failure.description.map { ServerErrorMessage(defaultValue: $0) })
        }
        let code: ThunderIDErrorCode
        switch failure.error {
        case "unauthorized_client" where organizationUnitId != nil: code = .organizationUnitUnavailable
        case "invalid_grant": code = .invalidGrant
        case "access_denied": code = .authorizationDenied
        case "expired_token": code = .authorizationExpired
        case "invalid_client": code = .authenticationFailed
        case "invalid_request", "invalid_scope", "invalid_target": code = .invalidInput
        default:
            code = failure.status >= 500 ? .serverError : .authenticationFailed
        }
        return ThunderIDError(code: code, message: message, serverError: serverError)
    }

    /// The client identifier the OAuth requests send, which redirect mode requires.
    func requireClientId(_ config: ThunderIDConfig, for operation: String) throws -> String {
        guard let clientId = config.clientId, !clientId.isEmpty else {
            throw ThunderIDError(code: .invalidConfiguration, message: "clientId is required for \(operation)")
        }
        return clientId
    }
}
