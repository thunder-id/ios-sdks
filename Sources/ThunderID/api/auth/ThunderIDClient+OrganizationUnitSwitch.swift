// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Options for ``ThunderIDClient/switchOrganizationUnit(_:options:)``.
public struct SwitchOrganizationUnitOptions {
    /// Opens an authorization URL, typically in an `ASWebAuthenticationSession`, and returns the callback
    /// URL it comes back to. Redirect mode and sign-in on a backend use it when the switch cannot run
    /// silently. The server reuses its SSO session, so normally no credentials are asked.
    public var authorize: ((URL) async throws -> URL)?
    /// App-native mode: the application whose `AUTHENTICATION` flow is started. Defaults to
    /// ``ThunderIDConfig/applicationId``.
    public var applicationId: String?

    public init(authorize: ((URL) async throws -> URL)? = nil, applicationId: String? = nil) {
        self.authorize = authorize
        self.applicationId = applicationId
    }
}

/// What ``ThunderIDClient/switchOrganizationUnit(_:options:)`` did.
public enum OrganizationUnitSwitchResult {
    /// The session now belongs to the unit: the tokens were replaced and the user read again.
    case switched(User)
    /// App-native mode: the sign-in bounded to the unit needs the user. Drive the returned step with
    /// ``ThunderIDClient/signIn(payload:request:sessionId:)``; the session switches when the flow completes,
    /// and the previous one stays until then.
    case signInRequired(EmbeddedFlowResponse)
}

public extension ThunderIDClient {
    /// Signs in again bounded to the organization unit `ouId`, reusing the server's SSO session where the
    /// user can sign in there.
    ///
    /// - With a device secret from a `device_sso` sign-in, it exchanges the secret at
    ///   `{baseUrl}/ou/{ouId}/oauth2/token`, with no browser.
    /// - Otherwise redirect mode, and sign-in on a backend, open the unit-bounded authorization URL through
    ///   ``SwitchOrganizationUnitOptions/authorize`` and complete the callback.
    /// - App-native mode starts the `AUTHENTICATION` flow with `ouId`.
    ///
    /// On success the tokens are replaced and the user is read again (the refresh token is bound to the
    /// unit). On failure the previous session stays as it was. An unknown unit and a unit the application
    /// cannot be used from both fail with ``ThunderIDErrorCode/organizationUnitUnavailable``.
    func switchOrganizationUnit(
        _ ouId: String,
        options: SwitchOrganizationUnitOptions = .init()
    ) async throws -> OrganizationUnitSwitchResult {
        let config = try requireConfig()
        _ = try Self.organizationUnitSegment(ouId)
        if backend != nil {
            return .switched(try await switchThroughBrowser(ouId, options: options))
        }
        if config.clientId != nil, tokenStore?.deviceSecret() != nil {
            do {
                return .switched(try await exchangeDeviceSecret(for: ouId, config: config))
            } catch let error as ThunderIDError
                        where options.authorize != nil && error.code != .organizationUnitUnavailable {
                // The SSO session cannot sign the user in silently: fall back to the browser.
            }
        }
        if config.clientId != nil, options.authorize != nil {
            return .switched(try await switchThroughBrowser(ouId, options: options))
        }
        guard let applicationId = options.applicationId ?? config.applicationId, !applicationId.isEmpty else {
            throw ThunderIDError(
                code: .invalidConfiguration,
                message: "Switching organization units needs an authorize handler, a device secret or an applicationId"
            )
        }
        let response = try await signIn(
            payload: EmbeddedSignInPayload(),
            request: EmbeddedFlowRequestConfig(
                applicationId: applicationId,
                flowType: .authentication,
                organizationUnitId: ouId
            )
        )
        switch response.flowStatus {
        case .complete:
            return .switched(try await getUser())
        case .promptOnly:
            return .signInRequired(response)
        case .error:
            throw ThunderIDError(
                code: .authenticationFailed,
                message: response.failureReason ?? "The sign-in to the organization unit failed"
            )
        }
    }
}

extension ThunderIDClient {
    private func switchThroughBrowser(_ ouId: String, options: SwitchOrganizationUnitOptions) async throws -> User {
        guard let authorize = options.authorize else {
            throw ThunderIDError(
                code: .invalidConfiguration,
                message: "Switching organization units in redirect mode needs an authorize handler"
            )
        }
        let url = try await signInURL(options: SignInOptions(organizationUnitId: ouId))
        let callback: URL
        do {
            callback = try await authorize(url)
        } catch {
            pkceManager.clearVerifier()
            pendingOrganizationUnitId = nil
            throw error
        }
        return try await handleRedirectCallback(url: callback)
    }

    /// Exchanges the stored device secret at the unit's token endpoint, which signs the user in to the unit
    /// from the SSO session without the browser.
    private func exchangeDeviceSecret(for ouId: String, config: ThunderIDConfig) async throws -> User {
        guard let secret = tokenStore?.deviceSecret() else {
            throw ThunderIDError(code: .invalidGrant, message: "No device secret is stored")
        }
        let clientId = try requireClientId(config, for: "switchOrganizationUnit")
        let form: [(String, String)] = [
            ("grant_type", "urn:ietf:params:oauth:grant-type:token-exchange"),
            ("subject_token", secret),
            ("subject_token_type", "urn:ietf:params:oauth:token-type:jwt"),
            ("client_id", clientId),
            ("scope", config.scopes.joined(separator: " "))
        ]
        let response = try await redeemAtUnit(ouId, form: form, config: config)
        return try await adoptBoundedSession(response)
    }

    /// Completes a redirect sign-in bounded to `organizationUnitId`: its code is redeemed only at the unit's
    /// token endpoint. A callback that reports an error leaves the stored session as it was.
    func handleBoundedCallback(
        url: URL,
        organizationUnitId ouId: String,
        clientId: String,
        config: ThunderIDConfig
    ) async throws -> User {
        defer {
            pkceManager.clearVerifier()
            pendingOrganizationUnitId = nil
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value: (String) -> String? = { name in items.first { $0.name == name }?.value }
        if let error = value("error") {
            let description = value("error_description")
            throw Self.mapOAuthFailure(
                OAuthFailure(status: 400, error: error, description: description),
                organizationUnitId: ouId
            )
        }
        guard let code = value("code") else {
            throw ThunderIDError(code: .invalidGrant, message: "Authorization code missing from callback URL")
        }
        guard let verifier = pkceManager.codeVerifier else {
            throw ThunderIDError(
                code: .invalidGrant,
                message: "PKCE verifier not found; ensure signIn was called first"
            )
        }
        let form: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("client_id", clientId),
            ("redirect_uri", config.afterSignInUrl ?? ""),
            ("code_verifier", verifier)
        ]
        let response = try await redeemAtUnit(ouId, form: form, config: config)
        return try await adoptBoundedSession(response)
    }

    private func redeemAtUnit(
        _ ouId: String,
        form: [(String, String)],
        config: ThunderIDConfig
    ) async throws -> TokenResponse {
        let endpoint = try oauthURL("/oauth2/token", organizationUnitId: ouId, config: config)
        do {
            return try await postForm(endpoint, form: form)
        } catch let failure as OAuthFailure {
            throw Self.mapOAuthFailure(failure, organizationUnitId: ouId)
        }
    }

    /// Validates the new session's ID token, then replaces the stored session with it and reads the user.
    private func adoptBoundedSession(_ response: TokenResponse) async throws -> User {
        if let idToken = response.idToken {
            try await tokenValidator?.validate(idToken: idToken, nonce: nil)
        }
        try tokenStore!.replace(response)
        currentUser = nil
        return try await getUser()
    }
}
