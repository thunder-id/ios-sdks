// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Options for ``ThunderIDClient/initiateCIBA(options:)`` (CIBA Core 1.0 section 7.1). Exactly one of
/// `loginHint`, `loginHintToken` and `idTokenHint` identifies the user.
public struct CIBAInitiateOptions {
    /// Identifies the user, such as a username, an email address or a phone number.
    public var loginHint: String?
    /// A token carrying a hint about the user. The server does not support it and refuses it.
    public var loginHintToken: String?
    /// An ID token the server issued earlier for the user.
    public var idTokenHint: String?
    /// A short message shown on both devices, so the user can tell the two interactions belong together.
    public var bindingMessage: String?
    /// The lifetime asked for the request, in seconds. The server may give a shorter one.
    public var requestedExpiry: Int?
    /// Space-separated authentication context class references.
    public var acrValues: String?
    /// Authorization details (RFC 9396), each an object with a string `type`. Sent JSON-encoded.
    public var authorizationDetails: [[String: Any]]?

    public init(
        loginHint: String? = nil,
        loginHintToken: String? = nil,
        idTokenHint: String? = nil,
        bindingMessage: String? = nil,
        requestedExpiry: Int? = nil,
        acrValues: String? = nil,
        authorizationDetails: [[String: Any]]? = nil
    ) {
        self.loginHint = loginHint
        self.loginHintToken = loginHintToken
        self.idTokenHint = idTokenHint
        self.bindingMessage = bindingMessage
        self.requestedExpiry = requestedExpiry
        self.acrValues = acrValues
        self.authorizationDetails = authorizationDetails
    }
}

/// The accepted backchannel authentication request (CIBA Core 1.0 section 7.3).
public struct CIBAInitiateResponse: Decodable, Equatable {
    /// Identifies the request. Pass it to ``ThunderIDClient/pollCIBA(authReqId:interval:)``.
    public let authReqId: String
    /// The request's lifetime, in seconds.
    public let expiresIn: Int
    /// The least number of seconds between two polls.
    public let interval: Int

    enum CodingKeys: String, CodingKey {
        case authReqId = "auth_req_id"
        case expiresIn = "expires_in"
        case interval
    }

    public init(authReqId: String, expiresIn: Int, interval: Int) {
        self.authReqId = authReqId
        self.expiresIn = expiresIn
        self.interval = interval
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authReqId = try container.decode(String.self, forKey: .authReqId)
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn) ?? 120
        interval = try container.decodeIfPresent(Int.self, forKey: .interval) ?? 5
    }
}

/// Client-initiated backchannel authentication (CIBA). The SDK runs on a public client, so it supports
/// CIBA only for a client registered with `token_endpoint_auth_method` `none`: it sends `client_id` and no
/// secret. A configuration that holds a `clientSecret` is refused with
/// ``ThunderIDErrorCode/unsupportedOperation``, since an app cannot keep a secret.
public extension ThunderIDClient {
    /// Posts a backchannel authentication request to the server's discovered
    /// `backchannel_authentication_endpoint`, with the configured scopes. Fails with
    /// ``ThunderIDErrorCode/endpointNotAdvertised`` when the server's metadata names none.
    func initiateCIBA(options: CIBAInitiateOptions) async throws -> CIBAInitiateResponse {
        let config = try requireConfig()
        try refuseInBackendMode("initiateCIBA")
        let clientId = try requirePublicClient(config, for: "CIBA")
        let hints = [options.loginHint, options.loginHintToken, options.idTokenHint].compactMap { $0 }
        guard hints.count == 1 else {
            throw ThunderIDError(
                code: .invalidInput,
                message: "Provide exactly one of loginHint, loginHintToken or idTokenHint"
            )
        }
        guard let endpoint = try await serverMetadata().backchannelAuthenticationEndpoint, !endpoint.isEmpty else {
            throw ThunderIDError(
                code: .endpointNotAdvertised,
                message: "The server's metadata names no backchannel_authentication_endpoint"
            )
        }
        var form: [(String, String)] = [("client_id", clientId), ("scope", config.scopes.joined(separator: " "))]
        let optional: [(String, String?)] = [
            ("login_hint", options.loginHint),
            ("login_hint_token", options.loginHintToken),
            ("id_token_hint", options.idTokenHint),
            ("binding_message", options.bindingMessage),
            ("acr_values", options.acrValues),
            ("requested_expiry", options.requestedExpiry.map(String.init)),
            ("authorization_details", try Self.encodeAuthorizationDetails(options.authorizationDetails))
        ]
        form += optional.compactMap { name, value in value.map { (name, $0) } }
        do {
            return try await postForm(endpoint, form: form)
        } catch let failure as OAuthFailure {
            throw Self.mapOAuthFailure(failure)
        }
    }

    /// Polls the token endpoint with the `urn:openid:params:grant-type:ciba` grant until the user approves
    /// or denies the request, waiting at least `interval` seconds between polls and 5 more after each
    /// `slow_down`. On approval it stores the tokens as a sign-in does and returns them. A denial fails
    /// with ``ThunderIDErrorCode/authorizationDenied``, an expired request with
    /// ``ThunderIDErrorCode/authorizationExpired``. Cancelling the calling task stops polling.
    func pollCIBA(authReqId: String, interval: Int) async throws -> TokenResponse {
        let config = try requireConfig()
        try refuseInBackendMode("pollCIBA")
        let clientId = try requirePublicClient(config, for: "CIBA")
        return try await pollTokenEndpoint(interval: interval, config: config, form: [
            ("grant_type", "urn:openid:params:grant-type:ciba"),
            ("auth_req_id", authReqId),
            ("client_id", clientId)
        ])
    }
}

extension ThunderIDClient {
    /// The client identifier, refusing a configuration that holds a client secret: the operation runs only
    /// for a public client, which authenticates with `client_id` alone.
    func requirePublicClient(_ config: ThunderIDConfig, for operation: String) throws -> String {
        if let secret = config.clientSecret, !secret.isEmpty {
            throw ThunderIDError(
                code: .unsupportedOperation,
                message: "\(operation) is supported only for a public client (token_endpoint_auth_method none)"
            )
        }
        return try requireClientId(config, for: operation)
    }

    static func encodeAuthorizationDetails(_ details: [[String: Any]]?) throws -> String? {
        guard let details, !details.isEmpty else { return nil }
        guard JSONSerialization.isValidJSONObject(details),
              let data = try? JSONSerialization.data(withJSONObject: details) else {
            throw ThunderIDError(code: .invalidInput, message: "authorizationDetails must be JSON objects")
        }
        return String(data: data, encoding: .utf8)
    }

    /// Polls the token endpoint (RFC 8628 section 3.5, CIBA Core 1.0 section 7.3) until it issues tokens,
    /// then stores them as a sign-in does.
    func pollTokenEndpoint(
        interval: Int,
        config: ThunderIDConfig,
        form: [(String, String)]
    ) async throws -> TokenResponse {
        let fallback = try oauthURL("/oauth2/token", organizationUnitId: nil, config: config)
        let advertised = try? await serverMetadata().tokenEndpoint
        let endpoint = advertised ?? fallback
        var wait = TimeInterval(max(interval, 1))
        while true {
            try await pollSleep(wait)
            try Task.checkCancellation()
            do {
                let response: TokenResponse = try await postForm(endpoint, form: form)
                if let idToken = response.idToken {
                    try await tokenValidator?.validate(idToken: idToken, nonce: nil)
                }
                try tokenStore!.save(response)
                currentUser = nil
                return response
            } catch let failure as OAuthFailure {
                switch failure.error {
                case "authorization_pending": continue
                case "slow_down": wait += 5
                default: throw Self.mapOAuthFailure(failure)
                }
            }
        }
    }
}
