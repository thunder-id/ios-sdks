// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The session an embedded (app-native) flow leaves: the token its assertion is exchanged for.
extension ThunderIDClient {
    /// The `clientId` an embedded flow needs to exchange its assertion; checked before each flow request.
    func requireEmbeddedClientId() throws -> String {
        try requireClientId(requireConfig(), for: "embedded sign-in and sign-up, next to applicationId")
    }

    /// Keeps a flow step's SSO session handles and, when the step completes with an assertion, replaces the
    /// session with the token the assertion is exchanged for. When the exchange fails, the previous session
    /// stays and the step's new handles are dropped, so the next attempt runs the flow again.
    func keepFlowStep(_ response: EmbeddedFlowResponse) async throws {
        guard response.flowStatus == .complete, let assertion = response.assertion, !assertion.isEmpty else {
            try keepFlowSessions(from: response)
            return
        }
        let tokens: TokenResponse
        do {
            tokens = try await exchangeFlowAssertion(assertion)
        } catch {
            try? tokenStore?.mergeFlowSessions([], cleared: response.clearedSessions ?? [])
            throw error
        }
        try keepFlowSessions(from: response)
        try tokenStore!.replace(tokens)
        currentUser = nil
    }

    /// Exchanges a completed flow's `assertion` for an access token at the token endpoint (RFC 8693), with no
    /// scope: the token carries what the flow granted. The assertion is kept as the ID token.
    private func exchangeFlowAssertion(_ assertion: String) async throws -> TokenResponse {
        let form: [(String, String)] = [
            ("grant_type", Self.tokenExchangeGrant),
            ("client_id", try requireEmbeddedClientId()),
            ("subject_token", assertion),
            ("subject_token_type", "urn:ietf:params:oauth:token-type:jwt")
        ]
        let endpoint = try await discoveredEndpoint(\.tokenEndpoint, fallback: "/oauth2/token")
        let response: TokenResponse
        do {
            response = try await postForm(endpoint.absoluteString, form: form)
        } catch let failure as OAuthFailure {
            let error = Self.mapOAuthFailure(failure)
            guard failure.error == "unauthorized_client" else { throw error }
            throw ThunderIDError(
                code: .invalidConfiguration,
                message: "An embedded sign-in needs the \(Self.tokenExchangeGrant) grant type on the application",
                underlyingError: error,
                serverError: error.serverError
            )
        }
        return TokenResponse(
            accessToken: response.accessToken,
            tokenType: response.tokenType,
            expiresIn: response.expiresIn,
            idToken: assertion,
            scope: response.scope
        )
    }

    private static let tokenExchangeGrant = "urn:ietf:params:oauth:grant-type:token-exchange"
}
