// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Handles automatic access token refresh and atomic refresh token rotation (spec §11.7).
final class TokenRefresher {
    private let httpClient: HTTPClient
    private let tokenStore: TokenStore
    /// Where tokens are refreshed: the server's advertised `token_endpoint`. Without it, `/oauth2/token`.
    private let endpoint: (() async throws -> URL)?
    private var refreshTask: Task<TokenResponse, Error>?

    init(httpClient: HTTPClient, tokenStore: TokenStore, endpoint: (() async throws -> URL)? = nil) {
        self.httpClient = httpClient
        self.tokenStore = tokenStore
        self.endpoint = endpoint
    }

    /// Returns the current access token, refreshing if near expiry (60s threshold).
    /// `clientId` is only required when a refresh is actually attempted — app-native
    /// sessions (config'd with `applicationId`, no `clientId`) can still read a
    /// still-valid token without it.
    func getAccessToken(clientId: String?) async throws -> String {
        if let token = tokenStore.accessToken() {
            if !tokenStore.isNearExpiry() {
                return token
            }
            // Token-exchange flows may return an access token without a refresh token.
            // In that case, use the current access token instead of failing hard.
            if tokenStore.refreshToken() == nil {
                return token
            }
        }
        guard let clientId else {
            throw ThunderIDError(code: .invalidConfiguration, message: "clientId required to refresh access token")
        }
        let refreshed = try await refresh(clientId: clientId)
        return refreshed.accessToken
    }

    func refresh(clientId: String) async throws -> TokenResponse {
        if let existingTask = refreshTask {
            return try await existingTask.value
        }
        let task = Task<TokenResponse, Error> {
            defer { self.refreshTask = nil }
            guard let refreshToken = tokenStore.refreshToken() else {
                throw ThunderIDError(code: .sessionExpired, message: "No refresh token available")
            }
            // Form-encoded, as the token endpoint reads. A refresh token from a bounded sign-in carries its unit.
            let form: [(String, String)] = [
                ("grant_type", "refresh_token"),
                ("refresh_token", refreshToken),
                ("client_id", clientId)
            ]
            let response: TokenResponse
            if let endpoint {
                response = try await httpClient.postForm(url: try await endpoint(), form: form)
            } else {
                response = try await httpClient.postForm(path: "/oauth2/token", form: form)
            }
            try tokenStore.save(response)
            return response
        }
        refreshTask = task
        return try await task.value
    }
}
