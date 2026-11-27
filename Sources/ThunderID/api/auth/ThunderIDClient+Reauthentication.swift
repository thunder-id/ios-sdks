// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

#if !os(tvOS)
import AuthenticationServices
#endif
import Foundation

/// How ``ThunderIDClient/reauthenticate(maxAge:options:)`` shows the sign-in.
public struct ReauthenticateOptions {
    /// Opens the authorization URL and returns the callback URL, for an app that runs its own browser
    /// session. When `nil`, the SDK opens an `ASWebAuthenticationSession`.
    public var authorize: ((URL) async throws -> URL)?
    #if !os(tvOS)
    /// The window the browser sheet opens over; the key window when `nil`.
    public var presentationAnchor: ASPresentationAnchor?

    public init(authorize: ((URL) async throws -> URL)? = nil, presentationAnchor: ASPresentationAnchor? = nil) {
        self.authorize = authorize
        self.presentationAnchor = presentationAnchor
    }
    #else
    public init(authorize: ((URL) async throws -> URL)? = nil) {
        self.authorize = authorize
    }
    #endif
}

/// How the signed-in user signs in again for a request the server refused with
/// ``ThunderIDErrorCode/stepUpRequired``.
public enum ReauthenticationMethod: Equatable {
    /// In a browser, with ``ThunderIDClient/reauthenticate(maxAge:options:)``: a session from a redirect sign-in.
    case browser
    /// By running the sign-in flow again with ``EmbeddedFlowRequestConfig/reauthentication``: a session from an
    /// embedded (app-native) sign-in.
    case flow
    /// Not in the app: sign-in runs on a backend.
    case unavailable
}

public extension ThunderIDClient {
    /// How the signed-in user signs in again: ``ReauthenticationMethod/flow`` for a session from an embedded
    /// sign-in flow, ``ReauthenticationMethod/unavailable`` with a backend, otherwise
    /// ``ReauthenticationMethod/browser``.
    func reauthenticationMethod() -> ReauthenticationMethod {
        if backend != nil { return .unavailable }
        guard tokenStore?.isEmbeddedSignIn() == true else { return .browser }
        let config = try? getConfiguration()
        let canRunFlow = config?.clientId?.isEmpty == false && config?.applicationId?.isEmpty == false
        return canRunFlow ? .flow : .unavailable
    }

    /// Signs the signed-in user in again, for a request the server refused with
    /// ``ThunderIDErrorCode/stepUpRequired``, and replaces the session's tokens with the new ones.
    ///
    /// Redirect mode only: an authorization request with the configured scopes, PKCE, `state`, `nonce`,
    /// `max_age` (or `prompt=login` when `maxAge` is `nil`) and the session's ID token as `id_token_hint`.
    /// The new ID token is validated, its `nonce` checked, and its `sub` must be the signed-in user's. On any
    /// failure, including a cancelled browser sheet, the session stays as it was. It never refreshes the
    /// session: a refreshed token keeps the original sign-in time.
    ///
    /// - Parameters:
    ///   - maxAge: The challenge's `maxAge` in seconds, from ``ThunderIDError/authenticationChallenge``.
    ///   - options: The browser to use. By default an `ASWebAuthenticationSession` over the key window.
    /// - Returns: The signed-in user.
    /// - Throws: ``ThunderIDErrorCode/unsupportedOperation`` when sign-in runs on a backend or the session came
    ///   from an embedded sign-in flow (run the flow again with ``EmbeddedFlowRequestConfig/reauthentication``
    ///   there; ``reauthenticationMethod()`` tells which); ``ThunderIDErrorCode/authenticationFailed`` when the
    ///   sign-in fails, is cancelled, or returns another user.
    func reauthenticate(maxAge: Int?, options: ReauthenticateOptions = ReauthenticateOptions()) async throws -> User {
        let config = try requireConfig()
        if backend != nil {
            throw ThunderIDError(code: .unsupportedOperation, message: "Sign in again through the backend")
        }
        guard reauthenticationMethod() == .browser else {
            throw ThunderIDError(
                code: .unsupportedOperation,
                message: "App-native mode: run the sign-in flow again to sign the user in again"
            )
        }
        guard let subject = signedInSubject() else {
            throw ThunderIDError(code: .sessionExpired, message: "No signed-in user to sign in again")
        }
        var signIn = SignInOptions(prompt: maxAge == nil ? "login" : nil, maxAge: maxAge)
        signIn.idTokenHint = tokenStore?.idToken()
        signIn.state = Self.randomValue()
        signIn.nonce = Self.randomValue()
        let url = try await signInURL(options: signIn)
        let callback: URL
        do {
            callback = try await openForReauthentication(url, options: options, config: config)
        } catch {
            pkceManager.clearVerifier()
            if error is ThunderIDError { throw error }
            throw ThunderIDError(
                code: .authenticationFailed,
                message: "The sign-in did not finish",
                underlyingError: error
            )
        }
        let response = try await redeemReauthentication(callback, state: signIn.state, config: config)
        try await checkReauthentication(response, nonce: signIn.nonce, subject: subject)
        try tokenStore?.replace(response)
        currentUser = nil
        return try await getUser()
    }
}

extension ThunderIDClient {
    /// The signed-in user's `sub`, required to start a re-sign-in.
    func requireSignedInSubject() throws -> String {
        guard let subject = signedInSubject() else {
            throw ThunderIDError(code: .authenticationFailed, message: "Nobody is signed in to sign in again")
        }
        return subject
    }

    /// Remembers who a re-sign-in flow must sign in, from the step that starts it (`startSubject`), and when a
    /// step completes such a flow, whatever config it is sent with, requires its assertion to name that user
    /// before the assertion is exchanged or the session touched. A step that does not complete keeps the entry,
    /// since the server keeps the execution after an error step.
    func trackReauthentication(
        submittedFlowId: String?,
        startSubject: String?,
        response: EmbeddedFlowResponse
    ) throws {
        guard let expected = submittedFlowId.flatMap({ reauthenticationSubjects[$0] }) ?? startSubject else { return }
        let flowId = submittedFlowId ?? response.flowId
        guard response.flowStatus == .complete else {
            if let flowId { reauthenticationSubjects[flowId] = expected }
            return
        }
        if let flowId { reauthenticationSubjects.removeValue(forKey: flowId) }
        guard let assertion = response.assertion, !assertion.isEmpty else { return }
        let claims = try? decodeJwtToken(assertion) as [String: AnyCodable]
        guard claims?["sub"]?.value as? String == expected else { throw Self.differentUserError }
    }

    /// A re-sign-in that another account completed. The session stays as it was.
    static var differentUserError: ThunderIDError {
        var error = ThunderIDError(code: .authenticationFailed, message: "The sign-in returned another user")
        error.anotherAccountSignedIn = true
        return error
    }

    /// The `sub` of the signed-in user: from the session's ID token, else its access token.
    func signedInSubject() -> String? {
        for token in [tokenStore?.idToken(), tokenStore?.accessToken()] {
            if let token, let claims = try? decodeJwtToken(token) as [String: AnyCodable],
               let sub = claims["sub"]?.value as? String, !sub.isEmpty {
                return sub
            }
        }
        return currentUser?.sub
    }

    private func openForReauthentication(
        _ url: URL,
        options: ReauthenticateOptions,
        config: ThunderIDConfig
    ) async throws -> URL {
        if let authorize = options.authorize { return try await authorize(url) }
        #if os(tvOS)
        throw ThunderIDError(code: .unsupportedOperation, message: "Browser sign-in is not available on tvOS")
        #else
        guard let scheme = URL(string: config.afterSignInUrl ?? "")?.scheme else {
            throw ThunderIDError(code: .invalidConfiguration, message: "afterSignInUrl is required to sign in again")
        }
        let session = await FederatedAuthSession(presentationAnchor: options.presentationAnchor)
        return try await session.authenticate(url: url, callbackURLScheme: scheme)
        #endif
    }

    /// Checks the callback's `state` and redeems its code. Nothing is stored.
    private func redeemReauthentication(
        _ callback: URL,
        state: String?,
        config: ThunderIDConfig
    ) async throws -> TokenResponse {
        defer { pkceManager.clearVerifier() }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        guard value("state") == state else {
            throw ThunderIDError(code: .authenticationFailed, message: "The sign-in returned an unexpected state")
        }
        if let error = value("error") {
            throw ThunderIDError(
                code: .authenticationFailed,
                message: value("error_description") ?? "The sign-in failed: \(error)",
                serverError: ServerError(code: error)
            )
        }
        guard let code = value("code"), let verifier = pkceManager.codeVerifier else {
            throw ThunderIDError(code: .authenticationFailed, message: "The sign-in returned no authorization code")
        }
        let form: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("client_id", try requireClientId(config, for: "reauthenticate")),
            ("redirect_uri", config.afterSignInUrl ?? ""),
            ("code_verifier", verifier)
        ]
        let tokenEndpoint = try await discoveredEndpoint(\.tokenEndpoint, fallback: "/oauth2/token")
        return try await httpClient!.postForm(url: tokenEndpoint, form: form)
    }

    /// Validates the new ID token and requires its `nonce` and its `sub` to be the expected ones.
    private func checkReauthentication(_ response: TokenResponse, nonce: String?, subject: String) async throws {
        guard let idToken = response.idToken,
              let claims = try? decodeJwtToken(idToken) as [String: AnyCodable] else {
            throw ThunderIDError(code: .authenticationFailed, message: "The sign-in returned no ID token")
        }
        try await tokenValidator?.validate(idToken: idToken, nonce: nonce)
        guard claims["nonce"]?.value as? String == nonce else {
            throw ThunderIDError(code: .authenticationFailed, message: "ID token nonce mismatch")
        }
        guard claims["sub"]?.value as? String == subject else {
            throw Self.differentUserError
        }
    }

    /// 32 random bytes, base64url-encoded.
    static func randomValue() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public extension ThunderIDError {
    /// Whether a re-sign-in failed because another account signed in. The session stays as it was.
    var isReauthenticationByAnotherAccount: Bool { anotherAccountSignedIn }
}
