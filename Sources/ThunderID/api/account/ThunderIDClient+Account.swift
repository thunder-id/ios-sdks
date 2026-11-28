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
           var claims = try? decodeJwtToken(token) as [String: AnyCodable],
           let sub = claims["sub"]?.value as? String, !sub.isEmpty {
            // The ID token fills in claims the access token lacks, such as the user's name after an app-native sign-in.
            if let idToken = tokenStore?.idToken(),
               let idClaims = try? decodeJwtToken(idToken) as [String: AnyCodable],
               idClaims["sub"]?.value as? String == sub {
                claims.merge(idClaims) { fromAccessToken, _ in fromAccessToken }
            }
            let user = User(claims: claims)
            currentUser = user
            return user
        }
        let userinfo = try await discoveredEndpoint(\.userinfoEndpoint, fallback: "/oauth2/userinfo")
        let user: User = try await httpClient!.get(url: userinfo)
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

    /// Sets one of the signed-in user's own credentials via `POST /users/me/update-credentials`.
    ///
    /// When the user holds the credential, the server checks `currentValue` against it: a missing value
    /// fails with server code `USR-1047` and a wrong one with `USR-1048` (see ``ThunderIDError/serverError``).
    /// When the user does not hold it yet, leave `currentValue` empty: the server then asks for a recent
    /// sign-in and, when the sign-in is too old, fails with `AUTH-4011` and an
    /// ``ThunderIDError/authenticationChallenge`` whose `maxAge` bounds the next sign-in.
    ///
    /// Replacing a held credential revokes the user's tokens, including the one this client holds, so
    /// sign the user in again afterwards.
    ///
    /// - Parameters:
    ///   - attribute: The credential the user type's schema declares, such as `password`.
    ///   - currentValue: The credential's current value. Sent only when not empty.
    ///   - newValue: The value to set.
    /// - Throws: ``ThunderIDErrorCode/invalidInput`` before any request when `attribute` is blank or
    ///   `newValue` is empty; otherwise the server's error.
    func updateUserCredentials(
        attribute: String = "password",
        currentValue: String? = nil,
        newValue: String
    ) async throws {
        try requireInitialized()
        let name = attribute.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !newValue.isEmpty else {
            throw ThunderIDError(code: .invalidInput, message: "A credential name and a new value are required")
        }
        var body: [String: Any] = ["name": name, "newValue": newValue]
        if let currentValue, !currentValue.isEmpty {
            body["currentValue"] = currentValue
        }
        let _: EmptyResponse = try await httpClient!.post(
            path: "/users/me/update-credentials",
            body: body,
            isSensitive: true
        )
    }

    /// Overrides the cached user, e.g. after merging in freshly-fetched `/users/me` attributes.
    func setCachedUser(_ user: User) {
        currentUser = user
    }
}
