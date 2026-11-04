// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The answer of the pushed authorization request endpoint (RFC 9126 section 2.2).
struct PushedAuthorizationResponse: Decodable {
    let requestUri: String
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case requestUri = "request_uri"
        case expiresIn = "expires_in"
    }
}

public extension ThunderIDClient {
    /// Redirect-based sign-in: returns the authorization URL to open in `ASWebAuthenticationSession`, as
    /// ``buildSignInURL(options:)`` does, pushing the request first when that is asked for.
    ///
    /// When ``ThunderIDConfig/pushedAuthorizationRequests`` is on, or the server's metadata sets
    /// `require_pushed_authorization_requests`, the authorization request is posted to `/oauth2/par`
    /// (RFC 9126) and the URL carries only `client_id` and the returned `request_uri`. Otherwise it is the
    /// URL ``buildSignInURL(options:)`` builds. A unit-bounded sign-in
    /// (``SignInOptions/organizationUnitId``) authorizes at that unit's authorization endpoint either way.
    func signInURL(options: SignInOptions? = nil) async throws -> URL {
        let config = try requireConfig()
        if backend != nil { return try buildSignInURL(options: options) }
        guard try await shouldPushAuthorizationRequest(config) else {
            return try buildSignInURL(options: options)
        }
        let clientId = try requireClientId(config, for: "redirect sign-in")
        let metadata = try? await serverMetadata()
        let fallback = try oauthURL("/oauth2/par", organizationUnitId: nil, config: config)
        let parEndpoint = metadata?.pushedAuthorizationRequestEndpoint ?? fallback
        let parameters = authorizationParameters(clientId: clientId, options: options, config: config)
        let form = parameters.compactMap { item in item.value.map { (item.name, $0) } }
        let pushed: PushedAuthorizationResponse
        do {
            pushed = try await postForm(parEndpoint, form: form)
        } catch let failure as OAuthFailure {
            pkceManager.clearVerifier()
            throw Self.mapOAuthFailure(failure)
        }
        let ouId = options?.organizationUnitId
        let authorize = try oauthURL("/oauth2/authorize", organizationUnitId: ouId, config: config)
        guard var components = URLComponents(string: authorize) else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Could not build authorize URL")
        }
        components.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "request_uri", value: pushed.requestUri)
        ]
        guard let url = components.url else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Could not build authorize URL")
        }
        pendingOrganizationUnitId = ouId
        return url
    }
}

extension ThunderIDClient {
    /// Whether the authorization request is pushed: the app asks for it, or the server requires it. The
    /// server's metadata is read only when the app does not ask, and an unreadable one requires nothing.
    func shouldPushAuthorizationRequest(_ config: ThunderIDConfig) async throws -> Bool {
        if config.pushedAuthorizationRequests { return true }
        let metadata = try? await serverMetadata()
        return metadata?.requirePushedAuthorizationRequests == true
    }
}
