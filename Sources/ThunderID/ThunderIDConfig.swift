// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

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

    // MARK: - User Profile
    /// Whether user profile attributes come from `/users/me` or only from the OIDC
    /// access-token/userinfo claims.
    public var fetchUserProfile: Bool

    // MARK: - Platform Attestation
    /// When enabled, the token from ``attestationTokenProvider`` is sent as the
    /// `Attestation-Token` header on native flow-initiate requests.
    public var attestationEnabled: Bool
    public var attestationTokenProvider: (() async throws -> String)?

    // MARK: - Token Validation
    public var tokenValidation: TokenValidationConfig

    // MARK: - Session
    /// Behaviour around the session. See ``ThunderIDSessionConfig``.
    public var session: ThunderIDSessionConfig

    // MARK: - Endpoints
    /// Collection URL overrides for the management operations, for a management API that runs on a
    /// different host from `baseUrl`, and the app backend that signs the app in (`endpoints.backend`).
    public var endpoints: ThunderIDEndpoints
    /// HTTP options.
    public var http: ThunderIDHttpConfig

    // MARK: - Storage & Platform
    public var storage: StorageAdapter?
    public var instanceId: Int?

    /// Vendor/brand namespace used to derive default storage identifiers (e.g. Keychain service name).
    /// Override this when white-labeling the SDK under a different brand. Defaults to
    /// `VendorConstants.vendorPrefix` ("thunderid").
    public var vendor: String

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
        fetchUserProfile: Bool = true,
        attestationEnabled: Bool = false,
        attestationTokenProvider: (() async throws -> String)? = nil,
        tokenValidation: TokenValidationConfig = .init(),
        session: ThunderIDSessionConfig = .init(),
        endpoints: ThunderIDEndpoints = .init(),
        http: ThunderIDHttpConfig = .init(),
        storage: StorageAdapter? = nil,
        instanceId: Int? = nil,
        vendor: String = VendorConstants.vendorPrefix
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
        self.fetchUserProfile = fetchUserProfile
        self.attestationEnabled = attestationEnabled
        self.attestationTokenProvider = attestationTokenProvider
        self.tokenValidation = tokenValidation
        self.session = session
        self.endpoints = endpoints
        self.http = http
        self.storage = storage
        self.instanceId = instanceId
        self.vendor = vendor
    }
}

/// Performs an HTTP request. Supply one to route the management operations through your own transport.
/// The request it receives already carries the signed-in user's access token.
public typealias ThunderIDFetcher = (URLRequest) async throws -> (Data, URLResponse)

/// HTTP options.
public struct ThunderIDHttpConfig {
    /// Transport for the management operations. Applies to management operations only. Defaults to
    /// `URLSession`. A fetcher passed to an individual call takes precedence over this one.
    public var fetcher: ThunderIDFetcher?

    public init(fetcher: ThunderIDFetcher? = nil) {
        self.fetcher = fetcher
    }
}

/// Collection URL overrides for the management operations. A `nil` entry falls back to
/// `{baseUrl}/{collection}`. A single resource is addressed as `{collection}/{id}`.
public struct ThunderIDEndpoints {
    public var agents: String?
    /// Defaults to `{baseUrl}/agent-types`.
    public var agentTypes: String?
    public var applications: String?
    /// Defaults to `{baseUrl}/configuration-versions`.
    public var configurationVersions: String?
    public var connections: String?
    /// The design collection, which holds `themes`, `layouts` and `resolve`.
    public var design: String?
    public var export: String?
    public var flows: String?
    public var gateways: String?
    public var groups: String?
    /// The translations collection, which holds `languages`.
    public var i18n: String?
    public var `import`: String?
    /// Defaults to `{baseUrl}/notification-templates`.
    public var notificationTemplates: String?
    /// Defaults to `{baseUrl}/organization-units`.
    public var organizationUnits: String?
    /// Defaults to `{baseUrl}/resource-servers`.
    public var resourceServers: String?
    public var roles: String?
    public var secrets: String?
    /// Defaults to `{baseUrl}/server-config`.
    public var serverConfig: String?
    public var users: String?
    /// Defaults to `{baseUrl}/user-types`.
    public var userTypes: String?
    public var variables: String?
    /// The app backend's auth endpoints. Setting them hands sign-in to the backend: the SDK then signs in,
    /// reads the session, and sends API calls through the backend, and never holds the user's tokens.
    /// `baseUrl` is then the backend's base URL, and API calls go to its proxy
    /// (`{baseUrl}{backend.proxy}`), which maps them to the API. Unset by default.
    public var backend: ThunderIDBackendEndpoints?

    public init(
        agents: String? = nil,
        agentTypes: String? = nil,
        applications: String? = nil,
        configurationVersions: String? = nil,
        connections: String? = nil,
        design: String? = nil,
        export: String? = nil,
        flows: String? = nil,
        gateways: String? = nil,
        groups: String? = nil,
        i18n: String? = nil,
        import: String? = nil,
        notificationTemplates: String? = nil,
        organizationUnits: String? = nil,
        resourceServers: String? = nil,
        roles: String? = nil,
        secrets: String? = nil,
        serverConfig: String? = nil,
        users: String? = nil,
        userTypes: String? = nil,
        variables: String? = nil,
        backend: ThunderIDBackendEndpoints? = nil
    ) {
        self.agents = agents
        self.agentTypes = agentTypes
        self.applications = applications
        self.configurationVersions = configurationVersions
        self.connections = connections
        self.design = design
        self.export = export
        self.flows = flows
        self.gateways = gateways
        self.groups = groups
        self.i18n = i18n
        self.import = `import`
        self.notificationTemplates = notificationTemplates
        self.organizationUnits = organizationUnits
        self.resourceServers = resourceServers
        self.roles = roles
        self.secrets = secrets
        self.serverConfig = serverConfig
        self.users = users
        self.userTypes = userTypes
        self.variables = variables
        self.backend = backend
    }
}

/// Behaviour around the session.
public struct ThunderIDSessionConfig {
    /// How often to ask the app's backend whether the session is still live, in seconds. Only applies when
    /// sign-in runs on a backend (`endpoints.backend`): the backend's check endpoint reports liveness without
    /// refreshing the session or counting as activity, so polling it does not keep an idle session alive.
    /// `0` leaves only the check that runs when the app comes back to the foreground.
    public var checkInterval: TimeInterval

    public init(checkInterval: TimeInterval = 0) {
        self.checkInterval = checkInterval
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
