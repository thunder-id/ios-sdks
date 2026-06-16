import Foundation

/// ThunderID SDK client — Platform layer implementation of the full IAMClient interface (spec §7.1).
public final class ThunderClient {
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
        guard self.config == nil else {
            throw IAMError(code: .alreadyInitialized, message: "SDK is already initialized")
        }
        try validateConfig(config)
        self.config = config
        let adapter = storage ?? config.storage ?? KeychainStorageAdapter()
        let http = HTTPClient(baseUrl: config.baseUrl)
        tokenStore = TokenStore(storage: adapter)
        jwksCache = JWKSCache(httpClient: http)
        tokenValidator = TokenValidator(jwksCache: jwksCache!, config: config)
        tokenRefresher = TokenRefresher(httpClient: http, tokenStore: tokenStore!)
        flowClient = FlowExecutionClient(httpClient: http)
        http.setAccessTokenProvider { [weak self] in
            guard let self, let config = self.config, let clientId = config.clientId else {
                throw IAMError(code: .sdkNotInitialized, message: "Not initialized")
            }
            return try await self.tokenRefresher!.getAccessToken(clientId: clientId)
        }
        httpClient = http
        return true
    }

    public func reInitialize(baseUrl: String? = nil, clientId: String? = nil) async throws -> Bool {
        guard var current = config else {
            throw IAMError(code: .sdkNotInitialized, message: "SDK not initialized")
        }
        if let baseUrl { current = ThunderIDConfig(baseUrl: baseUrl, clientId: current.clientId) }
        config = nil
        return try await initialize(config: current)
    }

    public func getConfiguration() throws -> ThunderIDConfig {
        guard let config else { throw IAMError(code: .sdkNotInitialized, message: "SDK not initialized") }
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
            response = try await flowClient!.submit(flowId: flowId, actionId: payload.actionId, inputs: payload.inputs, challengeToken: payload.challengeToken)
        } else {
            response = try await flowClient!.initiate(applicationId: request.applicationId, flowType: request.flowType)
        }
        try establishSessionIfNeeded(from: response)
        return response
    }

    /// Redirect-based sign-in: returns the authorization URL to open in ASWebAuthenticationSession.
    /// The caller is responsible for handling the redirect callback.
    public func buildSignInURL(options: SignInOptions? = nil) throws -> URL {
        let cfg = try requireConfig()
        guard let clientId = cfg.clientId else {
            throw IAMError(code: .invalidConfiguration, message: "clientId required for redirect mode")
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
            throw IAMError(code: .invalidConfiguration, message: "Could not build authorize URL")
        }
        return url
    }

    /// Exchanges the authorization code received from the redirect callback for tokens.
    public func handleRedirectCallback(url: URL) async throws -> User {
        let cfg = try requireConfig()
        guard let clientId = cfg.clientId else {
            throw IAMError(code: .invalidConfiguration, message: "clientId required")
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw IAMError(code: .invalidGrant, message: "Authorization code missing from callback URL")
        }
        guard let verifier = pkceManager.codeVerifier else {
            throw IAMError(code: .invalidGrant, message: "PKCE verifier not found; ensure signIn was called first")
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
                let _: EmptyDecodable? = try? await httpClient.post(
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
    public func signUp(payload: EmbeddedSignInPayload? = nil, request: EmbeddedFlowRequestConfig? = nil) async throws -> EmbeddedFlowResponse {
        try requireInitialized()
        let appId = request?.applicationId ?? config?.applicationId ?? ""
        let response: EmbeddedFlowResponse
        if let payload, let flowId = payload.flowId {
            response = try await flowClient!.submit(flowId: flowId, actionId: payload.actionId, inputs: payload.inputs, challengeToken: payload.challengeToken)
        } else {
            response = try await flowClient!.initiate(applicationId: appId, flowType: request?.flowType ?? .registration)
        }
        try establishSessionIfNeeded(from: response)
        return response
    }

    // MARK: - Token & Session

    public func getAccessToken(sessionId: String? = nil) async throws -> String {
        try requireInitialized()
        guard let clientId = config?.clientId else {
            throw IAMError(code: .invalidConfiguration, message: "clientId required")
        }
        return try await tokenRefresher!.getAccessToken(clientId: clientId)
    }

    public func decodeJwtToken<R: Decodable>(_ token: String) throws -> R {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3,
              let data = Data(base64URLEncoded: parts[1]) else {
            throw IAMError(code: .invalidInput, message: "Invalid JWT format")
        }
        return try JSONDecoder().decode(R.self, from: data)
    }

    public func exchangeToken(config: TokenExchangeRequestConfig, sessionId: String? = nil) async throws -> TokenResponse {
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
            let user = User(
                sub: sub,
                username: (claims["username"]?.value ?? claims["preferred_username"]?.value) as? String,
                email: claims["email"]?.value as? String,
                displayName: (claims["name"]?.value ?? claims["displayName"]?.value) as? String,
                profilePicture: claims["picture"]?.value as? String,
                claims: claims
            )
            currentUser = user
            return user
        }
        let user: User = try await httpClient!.get(path: "/oauth2/userinfo")
        currentUser = user
        return user
    }

    public func getUserProfile(options: [String: Any]? = nil) async throws -> UserProfile {
        try requireInitialized()
        return try await httpClient!.get(path: "/scim2/Me")
    }

    public func updateUserProfile(payload: [String: Any], userId: String? = nil) async throws -> User {
        try requireInitialized()
        let path = userId != nil ? "/scim2/Users/\(userId!)" : "/scim2/Me"
        let updated: User = try await httpClient!.post(path: path, body: payload)
        currentUser = updated
        return updated
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
            throw IAMError(code: .sdkNotInitialized, message: "Call initialize() before using the SDK")
        }
        return config
    }

    private func requireConfig() throws -> ThunderIDConfig {
        guard let config else {
            throw IAMError(code: .sdkNotInitialized, message: "Call initialize() before using the SDK")
        }
        return config
    }

    private func validateConfig(_ config: ThunderIDConfig) throws {
        guard !config.baseUrl.isEmpty else {
            throw IAMError(code: .invalidConfiguration, message: "baseUrl is required")
        }
        guard config.baseUrl.hasPrefix("https://") else {
            throw IAMError(code: .invalidConfiguration, message: "baseUrl must use HTTPS")
        }
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
            let sub = claims["sub"]?.value as? String ?? ""
            currentUser = User(
                sub: sub,
                username: claims["username"]?.value as? String ?? claims["preferred_username"]?.value as? String,
                email: claims["email"]?.value as? String,
                displayName: claims["name"]?.value as? String ?? claims["displayName"]?.value as? String,
                claims: claims
            )
        }
    }
}

private struct EmptyDecodable: Decodable {}

private extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        self.init(base64Encoded: base64)
    }
}
