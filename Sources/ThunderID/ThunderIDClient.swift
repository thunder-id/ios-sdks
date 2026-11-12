// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// ThunderID SDK client — Platform layer implementation of the full IAMClient interface (spec §7.1).
public final class ThunderIDClient {
    private var config: ThunderIDConfig?
    var httpClient: HTTPClient?
    var tokenStore: TokenStore?
    private var tokenRefresher: TokenRefresher?
    var tokenValidator: TokenValidator?
    private var jwksCache: JWKSCache?
    var flowClient: FlowExecutionClient?
    var pkceManager = PKCEManager()
    private var _isLoading: Bool = false
    var currentUser: User?
    /// Set when sign-in runs on the app's backend (`endpoints.backend`), which holds the tokens.
    var backend: BackendClient?
    var backendHttp: BackendHttpClient?
    var signOutListeners: [() -> Void] = []
    /// The server's OpenID provider metadata, read once when an operation first needs it.
    var cachedServerMetadata: ServerMetadata?
    /// The organization unit the redirect sign-in in progress is bounded to: its code is redeemed only at
    /// that unit's token endpoint. Held in memory with the PKCE verifier.
    var pendingOrganizationUnitId: String?
    /// The embedded sign-in flows started bounded to an organization unit. When one completes, its session
    /// replaces the stored one rather than merging into it.
    var boundedFlowIds: Set<String> = []
    /// Waits between polls of the token endpoint. A test seam: tests replace it so polling does not sleep.
    var pollSleep: (TimeInterval) async throws -> Void = { seconds in
        try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
    }

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
        // With sign-in on a backend, `baseUrl` is the backend's, and API paths such as `/users/me` resolve
        // against its proxy, which maps them to the API.
        let backendEndpoints = try config.endpoints.backend.map {
            try ResolvedBackendEndpoints.resolve($0, baseUrl: config.baseUrl)
        }
        self.config = config
        cachedServerMetadata = nil
        let adapter = storage ?? config.storage ?? KeychainStorageAdapter(service: "dev.\(config.vendor).sdk")
        let http = HTTPClient(baseUrl: backendEndpoints?.proxy ?? config.baseUrl, session: session)
        tokenStore = TokenStore(storage: adapter)
        let tokens = makeTokenHandling(http: http, tokenStore: tokenStore!, config: config)
        (jwksCache, tokenValidator, tokenRefresher) = (tokens.keys, tokens.validator, tokens.refresher)
        flowClient = FlowExecutionClient(httpClient: http)
        httpClient = http
        if let backendEndpoints {
            // The backend holds the tokens, so no request carries one: they go through the backend instead.
            setUpBackend(backendEndpoints, config: config, http: http, tokenStore: tokenStore!, session: session)
            return true
        }
        http.setAccessTokenProvider { [weak self] in
            guard let self, let config = self.config else {
                throw ThunderIDError(code: .sdkNotInitialized, message: "Not initialized")
            }
            return try await self.tokenRefresher!.getAccessToken(clientId: config.clientId)
        }
        return true
    }

    public func reInitialize(baseUrl: String? = nil, clientId: String? = nil) async throws -> Bool {
        guard var current = config else {
            throw ThunderIDError(code: .sdkNotInitialized, message: "SDK not initialized")
        }
        if let baseUrl { current = ThunderIDConfig(baseUrl: baseUrl, clientId: current.clientId) }
        tearDownBackend()
        config = nil
        return try await initialize(config: current)
    }

    public func getConfiguration() throws -> ThunderIDConfig {
        guard let config else { throw ThunderIDError(code: .sdkNotInitialized, message: "SDK not initialized") }
        return config
    }

    // MARK: - Authentication

    /// App-native sign-in via Flow Execution API (spec §6.1 app-native mode). The SSO session handles a step
    /// returns are kept, for a later organization unit switch.
    public func signIn(
        payload: EmbeddedSignInPayload,
        request: EmbeddedFlowRequestConfig,
        sessionId: String? = nil
    ) async throws -> EmbeddedFlowResponse {
        try await runSignIn(payload: payload, request: request)
    }

    /// Runs one sign-in step. `flowSessions` go with the request that starts the flow, so the server can
    /// reuse those SSO sessions.
    func runSignIn(
        payload: EmbeddedSignInPayload,
        request: EmbeddedFlowRequestConfig,
        flowSessions: [EmbeddedFlowSessionData] = []
    ) async throws -> EmbeddedFlowResponse {
        try requireInitialized()
        try refuseInBackendMode("Embedded sign-in")
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
            // A unit-bounded sign-in names its unit only on the request that starts an AUTHENTICATION flow.
            let ouId = request.flowType == .authentication ? request.organizationUnitId : nil
            response = try await flowClient!.initiate(
                applicationId: request.applicationId,
                flowType: request.flowType,
                attestationToken: try await attestationToken(),
                organizationUnitId: ouId,
                sessionData: flowSessions
            )
            if ouId != nil, let flowId = response.flowId { boundedFlowIds.insert(flowId) }
        }
        try keepFlowSessions(from: response)
        try establishSessionIfNeeded(from: response)
        return response
    }

    /// Redirect-based sign-in: returns the authorization URL to open in ASWebAuthenticationSession.
    /// The caller is responsible for handling the redirect callback.
    ///
    /// When sign-in runs on the app's backend, it is the backend's sign-in URL, bound to a PKCE challenge
    /// and coming back to `afterSignInUrl` with a one-time `session_code`.
    ///
    /// It authorizes at the `authorization_endpoint` of the server's metadata once the client has read it,
    /// and at `{baseUrl}/oauth2/authorize` until then. ``signInURL(options:)`` reads the metadata first, so
    /// use it when `baseUrl` is the issuer of an OpenID provider other than ThunderID.
    ///
    /// With ``SignInOptions/organizationUnitId`` the sign-in is bounded to that unit: it authorizes at
    /// `{baseUrl}/ou/{ouId}/oauth2/authorize`, and ``handleRedirectCallback(url:)`` redeems the code at that
    /// unit's token endpoint. When ``ThunderIDConfig/pushedAuthorizationRequests`` is on, or the server
    /// requires pushed requests, use ``signInURL(options:)``, which pushes the request first.
    public func buildSignInURL(options: SignInOptions? = nil) throws -> URL {
        let cfg = try requireConfig()
        if let backend {
            return try backendSignInURL(backend, config: cfg, organizationUnitId: options?.organizationUnitId)
        }
        guard let clientId = cfg.clientId else {
            throw ThunderIDError(code: .invalidConfiguration, message: "clientId required for redirect mode")
        }
        if cfg.pushedAuthorizationRequests {
            throw ThunderIDError(
                code: .unsupportedOperation,
                message: "pushedAuthorizationRequests is on: build the URL with signInURL(options:), which pushes it"
            )
        }
        let ouId = options?.organizationUnitId
        let authorize = try authorizationEndpoint(organizationUnitId: ouId, config: cfg)
        guard var components = URLComponents(string: authorize) else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Could not build authorize URL")
        }
        components.queryItems = authorizationParameters(clientId: clientId, options: options, config: cfg)
        guard let url = components.url else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Could not build authorize URL")
        }
        pendingOrganizationUnitId = ouId
        return url
    }

    /// The authorization request's parameters, with a fresh PKCE challenge.
    func authorizationParameters(
        clientId: String,
        options: SignInOptions?,
        config cfg: ThunderIDConfig
    ) -> [URLQueryItem] {
        let (_, challenge) = pkceManager.generate()
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
        return params
    }

    /// Exchanges the authorization code received from the redirect callback for tokens.
    /// When sign-in runs on the app's backend, it exchanges the callback's `session_code` for the session.
    public func handleRedirectCallback(url: URL) async throws -> User {
        let cfg = try requireConfig()
        if let backend { return try await handleBackendCallback(url: url, backend: backend) }
        guard let clientId = cfg.clientId else {
            throw ThunderIDError(code: .invalidConfiguration, message: "clientId required")
        }
        if let ouId = pendingOrganizationUnitId {
            return try await handleBoundedCallback(url: url, organizationUnitId: ouId, clientId: clientId, config: cfg)
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
        let form: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("client_id", clientId),
            ("redirect_uri", cfg.afterSignInUrl ?? ""),
            ("code_verifier", verifier)
        ]
        let tokenEndpoint = try await discoveredEndpoint(\.tokenEndpoint, fallback: "/oauth2/token")
        let tokenResponse: TokenResponse = try await httpClient!.postForm(url: tokenEndpoint, form: form)
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
        if let backend {
            currentUser = nil
            return try await backend.signOut() ?? config?.afterSignOutUrl ?? "/"
        }
        if let refreshToken = tokenStore?.refreshToken(), let clientId = config?.clientId {
            let form: [(String, String)] = [("token", refreshToken), ("client_id", clientId)]
            if let httpClient,
               let revoke = try? await discoveredEndpoint(\.revocationEndpoint, fallback: "/oauth2/revoke") {
                let _: EmptyResponse? = try? await httpClient.postForm(url: revoke, form: form)
            }
        }
        tokenStore?.clear()
        currentUser = nil
        return config?.afterSignOutUrl ?? "/"
    }

    public func isSignedIn(sessionId: String? = nil) async throws -> Bool {
        try requireInitialized()
        if let backend { return try await backend.getSession().isSignedIn }
        return tokenStore?.accessToken() != nil
    }

    /// True while initializing or refreshing. When sign-in runs on a backend, it stays true until the first
    /// session read settles, so a route guard does not start a sign-in before it is known whether the user
    /// is signed in.
    public func isLoading() -> Bool { _isLoading || (backend?.loading.isLoading ?? false) }

    // MARK: - Registration

    /// App-native sign-up via Flow Execution API (spec §6.2). Keeps the SSO session handles a step returns.
    public func signUp(
        payload: EmbeddedSignInPayload? = nil,
        request: EmbeddedFlowRequestConfig? = nil
    ) async throws -> EmbeddedFlowResponse {
        try requireInitialized()
        try refuseInBackendMode("Embedded sign-up")
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
        try keepFlowSessions(from: response)
        try establishSessionIfNeeded(from: response)
        return response
    }

    // MARK: - Token & Session

    /// When sign-in runs on a backend, it is the access token the backend's `token` endpoint issues for the
    /// requests under `endpoints.backend.bypass`.
    public func getAccessToken(sessionId: String? = nil) async throws -> String {
        try requireInitialized()
        if let backend { return try await backend.accessToken() }
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
        try refuseInBackendMode("exchangeToken")
        var form: [(String, String)] = [
            ("grant_type", "urn:ietf:params:oauth:grant-type:token-exchange"),
            ("subject_token", config.subjectToken),
            ("subject_token_type", config.subjectTokenType)
        ]
        if let clientId = self.config?.clientId ?? self.config?.applicationId, !clientId.isEmpty {
            form.append(("client_id", clientId))
        }
        if let type = config.requestedTokenType { form.append(("requested_token_type", type)) }
        if let aud = config.audience { form.append(("audience", aud)) }
        let tokenEndpoint = try await discoveredEndpoint(\.tokenEndpoint, fallback: "/oauth2/token")
        let response: TokenResponse = try await httpClient!.postForm(url: tokenEndpoint, form: form)
        try tokenStore!.save(response)
        return response
    }

    public func clearSession(sessionId: String? = nil) {
        tokenStore?.clear()
        currentUser = nil
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
    func requireInitialized() throws -> ThunderIDConfig {
        guard let config else {
            throw ThunderIDError(code: .sdkNotInitialized, message: "Call initialize() before using the SDK")
        }
        return config
    }

    func requireConfig() throws -> ThunderIDConfig {
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
        if let wellKnown = config.endpoints.wellKnown, URL(string: wellKnown)?.scheme != "https" {
            throw ThunderIDError(code: .invalidConfiguration, message: "endpoints.wellKnown must be an HTTPS URL")
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

    func establishSessionIfNeeded(from response: EmbeddedFlowResponse) throws {
        let bounded = response.flowId.map { boundedFlowIds.contains($0) } ?? false
        if bounded, response.flowStatus != .promptOnly, let flowId = response.flowId {
            boundedFlowIds.remove(flowId)
        }
        guard response.flowStatus == .complete,
              let assertion = response.assertion,
              !assertion.isEmpty else {
            return
        }
        let tokenResponse = TokenResponse(accessToken: assertion, tokenType: "Bearer")
        // A sign-in bounded to a unit is a new session: nothing of the previous one carries over.
        if bounded {
            try tokenStore!.replace(tokenResponse)
            currentUser = nil
        } else {
            try tokenStore!.save(tokenResponse)
        }
        if let claims = try? decodeJwtToken(assertion) as [String: AnyCodable] {
            currentUser = User(claims: claims)
        }
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
