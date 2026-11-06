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
    static let deviceSecret = "thunder.device_secret"
    static let flowSessions = "thunder.flow_sessions"
}

/// An SSO session handle as stored, with when it ends.
private struct StoredFlowSession: Codable {
    let flowIdentifier: String
    let sessionHandle: String
    /// Seconds since 1970, or `nil` when the server gave no expiry.
    let expiresAt: TimeInterval?
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
        if let secret = tokenResponse.deviceSecret {
            try storage.store(key: StoreKey.deviceSecret, value: secret)
        }
    }

    /// Replaces the stored session with `tokenResponse`: nothing of the previous one, such as a refresh
    /// token bound to another organization unit, carries over. The device secret is kept when the response
    /// brings none, and the flow sessions are kept, since both belong to the device's SSO session rather than
    /// to one sign-in.
    func replace(_ tokenResponse: TokenResponse) throws {
        let secret = tokenResponse.deviceSecret == nil ? deviceSecret() : nil
        [
            StoreKey.accessToken, StoreKey.refreshToken, StoreKey.idToken, StoreKey.tokenExpiry,
            StoreKey.scope, StoreKey.createdAt
        ].forEach(storage.delete)
        try save(tokenResponse)
        if let secret { try storage.store(key: StoreKey.deviceSecret, value: secret) }
    }

    /// The device secret a code exchange with the `device_sso` scope returned. It is a credential: it is
    /// never logged.
    func deviceSecret() -> String? { storage.retrieve(key: StoreKey.deviceSecret) }

    /// Drops a device secret the server no longer accepts.
    func removeDeviceSecret() { storage.delete(key: StoreKey.deviceSecret) }

    // MARK: - Flow sessions

    /// Keeps the SSO sessions an app-native flow step started, by flow identifier, and drops the ones in
    /// `cleared`. An expiry counts from `now`.
    func mergeFlowSessions(_ started: [EmbeddedFlowSessionData], cleared: [String], now: Date = Date()) throws {
        var held = Dictionary(storedFlowSessions().map { ($0.flowIdentifier, $0) }) { _, last in last }
        for session in started {
            held[session.flowIdentifier] = StoredFlowSession(
                flowIdentifier: session.flowIdentifier,
                sessionHandle: session.sessionHandle,
                expiresAt: session.expiresIn.map { now.addingTimeInterval(TimeInterval($0)).timeIntervalSince1970 }
            )
        }
        cleared.forEach { held.removeValue(forKey: $0) }
        let kept = held.values
            .filter { Self.isLive($0, at: now) }
            .sorted { $0.flowIdentifier < $1.flowIdentifier }
        guard !kept.isEmpty else {
            storage.delete(key: StoreKey.flowSessions)
            return
        }
        let value = String(data: try JSONEncoder().encode(kept), encoding: .utf8) ?? "[]"
        try storage.store(key: StoreKey.flowSessions, value: value)
    }

    /// The kept SSO session handles that have not expired. Each is a credential: it is never logged.
    func flowSessions(now: Date = Date()) -> [EmbeddedFlowSessionData] {
        storedFlowSessions()
            .filter { Self.isLive($0, at: now) }
            .map { EmbeddedFlowSessionData(flowIdentifier: $0.flowIdentifier, sessionHandle: $0.sessionHandle) }
    }

    private func storedFlowSessions() -> [StoredFlowSession] {
        guard let raw = storage.retrieve(key: StoreKey.flowSessions) else { return [] }
        return (try? JSONDecoder().decode([StoredFlowSession].self, from: Data(raw.utf8))) ?? []
    }

    private static func isLive(_ session: StoredFlowSession, at now: Date) -> Bool {
        session.expiresAt.map { $0 > now.timeIntervalSince1970 } ?? true
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

    /// Removes everything stored, the device secret and the flow sessions included.
    func clear() { storage.clear() }
}
