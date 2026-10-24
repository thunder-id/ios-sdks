// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension BackendClient {
    /// The access token for requests under `endpoints.backend.bypass`. Like a client credentials token it
    /// has no refresh token: one is kept per client in the token storage with the time it was issued,
    /// reused until it is ``tokenRenewalMargin`` from expiry, then requested again. Concurrent callers share
    /// one request.
    ///
    /// - Parameter renew: Request a new token even when the stored one is still valid.
    func accessToken(renew: Bool = false) async throws -> String {
        if !renew,
           let token = tokenStore.accessToken(),
           let expiry = tokenStore.tokenExpiry(),
           expiry.timeIntervalSinceNow > Self.tokenRenewalMargin {
            return token
        }
        if let tokenTask { return try await tokenTask.value }
        let task = Task { try await requestAccessToken() }
        tokenTask = task
        defer { tokenTask = nil }
        return try await task.value
    }

    /// Gets an access token from the backend's `token` endpoint and stores it. A `session_expired` refreshes
    /// the session and asks once more; `login_required` means the session has ended.
    private func requestAccessToken() async throws -> String {
        var (data, response) = try await send(endpoints.token, method: "POST")
        if response.statusCode == 401 {
            switch Self.errorCode(data) {
            case "session_expired":
                if try await refresh() {
                    (data, response) = try await send(endpoints.token, method: "POST")
                }
            case "login_required":
                markSignedOut()
            default:
                break
            }
        }
        guard (200...299).contains(response.statusCode) else {
            throw Self.failure("token", status: response.statusCode)
        }
        let issued = try Self.decode(TokenResponse.self, from: data, endpoint: "token")
        // Only the access token is kept. The backend issues no refresh token, and an ID token, should one
        // arrive, stays out of the client.
        try tokenStore.save(
            TokenResponse(
                accessToken: issued.accessToken,
                tokenType: issued.tokenType,
                expiresIn: issued.expiresIn,
                scope: issued.scope
            ),
            createdAt: Date()
        )
        return issued.accessToken
    }
}
