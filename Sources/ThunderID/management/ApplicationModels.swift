// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The fields of an application that a caller can set. Used to create and to update an application.
public struct ApplicationRequest: Codable {
    public var name: String
    public var description: String?
    public var url: String?
    public var logoUrl: String?
    public var tosUri: String?
    public var policyUri: String?
    public var contacts: [String]?
    public var authFlowId: String?
    public var registrationFlowId: String?
    public var isRegistrationFlowEnabled: Bool?
    public var recoveryFlowId: String?
    public var isRecoveryFlowEnabled: Bool?
    public var signOutFlowId: String?
    public var userAttributes: [String]?
    public var allowedUserTypes: [String]?
    public var allowedAgentTypes: [String]?
    public var themeId: String?
    public var layoutId: String?
    /// One of `browser`, `fullstack`, `mobile`, `m2m`, `mcp`, `custom`.
    public var type: String?
    public var template: String?
    public var flowSecret: String?
    public var inboundAuthConfig: [InboundAuthConfig]?
    public var ouId: String?
    public var assertion: TokenConfig?
    public var attestation: AttestationConfig?
    public var passkeyAllowedOrigins: [String]?
    public var isReadOnly: Bool?

    public init(name: String) {
        self.name = name
    }
}

/// An application registered in ThunderID. Every ``ApplicationRequest`` field is readable directly,
/// e.g. `application.name`.
@dynamicMemberLookup
public struct Application: Codable {
    public let id: String
    public var createdAt: String?
    public var updatedAt: String?
    /// The caller-settable fields, ready to send back through `ApplicationsAPI.update(id:_:)`.
    public var request: ApplicationRequest

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        request = try ApplicationRequest(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try request.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    public subscript<Value>(dynamicMember keyPath: WritableKeyPath<ApplicationRequest, Value>) -> Value {
        get { request[keyPath: keyPath] }
        set { request[keyPath: keyPath] = newValue }
    }
}

/// The summary of an application returned in list responses.
public struct BasicApplication: Codable {
    public let id: String
    public let name: String
    public let description: String?
    public let logoUrl: String?
    public let authFlowId: String?
    public let registrationFlowId: String?
    public let isRegistrationFlowEnabled: Bool?
    public let type: String?
    public let template: String?
    public let isReadOnly: Bool?
    public let clientId: String?
}

/// A page of applications.
public struct ApplicationListResponse: Codable {
    public let totalResults: Int
    public let count: Int
    public let applications: [BasicApplication]
}

/// Inbound authentication configuration of an application.
public struct InboundAuthConfig: Codable {
    /// Currently always `oauth2`.
    public var type: String
    public var config: OAuth2Config

    public init(type: String = "oauth2", config: OAuth2Config) {
        self.type = type
        self.config = config
    }
}

/// OAuth 2.0 / OIDC configuration of an application.
public struct OAuth2Config: Codable {
    public var clientId: String?
    public var clientSecret: String?
    public var redirectUris: [String]?
    public var postLogoutRedirectUris: [String]?
    public var grantTypes: [String]
    public var responseTypes: [String]
    public var tokenEndpointAuthMethod: String?
    public var pkceRequired: Bool?
    public var publicClient: Bool?
    public var scopes: [String]?
    public var token: OAuth2TokenConfig?
    public var userInfo: UserInfoConfig?
    public var scopeClaims: [String: [String]]?
    public var requirePushedAuthorizationRequests: Bool?
    public var certificate: ApplicationCertificate?
    public var acrValues: [String]?

    public init(grantTypes: [String], responseTypes: [String]) {
        self.grantTypes = grantTypes
        self.responseTypes = responseTypes
    }
}

/// A certificate attached to an OAuth 2.0 application, e.g. a JWKS URI.
public struct ApplicationCertificate: Codable {
    public var type: String
    public var value: String?

    public init(type: String, value: String? = nil) {
        self.type = type
        self.value = value
    }
}

/// Base token configuration shared by the tokens an application issues.
public struct TokenConfig: Codable {
    public var validityPeriod: Int
    public var userAttributes: [String]

    public init(validityPeriod: Int, userAttributes: [String]) {
        self.validityPeriod = validityPeriod
        self.userAttributes = userAttributes
    }
}

/// Token settings of an OAuth 2.0 application.
public struct OAuth2TokenConfig: Codable {
    public var accessToken: AccessTokenConfig?
    public var idToken: IDTokenConfig?
    public var refreshToken: RefreshTokenConfig?
    public var idJag: IDJAGConfig?
    public var validityPeriod: Int?
    public var userAttributes: [String]?

    public init() {}
}

/// Access token settings for one kind of subject (a user or the client itself).
public struct AccessTokenSubConfig: Codable {
    public var validityPeriod: Int?
    public var attributes: [String]?

    public init(validityPeriod: Int? = nil, attributes: [String]? = nil) {
        self.validityPeriod = validityPeriod
        self.attributes = attributes
    }
}

/// Access token configuration.
public struct AccessTokenConfig: Codable {
    public var userConfig: AccessTokenSubConfig?
    public var clientConfig: AccessTokenSubConfig?
    public var defaultAudience: String?

    public init() {}
}

/// ID token configuration.
public struct IDTokenConfig: Codable {
    public var validityPeriod: Int?
    public var userAttributes: [String]?
    /// One of `JWT`, `JWE`, `NESTED_JWT`.
    public var responseType: String?
    public var encryptionAlg: String?
    public var encryptionEnc: String?

    public init() {}
}

/// Refresh token configuration.
public struct RefreshTokenConfig: Codable {
    public var validityPeriod: Int

    public init(validityPeriod: Int) {
        self.validityPeriod = validityPeriod
    }
}

/// Identity assertion JWT authorization grant (ID-JAG) configuration.
public struct IDJAGConfig: Codable {
    public var enabled: Bool
    public var allowedAudiences: [String]?
    public var validityPeriod: Int?

    public init(enabled: Bool) {
        self.enabled = enabled
    }
}

/// Userinfo endpoint configuration.
public struct UserInfoConfig: Codable {
    public var userAttributes: [String]?
    /// One of `JSON`, `JWS`, `JWE`, `NESTED_JWT`.
    public var responseType: String?
    public var signingAlg: String?
    public var encryptionAlg: String?
    public var encryptionEnc: String?

    public init() {}
}

/// App attestation configuration. At most one platform can be configured.
public struct AttestationConfig: Codable {
    public var devMode: Bool?
    public var android: AndroidAttestationConfig?
    public var apple: AppleAttestationConfig?

    public init(devMode: Bool? = nil, android: AndroidAttestationConfig? = nil, apple: AppleAttestationConfig? = nil) {
        self.devMode = devMode
        self.android = android
        self.apple = apple
    }
}

/// Android app attestation configuration.
public struct AndroidAttestationConfig: Codable {
    public var packageName: String?
    public var certificateSha256Digests: [String]?
    public var serviceAccountCredentials: String?

    public init() {}
}

/// Apple app attestation configuration.
public struct AppleAttestationConfig: Codable {
    public var teamId: String
    public var bundleId: String

    public init(teamId: String, bundleId: String) {
        self.teamId = teamId
        self.bundleId = bundleId
    }
}
