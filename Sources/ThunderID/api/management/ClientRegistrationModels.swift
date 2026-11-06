// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The client metadata sent to register a client (RFC 7591) or to replace its registration (RFC 7592).
/// It is sent in the protocol's snake_case names.
public struct ClientRegistrationRequest: Codable {
    /// The organization unit to associate the client with.
    public var ouId: String?
    public var redirectUris: [String]
    public var postLogoutRedirectUris: [String]?
    public var backchannelLogoutUri: String?
    public var grantTypes: [String]?
    public var responseTypes: [String]?
    public var clientName: String?
    public var clientUri: String?
    public var logoUri: String?
    /// `client_secret_basic`, `client_secret_post`, `private_key_jwt` or `none`.
    public var tokenEndpointAuthMethod: String?
    public var jwksUri: String?
    public var jwks: [String: AnyCodable]?
    /// Space-separated scopes.
    public var scope: String?
    public var contacts: [String]?
    public var tosUri: String?
    public var policyUri: String?
    public var requirePushedAuthorizationRequests: Bool?
    public var userinfoSignedResponseAlg: String?
    public var userinfoEncryptedResponseAlg: String?
    public var userinfoEncryptedResponseEnc: String?
    public var idTokenSignedResponseAlg: String?
    public var idTokenEncryptedResponseAlg: String?
    public var idTokenEncryptedResponseEnc: String?

    public init(
        redirectUris: [String],
        ouId: String? = nil,
        grantTypes: [String]? = nil,
        responseTypes: [String]? = nil,
        clientName: String? = nil,
        tokenEndpointAuthMethod: String? = nil,
        scope: String? = nil
    ) {
        self.redirectUris = redirectUris
        self.ouId = ouId
        self.grantTypes = grantTypes
        self.responseTypes = responseTypes
        self.clientName = clientName
        self.tokenEndpointAuthMethod = tokenEndpointAuthMethod
        self.scope = scope
    }

    private enum CodingKeys: String, CodingKey {
        case ouId = "ou_id"
        case redirectUris = "redirect_uris"
        case postLogoutRedirectUris = "post_logout_redirect_uris"
        case backchannelLogoutUri = "backchannel_logout_uri"
        case grantTypes = "grant_types"
        case responseTypes = "response_types"
        case clientName = "client_name"
        case clientUri = "client_uri"
        case logoUri = "logo_uri"
        case tokenEndpointAuthMethod = "token_endpoint_auth_method"
        case jwksUri = "jwks_uri"
        case jwks
        case scope
        case contacts
        case tosUri = "tos_uri"
        case policyUri = "policy_uri"
        case requirePushedAuthorizationRequests = "require_pushed_authorization_requests"
        case userinfoSignedResponseAlg = "userinfo_signed_response_alg"
        case userinfoEncryptedResponseAlg = "userinfo_encrypted_response_alg"
        case userinfoEncryptedResponseEnc = "userinfo_encrypted_response_enc"
        case idTokenSignedResponseAlg = "id_token_signed_response_alg"
        case idTokenEncryptedResponseAlg = "id_token_encrypted_response_alg"
        case idTokenEncryptedResponseEnc = "id_token_encrypted_response_enc"
    }
}

/// A dynamically registered client, as the server holds it. Read in the protocol's snake_case names.
public struct ClientRegistration: Codable {
    public let clientId: String
    /// The client's secret. Returned only by ``ClientRegistrationsAPI/register(_:fetcher:)``: the server
    /// stores it write-only, so it is `nil` on every later read or update. Never log it.
    public let clientSecret: String?
    /// When the secret expires, as a Unix timestamp, or `0` when it never does.
    public let clientSecretExpiresAt: Int64
    /// The internal application ID.
    public let appId: String?
    public let redirectUris: [String]?
    public let postLogoutRedirectUris: [String]?
    public let backchannelLogoutUri: String?
    public let grantTypes: [String]?
    public let responseTypes: [String]?
    public let clientName: String?
    public let clientUri: String?
    public let logoUri: String?
    public let tokenEndpointAuthMethod: String?
    public let jwksUri: String?
    public let jwks: [String: AnyCodable]?
    public let scope: String?
    public let contacts: [String]?
    public let tosUri: String?
    public let policyUri: String?
    public let requirePushedAuthorizationRequests: Bool?
    public let userinfoSignedResponseAlg: String?
    public let userinfoEncryptedResponseAlg: String?
    public let userinfoEncryptedResponseEnc: String?
    public let idTokenSignedResponseAlg: String?
    public let idTokenEncryptedResponseAlg: String?
    public let idTokenEncryptedResponseEnc: String?

    private enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case clientSecretExpiresAt = "client_secret_expires_at"
        case appId = "app_id"
        case redirectUris = "redirect_uris"
        case postLogoutRedirectUris = "post_logout_redirect_uris"
        case backchannelLogoutUri = "backchannel_logout_uri"
        case grantTypes = "grant_types"
        case responseTypes = "response_types"
        case clientName = "client_name"
        case clientUri = "client_uri"
        case logoUri = "logo_uri"
        case tokenEndpointAuthMethod = "token_endpoint_auth_method"
        case jwksUri = "jwks_uri"
        case jwks
        case scope
        case contacts
        case tosUri = "tos_uri"
        case policyUri = "policy_uri"
        case requirePushedAuthorizationRequests = "require_pushed_authorization_requests"
        case userinfoSignedResponseAlg = "userinfo_signed_response_alg"
        case userinfoEncryptedResponseAlg = "userinfo_encrypted_response_alg"
        case userinfoEncryptedResponseEnc = "userinfo_encrypted_response_enc"
        case idTokenSignedResponseAlg = "id_token_signed_response_alg"
        case idTokenEncryptedResponseAlg = "id_token_encrypted_response_alg"
        case idTokenEncryptedResponseEnc = "id_token_encrypted_response_enc"
    }
}

/// The body of an RFC 7592 update: the client metadata with the `client_id` of the client it replaces.
struct ClientRegistrationUpdate: Encodable {
    let clientId: String
    let metadata: ClientRegistrationRequest
    /// The client's current secret, which the server only checks against the one it holds and never stores.
    let clientSecret: String?

    private enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
    }

    func encode(to encoder: Encoder) throws {
        try metadata.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientId, forKey: .clientId)
        try container.encodeIfPresent(clientSecret, forKey: .clientSecret)
    }
}

// The secret stays out of `print`, string interpolation and `dump`, so logging a registration cannot leak it.
extension ClientRegistration: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "ClientRegistration(clientId: \(clientId), clientName: \(clientName ?? "nil"), "
            + "clientSecret: \(clientSecret == nil ? "nil" : "***"))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "clientId": clientId,
                "clientSecret": clientSecret == nil ? "nil" : "***",
                "clientSecretExpiresAt": clientSecretExpiresAt,
                "appId": appId as Any,
                "clientName": clientName as Any,
                "redirectUris": redirectUris as Any,
                "grantTypes": grantTypes as Any
            ],
            displayStyle: .struct
        )
    }
}
