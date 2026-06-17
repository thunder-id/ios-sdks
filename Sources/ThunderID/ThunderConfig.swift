import Foundation

/// Configuration for the ThunderID SDK.
public struct ThunderIDConfig {
    // MARK: - Core
    public let baseUrl: String
    public let clientId: String?

    // MARK: - Redirect URIs
    public var afterSignInUrl: String?
    public var afterSignOutUrl: String?
    public var signInUrl: String?
    public var signUpUrl: String?

    // MARK: - OAuth2 / OIDC
    public var scopes: [String]
    public var clientSecret: String?
    public var signInOptions: [String: Any]
    public var signOutOptions: [String: Any]
    public var signUpOptions: [String: Any]

    // MARK: - Application Identity
    public var applicationId: String?
    public var organizationHandle: String?

    // MARK: - Token Validation
    public var tokenValidation: TokenValidationConfig

    // MARK: - Storage & Platform
    public var storage: StorageAdapter?
    public var instanceId: Int?

    public init(
        baseUrl: String,
        clientId: String? = nil,
        scopes: [String] = ["openid"],
        afterSignInUrl: String? = nil,
        afterSignOutUrl: String? = nil,
        signInUrl: String? = nil,
        signUpUrl: String? = nil,
        clientSecret: String? = nil,
        signInOptions: [String: Any] = [:],
        signOutOptions: [String: Any] = [:],
        signUpOptions: [String: Any] = [:],
        applicationId: String? = nil,
        organizationHandle: String? = nil,
        tokenValidation: TokenValidationConfig = .init(),
        storage: StorageAdapter? = nil,
        instanceId: Int? = nil
    ) {
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.scopes = scopes
        self.afterSignInUrl = afterSignInUrl
        self.afterSignOutUrl = afterSignOutUrl
        self.signInUrl = signInUrl
        self.signUpUrl = signUpUrl
        self.clientSecret = clientSecret
        self.signInOptions = signInOptions
        self.signOutOptions = signOutOptions
        self.signUpOptions = signUpOptions
        self.applicationId = applicationId
        self.organizationHandle = organizationHandle
        self.tokenValidation = tokenValidation
        self.storage = storage
        self.instanceId = instanceId
    }
}

public struct TokenValidationConfig {
    public var validate: Bool
    public var validateIssuer: Bool
    public var clockTolerance: Int

    public init(validate: Bool = true, validateIssuer: Bool = true, clockTolerance: Int = 0) {
        self.validate = validate
        self.validateIssuer = validateIssuer
        self.clockTolerance = clockTolerance
    }
}
