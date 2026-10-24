// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - Sign-in on a backend

public extension ThunderIDClient {
    /// Whether sign-in runs on the app's backend (`endpoints.backend`), which holds the tokens so the app
    /// never does.
    var isBackendMode: Bool { backend != nil }

    /// Calls `listener` when a signed-in session ends without this client signing out: another app signed
    /// the user out, an administrator ended the session, or it timed out. Only sign-in on a backend can tell,
    /// from a `401 login_required`, a check when the app returns to the foreground, or a poll every
    /// `session.checkInterval` seconds. A sign-out the app starts itself does not call it.
    func onSignOut(_ listener: @escaping () -> Void) {
        signOutListeners.append(listener)
    }

    /// Sends an API request and returns the response whatever its status.
    ///
    /// When sign-in runs on a backend, a request under `baseUrl` goes through the backend's proxy with the
    /// session handle, and a request under `endpoints.backend.bypass` goes straight there, with the access
    /// token unless `attachToken` is off. Otherwise a request under `baseUrl` carries the access token.
    /// Any other URL is refused with `unsupportedOperation`, rather than sent without credentials.
    func httpRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let config = try requireConfig()
        guard let httpClient else {
            throw ThunderIDError(code: .sdkNotInitialized, message: "Call initialize() before using the SDK")
        }
        if let backendHttp { return try await backendHttp.send(request) }
        let base = config.baseUrl.hasSuffix("/") ? String(config.baseUrl.dropLast()) : config.baseUrl
        guard let url = request.url?.absoluteString,
              url == base || url.hasPrefix("\(base)/") || url.hasPrefix("\(base)?") else {
            throw ThunderIDError(
                code: .unsupportedOperation,
                message: "Only requests under baseUrl can be sent with the access token"
            )
        }
        var authorized = request
        authorized.setValue("Bearer \(try await getAccessToken())", forHTTPHeaderField: "Authorization")
        return try await httpClient.rawData(for: authorized)
    }
}

extension ThunderIDClient {
    /// The session ended elsewhere: the backend client has already cleared the stored handle and token.
    func sessionEnded() {
        currentUser = nil
        signOutListeners.forEach { $0() }
    }

    func setUpBackend(
        _ endpoints: ResolvedBackendEndpoints,
        config: ThunderIDConfig,
        http: HTTPClient,
        tokenStore: TokenStore,
        session: URLSession?
    ) {
        let backendHttpClient = HTTPClient(baseUrl: endpoints.baseUrl, session: session)
        let client = BackendClient(
            endpoints: endpoints,
            tokenStore: tokenStore,
            http: backendHttpClient
        ) { [weak self] in
            self?.sessionEnded()
        }
        let transport = BackendHttpClient(backend: client, http: backendHttpClient)
        backend = client
        backendHttp = transport
        http.setTransport { request, fetcher in try await transport.send(request, fetcher: fetcher) }
        // Read the session now, so the client reports loading until it is known whether the user is signed in.
        Task {
            await client.startWatching(pollInterval: config.session.checkInterval)
            _ = try? await client.getSession()
        }
    }

    func tearDownBackend() {
        if let backend {
            Task { await backend.stopWatching() }
        }
        backend = nil
        backendHttp = nil
    }

    /// Refuses an operation that cannot run while sign-in runs on a backend: the embedded flows, whose
    /// result would land where the backend's tokens are not, and those that hand out a token the client
    /// does not hold.
    func refuseInBackendMode(_ operation: String) throws {
        guard backend != nil else { return }
        throw ThunderIDError(
            code: .unsupportedOperation,
            message: "\(operation) is not available when sign-in runs on a backend"
        )
    }

    func backendSignInURL(_ backend: BackendClient, config: ThunderIDConfig) throws -> URL {
        guard let redirectUri = config.afterSignInUrl, !redirectUri.isEmpty else {
            throw ThunderIDError(
                code: .invalidConfiguration,
                message: "afterSignInUrl is required to sign in through a backend"
            )
        }
        let (_, challenge) = pkceManager.generate()
        return try backend.signInURL(redirectUri: redirectUri, codeChallenge: challenge)
    }

    /// Completes the sign-in handoff: the callback carries a one-time `session_code`, which is exchanged,
    /// with the verifier this client generated for the sign-in, for the session.
    func handleBackendCallback(url: URL, backend: BackendClient) async throws -> User {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            pkceManager.clearVerifier()
            throw ThunderIDError(code: .authenticationFailed, message: "The backend could not sign in: \(error)")
        }
        guard let code = items.first(where: { $0.name == "session_code" })?.value, !code.isEmpty else {
            throw ThunderIDError(code: .invalidGrant, message: "Session code missing from callback URL")
        }
        guard let verifier = pkceManager.codeVerifier else {
            throw ThunderIDError(
                code: .invalidGrant,
                message: "PKCE verifier not found; ensure buildSignInURL was called first"
            )
        }
        defer { pkceManager.clearVerifier() }
        let session = try await backend.startSession(code: code, verifier: verifier)
        let user = User(claims: session.user ?? [:])
        setCachedUser(user)
        return user
    }

    /// The signed-in user from the backend session: the ID token's claims without the protocol claims.
    func backendUser(_ backend: BackendClient) async throws -> User {
        let session = try await backend.getSession()
        guard session.isSignedIn else {
            throw ThunderIDError(code: .authenticationFailed, message: "No user is signed in")
        }
        let user = User(claims: session.user ?? [:])
        setCachedUser(user)
        return user
    }
}
