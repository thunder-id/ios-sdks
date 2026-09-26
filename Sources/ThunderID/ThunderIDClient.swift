// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// ThunderID SDK client — Platform layer implementation of the full IAMClient interface (spec §7.1).
public final class ThunderIDClient {
    private var config: ThunderIDConfig?
    private var httpClient: HTTPClient?
    private var tokenStore: TokenStore?
    private var tokenRefresher: TokenRefresher?
    private var tokenValidator: TokenValidator?
    private var jwksCache: JWKSCache?
    private var flowClient: FlowExecutionClient?
    private var pkceManager = PKCEManager()
    private var _isLoading: Bool = false
    private var currentUser: User?

    public init() {}

    // MARK: - Lifecycle

    public func initialize(config: ThunderIDConfig, storage: StorageAdapter? = nil) async throws -> Bool {
        try await initialize(config: config, storage: storage, session: nil)
    }

    /// `session` is a test-only seam (`@testable`): it lets a test substitute a `URLProtocol`-stubbed
    /// session for the pinned one `initialize(config:storage:)` builds by default, so the HTTP layer
    /// can be exercised without a real network. Public callers always go through the two-argument
    /// overload above, which passes `nil` and keeps today's behavior unchanged.
    func initialize(config: ThunderIDConfig, storage: StorageAdapter?, session: URLSession?) async throws -> Bool {
        guard self.config == nil else {
            throw ThunderIDError(code: .alreadyInitialized, message: "SDK is already initialized")
        }
        try validateConfig(config)
        self.config = config
        let adapter = storage ?? config.storage ?? KeychainStorageAdapter(service: "dev.\(config.vendor).sdk")
        let http = HTTPClient(baseUrl: config.baseUrl, session: session)
        tokenStore = TokenStore(storage: adapter)
        jwksCache = JWKSCache(httpClient: http)
        tokenValidator = TokenValidator(jwksCache: jwksCache!, config: config)
        tokenRefresher = TokenRefresher(httpClient: http, tokenStore: tokenStore!)
        flowClient = FlowExecutionClient(httpClient: http)
        http.setAccessTokenProvider { [weak self] in
            guard let self, let config = self.config else {
                throw ThunderIDError(code: .sdkNotInitialized, message: "Not initialized")
            }
            return try await self.tokenRefresher!.getAccessToken(clientId: config.clientId)
        }
        httpClient = http
        return true
    }

    public func reInitialize(baseUrl: String? = nil, clientId: String? = nil) async throws -> Bool {
        guard var current = config else {
            throw ThunderIDError(code: .sdkNotInitialized, message: "SDK not initialized")
        }
        if let baseUrl { current = ThunderIDConfig(baseUrl: baseUrl, clientId: current.clientId) }
        config = nil
        return try await initialize(config: current)
    }

    public func getConfiguration() throws -> ThunderIDConfig {
        guard let config else { throw ThunderIDError(code: .sdkNotInitialized, message: "SDK not initialized") }
        return config
    }

    // MARK: - Authentication

    /// App-native sign-in via Flow Execution API (spec §6.1 app-native mode).
    public func signIn(
        payload: EmbeddedSignInPayload,
        request: EmbeddedFlowRequestConfig,
        sessionId: String? = nil
    ) async throws -> EmbeddedFlowResponse {
        try requireInitialized()
        _isLoading = true
        defer { _isLoading = false }
        let response: EmbeddedFlowResponse
        if let flowId = payload.flowId {
            response = try await flowClient!.submit(
                flowId: flowId,
                actionId: payload.actionId,
                inputs: payload.inputs,
                challengeToken: payload.challengeToken
            )
        } else {
            response = try await flowClient!.initiate(
                applicationId: request.applicationId,
                flowType: request.flowType,
                attestationToken: try await attestationToken()
            )
        }
        try establishSessionIfNeeded(from: response)
        return response
    }

    /// Redirect-based sign-in: returns the authorization URL to open in ASWebAuthenticationSession.
    /// The caller is responsible for handling the redirect callback.
    public func buildSignInURL(options: SignInOptions? = nil) throws -> URL {
        let cfg = try requireConfig()
        guard let clientId = cfg.clientId else {
            throw ThunderIDError(code: .invalidConfiguration, message: "clientId required for redirect mode")
        }
        let (_, challenge) = pkceManager.generate()
        var components = URLComponents(string: cfg.baseUrl + "/oauth2/authorize")!
        var params: [URLQueryItem] = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: cfg.afterSignInUrl ?? ""),
            .init(name: "scope", value: cfg.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256")
        ]
        if let prompt = options?.prompt { params.append(.init(name: "prompt", value: prompt)) }
        if let hint = options?.loginHint { params.append(.init(name: "login_hint", value: hint)) }
        if let fidp = options?.fidp { params.append(.init(name: "fidp", value: fidp)) }
        for (key, val) in cfg.signInOptions { params.append(.init(name: key, value: "\(val)")) }
        components.queryItems = params
        guard let url = components.url else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Could not build authorize URL")
        }
        return url
    }

    /// Exchanges the authorization code received from the redirect callback for tokens.
    public func handleRedirectCallback(url: URL) async throws -> User {
        let cfg = try requireConfig()
        guard let clientId = cfg.clientId else {
            throw ThunderIDError(code: .invalidConfiguration, message: "clientId required")
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw ThunderIDError(code: .invalidGrant, message: "Authorization code missing from callback URL")
        }
        guard let verifier = pkceManager.codeVerifier else {
            throw ThunderIDError(
                code: .invalidGrant,
                message: "PKCE verifier not found; ensure signIn was called first"
            )
        }
        defer { pkceManager.clearVerifier() }
        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientId,
            "redirect_uri": cfg.afterSignInUrl ?? "",
            "code_verifier": verifier
        ]
        let tokenResponse: TokenResponse = try await httpClient!.post(
            path: "/oauth2/token",
            body: body,
            requiresAuth: false
        )
        if let idToken = tokenResponse.idToken {
            try await tokenValidator?.validate(idToken: idToken, nonce: nil)
        }
        try tokenStore!.save(tokenResponse)
        return try await getUser()
    }

    public func signOut(options: SignOutOptions? = nil, sessionId: String? = nil) async throws -> String {
        try requireInitialized()
        _isLoading = true
        defer { _isLoading = false }
        if let refreshToken = tokenStore?.refreshToken(), let clientId = config?.clientId {
            let body: [String: Any] = [
                "token": refreshToken,
                "client_id": clientId
            ]
            if let httpClient {
                let _: EmptyResponse? = try? await httpClient.post(
                    path: "/oauth2/revoke",
                    body: body,
                    requiresAuth: false
                )
            }
        }
        tokenStore?.clear()
        currentUser = nil
        return config?.afterSignOutUrl ?? "/"
    }

    public func isSignedIn(sessionId: String? = nil) async throws -> Bool {
        try requireInitialized()
        return tokenStore?.accessToken() != nil
    }

    public func isLoading() -> Bool { _isLoading }

    // MARK: - Registration

    /// App-native sign-up via Flow Execution API (spec §6.2).
    public func signUp(
        payload: EmbeddedSignInPayload? = nil,
        request: EmbeddedFlowRequestConfig? = nil
    ) async throws -> EmbeddedFlowResponse {
        try requireInitialized()
        let appId = request?.applicationId ?? config?.applicationId ?? ""
        let response: EmbeddedFlowResponse
        if let payload, let flowId = payload.flowId {
            response = try await flowClient!.submit(
                flowId: flowId,
                actionId: payload.actionId,
                inputs: payload.inputs,
                challengeToken: payload.challengeToken
            )
        } else {
            response = try await flowClient!.initiate(
                applicationId: appId,
                flowType: request?.flowType ?? .registration,
                attestationToken: try await attestationToken()
            )
        }
        try establishSessionIfNeeded(from: response)
        return response
    }

    // MARK: - Token & Session

    public func getAccessToken(sessionId: String? = nil) async throws -> String {
        try requireInitialized()
        return try await tokenRefresher!.getAccessToken(clientId: config?.clientId)
    }

    public func decodeJwtToken<R: Decodable>(_ token: String) throws -> R {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3,
              let data = Data(base64URLEncoded: parts[1]) else {
            throw ThunderIDError(code: .invalidInput, message: "Invalid JWT format")
        }
        return try JSONDecoder().decode(R.self, from: data)
    }

    public func exchangeToken(
        config: TokenExchangeRequestConfig, sessionId: String? = nil
    ) async throws -> TokenResponse {
        try requireInitialized()
        var body: [String: Any] = [
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "subject_token": config.subjectToken,
            "subject_token_type": config.subjectTokenType
        ]
        if let clientId = self.config?.clientId ?? self.config?.applicationId, !clientId.isEmpty {
            body["client_id"] = clientId
        }
        if let type = config.requestedTokenType { body["requested_token_type"] = type }
        if let aud = config.audience { body["audience"] = aud }
        let response: TokenResponse = try await httpClient!.post(
            path: "/oauth2/token",
            body: body,
            requiresAuth: false
        )
        try tokenStore!.save(response)
        return response
    }

    public func clearSession(sessionId: String? = nil) {
        tokenStore?.clear()
        currentUser = nil
    }

    // MARK: - User & Profile

    public func getUser(options: [String: Any]? = nil) async throws -> User {
        try requireInitialized()
        if let user = currentUser { return user }
        if let token = tokenStore?.accessToken(),
           let claims = try? decodeJwtToken(token) as [String: AnyCodable],
           let sub = claims["sub"]?.value as? String, !sub.isEmpty {
            let user = User(claims: claims)
            currentUser = user
            return user
        }
        let user: User = try await httpClient!.get(path: "/oauth2/userinfo")
        currentUser = user
        return user
    }

    public func getUserProfile(options: [String: Any]? = nil) async throws -> UserProfile {
        try requireInitialized()
        return try await httpClient!.get(path: "/users/me")
    }

    public func getUserSchema() async throws -> [String: AttributeSchema] {
        try requireInitialized()
        // The endpoint wraps the attribute map in a single "schema" key.
        let response: [String: [String: AttributeSchema]] = try await httpClient!.get(path: "/users/me/meta")
        return response["schema"] ?? [:]
    }

    public func updateUserProfile(payload: [String: Any]) async throws -> UserProfile {
        try requireInitialized()
        return try await httpClient!.put(path: "/users/me", body: ["attributes": payload])
    }

    /// Changes one of the signed-in user's own credentials via `POST /users/me/update-credentials`.
    ///
    /// The self-service write path does not verify the account's existing value today, so this
    /// call collects only the new value, matching the Android/React/Vue SDKs.
    public func updateUserCredentials(attribute: String = "password", newValue: String) async throws {
        try requireInitialized()
        let _: EmptyResponse = try await httpClient!.post(
            path: "/users/me/update-credentials",
            body: ["attributes": [attribute: newValue]]
        )
    }

    /// Overrides the cached user, e.g. after merging in freshly-fetched `/users/me` attributes.
    public func setCachedUser(_ user: User) {
        currentUser = user
    }

    // MARK: - Flow Meta

    public func getFlowMeta(applicationId: String, language: String = "en-US") async throws -> [String: Any] {
        try requireInitialized()
        let path = "/flow/meta?id=\(applicationId)&type=APP&language=\(language)"
        let result: [String: AnyCodable] = try await httpClient!.get(path: path, requiresAuth: false)
        return result.mapValues { deepUnwrap($0.value) }
    }

    // MARK: - Private helpers

    @discardableResult
    private func requireInitialized() throws -> ThunderIDConfig {
        guard let config else {
            throw ThunderIDError(code: .sdkNotInitialized, message: "Call initialize() before using the SDK")
        }
        return config
    }

    private func requireConfig() throws -> ThunderIDConfig {
        guard let config else {
            throw ThunderIDError(code: .sdkNotInitialized, message: "Call initialize() before using the SDK")
        }
        return config
    }

    private func validateConfig(_ config: ThunderIDConfig) throws {
        guard !config.baseUrl.isEmpty else {
            throw ThunderIDError(code: .invalidConfiguration, message: "baseUrl is required")
        }
        guard config.baseUrl.hasPrefix("https://") else {
            throw ThunderIDError(code: .invalidConfiguration, message: "baseUrl must use HTTPS")
        }
        guard !config.attestationEnabled || config.attestationTokenProvider != nil else {
            throw ThunderIDError(
                code: .invalidConfiguration,
                message: "attestationTokenProvider is required when attestationEnabled is true"
            )
        }
    }

    /// Returns the attestation token when enabled, or `nil` otherwise.
    private func attestationToken() async throws -> String? {
        guard let config, config.attestationEnabled else { return nil }
        return try await config.attestationTokenProvider?()
    }

    private func deepUnwrap(_ value: Any) -> Any {
        switch value {
        case let codable as AnyCodable:
            return deepUnwrap(codable.value)
        case let dict as [String: AnyCodable]:
            return dict.mapValues { deepUnwrap($0.value) }
        case let dict as [String: Any]:
            return dict.mapValues { deepUnwrap($0) }
        case let array as [AnyCodable]:
            return array.map { deepUnwrap($0.value) }
        case let array as [Any]:
            return array.map { deepUnwrap($0) }
        default:
            return value
        }
    }

    private func establishSessionIfNeeded(from response: EmbeddedFlowResponse) throws {
        guard response.flowStatus == .complete,
              let assertion = response.assertion,
              !assertion.isEmpty else {
            return
        }
        let tokenResponse = TokenResponse(accessToken: assertion, tokenType: "Bearer")
        try tokenStore!.save(tokenResponse)
        if let claims = try? decodeJwtToken(assertion) as [String: AnyCodable] {
            currentUser = User(claims: claims)
        }
    }
}

// MARK: - Management

public extension ThunderIDClient {
    /// Application management operations. Throws until `initialize(config:)` has run.
    var applications: ApplicationsAPI {
        get throws { ApplicationsAPI(transport: try managementTransport("applications", override: \.applications)) }
    }

    /// User management operations. Throws until `initialize(config:)` has run.
    var users: UsersAPI {
        get throws { UsersAPI(transport: try managementTransport("users", override: \.users)) }
    }

    /// Agent management operations. Throws until `initialize(config:)` has run.
    var agents: AgentsAPI {
        get throws { AgentsAPI(transport: try managementTransport("agents", override: \.agents)) }
    }
}

private extension ThunderIDClient {
    func managementTransport(
        _ collection: String,
        override: KeyPath<ThunderIDEndpoints, String?>
    ) throws -> ManagementTransport {
        let config = try requireInitialized()
        guard let httpClient else {
            throw ThunderIDError(code: .sdkNotInitialized, message: "Call initialize() before using the SDK")
        }
        return ManagementTransport(
            httpClient: httpClient,
            collectionUrl: config.endpoints[keyPath: override] ?? "\(config.baseUrl)/\(collection)",
            fetcher: config.fetcher
        )
    }
}

private extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        self.init(base64Encoded: base64)
    }
}
