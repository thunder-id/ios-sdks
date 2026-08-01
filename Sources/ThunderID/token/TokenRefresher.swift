/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import Foundation

/// Handles automatic access token refresh and atomic refresh token rotation (spec §11.7).
final class TokenRefresher {
    private let httpClient: HTTPClient
    private let tokenStore: TokenStore
    private var refreshTask: Task<TokenResponse, Error>?

    init(httpClient: HTTPClient, tokenStore: TokenStore) {
        self.httpClient = httpClient
        self.tokenStore = tokenStore
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
            let body: [String: Any] = [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientId
            ]
            let response: TokenResponse = try await httpClient.post(
                path: "/oauth2/token",
                body: body,
                requiresAuth: false
            )
            try tokenStore.save(response)
            return response
        }
        refreshTask = task
        return try await task.value
    }
}
