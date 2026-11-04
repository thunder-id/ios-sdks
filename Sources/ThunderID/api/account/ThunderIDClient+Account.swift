// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The signed-in user's own account: who they are, their profile and its schema, and their credentials.
public extension ThunderIDClient {
    func getUser(options: [String: Any]? = nil) async throws -> User {
        try requireInitialized()
        if let user = currentUser { return user }
        if let backend { return try await backendUser(backend) }
        if let token = tokenStore?.accessToken(),
           let claims = try? decodeJwtToken(token) as [String: AnyCodable],
           let sub = claims["sub"]?.value as? String, !sub.isEmpty {
            let user = User(claims: claims)
            currentUser = user
            return user
        }
        let user: User = try await httpClient!.get(path: "/oauth2/userinfo")
        currentUser = user
        return user
    }

    func getUserProfile(options: [String: Any]? = nil) async throws -> UserProfile {
        try requireInitialized()
        return try await httpClient!.get(path: "/users/me")
    }

    func getUserSchema() async throws -> [String: AttributeSchema] {
        try requireInitialized()
        // The endpoint wraps the attribute map in a single "schema" key.
        let response: [String: [String: AttributeSchema]] = try await httpClient!.get(path: "/users/me/meta")
        return response["schema"] ?? [:]
    }

    func updateUserProfile(payload: [String: Any]) async throws -> UserProfile {
        try requireInitialized()
        return try await httpClient!.put(path: "/users/me", body: ["attributes": payload])
    }

    /// Changes one of the signed-in user's own credentials via `POST /users/me/update-credentials`.
    ///
    /// The self-service write path does not verify the account's existing value today, so this
    /// call collects only the new value, matching the Android/React/Vue SDKs.
    func updateUserCredentials(attribute: String = "password", newValue: String) async throws {
        try requireInitialized()
        let _: EmptyResponse = try await httpClient!.post(
            path: "/users/me/update-credentials",
            body: ["attributes": [attribute: newValue]]
        )
    }

    /// Overrides the cached user, e.g. after merging in freshly-fetched `/users/me` attributes.
    func setCachedUser(_ user: User) {
        currentUser = user
    }
}
