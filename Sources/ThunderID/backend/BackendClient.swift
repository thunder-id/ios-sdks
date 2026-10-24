// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Header that carries the session handle on every backend request.
let backendSessionHandleHeader = "X-Session-Handle"

/// Talks to the app's backend when sign-in runs there: starts the session from the sign-in handoff,
/// reads it, refreshes it, and ends it. The app never holds the user's tokens; the backend keeps them
/// behind the session handle, which lives in the configured storage and is never logged.
actor BackendClient {
    /// A stored access token is reused until it is this close to expiry, in seconds.
    static let tokenRenewalMargin: TimeInterval = 30

    /// A check on returning to the foreground is skipped when the last one is more recent than this.
    static let foregroundCheckThrottle: TimeInterval = 5

    nonisolated let endpoints: ResolvedBackendEndpoints
    /// True until the first session read settles.
    nonisolated let loading = LoadingFlag()

    let tokenStore: TokenStore
    let http: HTTPClient
    private let onSignedOut: () -> Void

    private var cachedSession: BackendSession?
    private var sessionTask: Task<BackendSession, Error>?
    private var refreshTask: Task<Bool, Error>?
    var tokenTask: Task<String, Error>?
    /// Whether the session last seen was signed in, so a later read can tell it has ended.
    private var wasSignedIn = false
    var lastCheck = Date.distantPast
    var pollTask: Task<Void, Never>?
    var foregroundObserver: NSObjectProtocol?

    /// - Parameter onSignedOut: Called when a signed-in session turns out to have ended without this
    ///   client signing out: another app signed the user out, an administrator ended it, or it timed out.
    init(
        endpoints: ResolvedBackendEndpoints,
        tokenStore: TokenStore,
        http: HTTPClient,
        onSignedOut: @escaping () -> Void
    ) {
        self.endpoints = endpoints
        self.tokenStore = tokenStore
        self.http = http
        self.onSignedOut = onSignedOut
    }

    // MARK: - Session

    /// Returns the session. The result is cached until a sign-in, sign-out, or refresh changes it, and
    /// concurrent callers share one read.
    ///
    /// - Parameter reload: Read the session from the backend even when one is cached.
    func getSession(reload: Bool = false) async throws -> BackendSession {
        guard tokenStore.sessionHandle() != nil else {
            // Nothing to read: no sign-in has completed, or local state was cleared.
            wasSignedIn = false
            cachedSession = .signedOut
            loading.settle()
            return .signedOut
        }
        if reload { cachedSession = nil }
        if let cachedSession { return cachedSession }
        if let sessionTask { return try await sessionTask.value }
        let task = Task { try await loadSession() }
        sessionTask = task
        defer {
            sessionTask = nil
            loading.settle()
        }
        let session = try await task.value
        cachedSession = session
        return session
    }

    /// Exchanges the one-time `session_code` from the sign-in handoff, with the PKCE verifier it was
    /// issued against, for the session, and stores the session handle.
    func startSession(code: String, verifier: String) async throws -> BackendSession {
        let body = try JSONSerialization.data(withJSONObject: ["session_code": code, "code_verifier": verifier])
        let (data, response) = try await send(endpoints.session, method: "POST", body: body, attachHandle: false)
        guard (200...299).contains(response.statusCode) else {
            throw Self.failure("session", status: response.statusCode)
        }
        let session = try Self.decode(BackendSession.self, from: data, endpoint: "session")
        guard session.isSignedIn, let handle = session.handle, !handle.isEmpty else {
            throw ThunderIDError(code: .authenticationFailed, message: "The backend did not start a session")
        }
        // A new session starts clean: a token issued for an earlier session is not reused.
        tokenStore.clear()
        try tokenStore.saveSessionHandle(handle)
        let started = BackendSession(isSignedIn: true, user: session.user, expiresAt: session.expiresAt, handle: nil)
        cachedSession = started
        wasSignedIn = true
        loading.settle()
        return started
    }

    /// Asks the backend whether the session is still live. The check neither refreshes the session nor
    /// counts as activity, so it can be polled without keeping an idle session alive.
    ///
    /// - Returns: Whether the session is live. A failed check reports the last known state.
    @discardableResult
    func checkSession() async -> Bool {
        lastCheck = Date()
        guard tokenStore.sessionHandle() != nil else { return false }
        do {
            let (data, response) = try await send(endpoints.checkSession, method: "GET")
            guard (200...299).contains(response.statusCode) else { return wasSignedIn }
            let check = try Self.decode(SessionCheck.self, from: data, endpoint: "checkSession")
            if !check.isSignedIn {
                markSignedOut()
            }
            return check.isSignedIn
        } catch {
            return wasSignedIn
        }
    }

    /// Refreshes the session once, sharing one request between concurrent callers.
    ///
    /// - Returns: Whether the session was refreshed. When it was not, the session is now signed out.
    func refresh() async throws -> Bool {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { () throws -> Bool in
            let (_, response) = try await send(endpoints.refresh, method: "POST")
            return (200...299).contains(response.statusCode)
        }
        refreshTask = task
        defer { refreshTask = nil }
        let refreshed = try await task.value
        if refreshed {
            cachedSession = nil
        } else {
            markSignedOut()
        }
        return refreshed
    }

    /// Ends the backend session and clears the session handle and any stored token. Local state is
    /// cleared even when the backend cannot be reached, and the failure is then reported.
    ///
    /// - Returns: The URL that ends the session at the authorization server, when the backend sent one.
    func signOut() async throws -> String? {
        // Signing out here is not news to anyone, so the sign-out listener is not told.
        wasSignedIn = false
        cachedSession = .signedOut
        loading.settle()
        guard tokenStore.sessionHandle() != nil else {
            tokenStore.clear()
            return nil
        }
        defer { tokenStore.clear() }
        let (data, response) = try await send(endpoints.signOut, method: "POST")
        guard (200...299).contains(response.statusCode) else {
            throw Self.failure("signOut", status: response.statusCode)
        }
        return (try? JSONDecoder().decode(SignOutResponse.self, from: data))?.redirectUrl
    }

    /// Records that the session has ended, clears the session handle and any stored token, and tells the
    /// sign-out listener when it had been signed in.
    func markSignedOut() {
        cachedSession = .signedOut
        tokenStore.clear()
        loading.settle()
        if wasSignedIn {
            wasSignedIn = false
            onSignedOut()
        }
    }

    /// The URL that starts sign-in at the backend, bound to the PKCE `codeChallenge` and coming back to
    /// `redirectUri`.
    nonisolated func signInURL(redirectUri: String, codeChallenge: String) throws -> URL {
        var components = URLComponents(url: endpoints.signIn, resolvingAgainstBaseURL: false)
        let existing = components?.queryItems ?? []
        components?.queryItems = existing + [
            .init(name: "redirect_uri", value: redirectUri),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components?.url else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Could not build the backend sign-in URL")
        }
        return url
    }

    func sessionHandle() -> String? {
        tokenStore.sessionHandle()
    }

    // MARK: - Transport

    /// Sends a request to a backend endpoint with the session handle. Logs nothing: the request carries
    /// the handle and the response can carry the session.
    func send(
        _ url: URL,
        method: String,
        body: Data? = nil,
        attachHandle: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.assumesHTTP3Capable = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if attachHandle, let handle = tokenStore.sessionHandle() {
            request.setValue(handle, forHTTPHeaderField: backendSessionHandleHeader)
        }
        return try await http.rawData(for: request)
    }

    /// The `error` code of a backend `401`, such as `session_expired` or `login_required`.
    nonisolated static func errorCode(_ data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
    }

    static func failure(_ endpoint: String, status: Int) -> ThunderIDError {
        let code: ThunderIDErrorCode
        switch status {
        case 401: code = .authenticationFailed
        case 403: code = .forbidden
        case 500...599: code = .serverError
        default: code = .unknownError
        }
        return ThunderIDError(code: code, message: "The backend \(endpoint) endpoint returned \(status)")
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, endpoint: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // The body is not echoed: it can carry the session or a token.
            throw ThunderIDError(code: .unknownError, message: "Could not read the backend \(endpoint) response")
        }
    }

    // MARK: - Private

    private func loadSession() async throws -> BackendSession {
        var (data, response) = try await send(endpoints.session, method: "GET")
        if response.statusCode == 401, Self.errorCode(data) == "session_expired", try await refresh() {
            (data, response) = try await send(endpoints.session, method: "GET")
        }
        if response.statusCode == 401 {
            return signedOutSession()
        }
        guard (200...299).contains(response.statusCode) else {
            throw Self.failure("session", status: response.statusCode)
        }
        let session = try Self.decode(BackendSession.self, from: data, endpoint: "session")
        guard session.isSignedIn else {
            return signedOutSession()
        }
        wasSignedIn = true
        return BackendSession(isSignedIn: true, user: session.user, expiresAt: session.expiresAt, handle: nil)
    }

    private func signedOutSession() -> BackendSession {
        markSignedOut()
        return .signedOut
    }
}

private struct SessionCheck: Decodable {
    let isSignedIn: Bool
}

private struct SignOutResponse: Decodable {
    let redirectUrl: String?
}

/// A flag readable from synchronous code, such as `isLoading()`, while an actor updates it.
final class LoadingFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var loading = true

    var isLoading: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loading
    }

    func settle() {
        lock.lock()
        loading = false
        lock.unlock()
    }
}
