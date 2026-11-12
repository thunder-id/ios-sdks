// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The parts of the server's OpenID provider metadata (`/.well-known/openid-configuration`) the client
/// reads: the issuer, where the endpoints are, and whether authorization requests must be pushed.
struct ServerMetadata: Decodable {
    let issuer: String?
    let authorizationEndpoint: String?
    let tokenEndpoint: String?
    let jwksUri: String?
    let userinfoEndpoint: String?
    let revocationEndpoint: String?
    let backchannelAuthenticationEndpoint: String?
    let deviceAuthorizationEndpoint: String?
    let pushedAuthorizationRequestEndpoint: String?
    let requirePushedAuthorizationRequests: Bool?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case jwksUri = "jwks_uri"
        case userinfoEndpoint = "userinfo_endpoint"
        case revocationEndpoint = "revocation_endpoint"
        case backchannelAuthenticationEndpoint = "backchannel_authentication_endpoint"
        case deviceAuthorizationEndpoint = "device_authorization_endpoint"
        case pushedAuthorizationRequestEndpoint = "pushed_authorization_request_endpoint"
        case requirePushedAuthorizationRequests = "require_pushed_authorization_requests"
    }
}

/// The parts of a client that hold and check its tokens.
struct TokenHandling {
    let keys: JWKSCache
    let validator: TokenValidator
    let refresher: TokenRefresher
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

    /// An endpoint of the redirect sign-in: the HTTPS URL `metadata` advertises at `keyPath`, or
    /// `{baseUrl}{path}` when there is no metadata or it names none. A ThunderID server advertises exactly
    /// those paths; another OpenID provider advertises its own, so `baseUrl` can be its issuer.
    func endpoint(
        _ keyPath: KeyPath<ServerMetadata, String?>,
        in metadata: ServerMetadata?,
        fallback path: String,
        config: ThunderIDConfig
    ) throws -> String {
        if let advertised = metadata?[keyPath: keyPath], URL(string: advertised)?.scheme == "https" {
            return advertised
        }
        return try oauthURL(path, organizationUnitId: nil, config: config)
    }

    /// Where a redirect sign-in authorizes: the unit's `{baseUrl}/ou/{ouId}/oauth2/authorize` for a sign-in
    /// bounded to an organization unit, otherwise the advertised `authorization_endpoint` when the metadata
    /// has been read, and `{baseUrl}/oauth2/authorize` when it has not.
    func authorizationEndpoint(organizationUnitId: String?, config: ThunderIDConfig) throws -> String {
        if organizationUnitId != nil {
            return try oauthURL("/oauth2/authorize", organizationUnitId: organizationUnitId, config: config)
        }
        return try endpoint(
            \.authorizationEndpoint,
            in: cachedServerMetadata,
            fallback: "/oauth2/authorize",
            config: config
        )
    }

    /// ``endpoint(_:in:fallback:config:)`` with the server's metadata, read when it is not yet. Metadata that
    /// cannot be read falls back to the path, and is read again next time.
    func discoveredEndpoint(_ keyPath: KeyPath<ServerMetadata, String?>, fallback path: String) async throws -> URL {
        let config = try requireConfig()
        let metadata = try? await serverMetadata()
        let value = try endpoint(keyPath, in: metadata, fallback: path, config: config)
        guard let url = URL(string: value) else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Invalid URL: \(value)")
        }
        return url
    }

    /// A ``discoveredEndpoint(_:fallback:)`` for a component the client owns. It holds the client weakly.
    func discoveredEndpointProvider(
        _ keyPath: KeyPath<ServerMetadata, String?>,
        fallback path: String
    ) -> () async throws -> URL {
        { [weak self] in
            guard let self else { throw ThunderIDError(code: .sdkNotInitialized, message: "Not initialized") }
            return try await self.discoveredEndpoint(keyPath, fallback: path)
        }
    }

    /// The key set, ID token validator and token refresher of a client. The keys, the token endpoint and the
    /// issuer come from the server's metadata, so `baseUrl` can be any OpenID provider's issuer; a ThunderID
    /// server advertises the same paths used when there is none.
    func makeTokenHandling(
        http: HTTPClient,
        tokenStore: TokenStore,
        config: ThunderIDConfig
    ) -> TokenHandling {
        let jwks = discoveredEndpointProvider(\.jwksUri, fallback: "/oauth2/jwks")
        let keys = JWKSCache(httpClient: http, endpoint: jwks)
        let validator = TokenValidator(jwksCache: keys, config: config) { [weak self] in
            await self?.expectedIssuer()
        }
        let refresher = TokenRefresher(
            httpClient: http,
            tokenStore: tokenStore,
            endpoint: discoveredEndpointProvider(\.tokenEndpoint, fallback: "/oauth2/token")
        )
        return TokenHandling(keys: keys, validator: validator, refresher: refresher)
    }

    static let discoverySuffix = "/.well-known/openid-configuration"

    /// Where the server's metadata is read: `endpoints.wellKnown`, or `{baseUrl}/.well-known/openid-configuration`.
    static func discoveryURL(_ config: ThunderIDConfig) -> String {
        if let wellKnown = config.endpoints.wellKnown { return wellKnown }
        let base = config.baseUrl.hasSuffix("/") ? String(config.baseUrl.dropLast()) : config.baseUrl
        return base + discoverySuffix
    }

    /// The issuer an ID token must name (OpenID Connect Discovery 1.0 section 4.3). The discovery base is
    /// `endpoints.wellKnown` without its `/.well-known/openid-configuration` suffix, or `baseUrl`. When the
    /// metadata's issuer is the discovery base, give or take one trailing slash, it is that issuer exactly, so
    /// a provider whose issuer ends with `/` is matched; otherwise, and when the metadata cannot be read, the
    /// discovery base. A `wellKnown` without the standard suffix was chosen by the app, so the token must name
    /// the issuer its metadata declares, and `nil` (no token is accepted) when that cannot be read.
    func expectedIssuer() async -> String? {
        guard let config = try? requireConfig() else { return nil }
        let advertised = (try? await serverMetadata())?.issuer.flatMap { $0.isEmpty ? nil : $0 }
        let discoveryBase: String
        if let wellKnown = config.endpoints.wellKnown {
            guard wellKnown.hasSuffix(Self.discoverySuffix) else { return advertised }
            discoveryBase = String(wellKnown.dropLast(Self.discoverySuffix.count))
        } else {
            discoveryBase = config.baseUrl
        }
        let trimmed: (String) -> String = { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
        guard let advertised, trimmed(advertised) == trimmed(discoveryBase) else { return discoveryBase }
        return advertised
    }

    /// Reads the server's metadata once and keeps it for the life of the client.
    func serverMetadata() async throws -> ServerMetadata {
        if let metadata = cachedServerMetadata { return metadata }
        let config = try requireConfig()
        guard let url = URL(string: Self.discoveryURL(config)), let httpClient else {
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
