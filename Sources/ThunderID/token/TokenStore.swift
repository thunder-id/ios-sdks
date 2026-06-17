import Foundation

private enum StoreKey {
    static let accessToken = "thunder.access_token"
    static let refreshToken = "thunder.refresh_token"
    static let idToken = "thunder.id_token"
    static let tokenExpiry = "thunder.token_expiry"
    static let scope = "thunder.scope"
}

/// Persists and retrieves the token set using the configured StorageAdapter.
final class TokenStore {
    private let storage: StorageAdapter

    init(storage: StorageAdapter) {
        self.storage = storage
    }

    func save(_ tokenResponse: TokenResponse) throws {
        try storage.store(key: StoreKey.accessToken, value: tokenResponse.accessToken)
        if let refresh = tokenResponse.refreshToken {
            try storage.store(key: StoreKey.refreshToken, value: refresh)
        }
        if let id = tokenResponse.idToken {
            try storage.store(key: StoreKey.idToken, value: id)
        }
        if let expires = tokenResponse.expiresIn {
            let expiry = Date().addingTimeInterval(TimeInterval(expires))
            try storage.store(key: StoreKey.tokenExpiry, value: String(expiry.timeIntervalSince1970))
        }
        if let scope = tokenResponse.scope {
            try storage.store(key: StoreKey.scope, value: scope)
        }
    }

    func accessToken() -> String? { storage.retrieve(key: StoreKey.accessToken) }
    func refreshToken() -> String? { storage.retrieve(key: StoreKey.refreshToken) }
    func idToken() -> String? { storage.retrieve(key: StoreKey.idToken) }

    func tokenExpiry() -> Date? {
        guard let raw = storage.retrieve(key: StoreKey.tokenExpiry),
              let interval = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    func isNearExpiry(threshold: TimeInterval = 60) -> Bool {
        guard let expiry = tokenExpiry() else { return true }
        return Date().addingTimeInterval(threshold) >= expiry
    }

    func clear() { storage.clear() }
}
