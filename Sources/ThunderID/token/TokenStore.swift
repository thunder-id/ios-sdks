// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

private enum StoreKey {
    static let accessToken = "thunder.access_token"
    static let refreshToken = "thunder.refresh_token"
    static let idToken = "thunder.id_token"
    static let tokenExpiry = "thunder.token_expiry"
    static let scope = "thunder.scope"
    static let createdAt = "thunder.created_at"
    static let sessionHandle = "thunder.session_handle"
}

/// Persists and retrieves the token set using the configured StorageAdapter.
final class TokenStore {
    private let storage: StorageAdapter

    init(storage: StorageAdapter) {
        self.storage = storage
    }

    /// Saves `tokenResponse`. `createdAt`, when given, is stored with it and the expiry counts from it,
    /// for a token that is reused until it nears expiry and then requested again.
    func save(_ tokenResponse: TokenResponse, createdAt: Date? = nil) throws {
        try storage.store(key: StoreKey.accessToken, value: tokenResponse.accessToken)
        if let createdAt {
            try storage.store(key: StoreKey.createdAt, value: String(createdAt.timeIntervalSince1970))
        }
        if let refresh = tokenResponse.refreshToken {
            try storage.store(key: StoreKey.refreshToken, value: refresh)
        }
        if let id = tokenResponse.idToken {
            try storage.store(key: StoreKey.idToken, value: id)
        }
        if let expires = tokenResponse.expiresIn {
            let expiry = (createdAt ?? Date()).addingTimeInterval(TimeInterval(expires))
            try storage.store(key: StoreKey.tokenExpiry, value: String(expiry.timeIntervalSince1970))
        }
        if let scope = tokenResponse.scope {
            try storage.store(key: StoreKey.scope, value: scope)
        }
    }

    func accessToken() -> String? { storage.retrieve(key: StoreKey.accessToken) }
    func refreshToken() -> String? { storage.retrieve(key: StoreKey.refreshToken) }
    func idToken() -> String? { storage.retrieve(key: StoreKey.idToken) }

    func createdAt() -> Date? {
        guard let raw = storage.retrieve(key: StoreKey.createdAt),
              let interval = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    func tokenExpiry() -> Date? {
        guard let raw = storage.retrieve(key: StoreKey.tokenExpiry),
              let interval = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    func isNearExpiry(threshold: TimeInterval = 60) -> Bool {
        guard let expiry = tokenExpiry() else { return true }
        return Date().addingTimeInterval(threshold) >= expiry
    }

    /// Removes the stored access token, keeping anything else, such as the session handle.
    func clearAccessToken() {
        [StoreKey.accessToken, StoreKey.tokenExpiry, StoreKey.scope, StoreKey.createdAt].forEach(storage.delete)
    }

    // MARK: - Backend session handle

    /// The opaque handle of the session the app's backend holds, when sign-in runs on a backend. It is
    /// a credential: it is never logged.
    func sessionHandle() -> String? { storage.retrieve(key: StoreKey.sessionHandle) }

    func saveSessionHandle(_ handle: String) throws {
        try storage.store(key: StoreKey.sessionHandle, value: handle)
    }

    func clear() { storage.clear() }
}
