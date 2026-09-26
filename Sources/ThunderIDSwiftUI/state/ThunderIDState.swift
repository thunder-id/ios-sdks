// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// Reactive auth state for SwiftUI views. Held as @StateObject in ThunderIDProvider.
@MainActor
public final class ThunderIDState: ObservableObject {
    @Published public private(set) var user: User?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isInitialized: Bool = false
    @Published public private(set) var error: String?

    public let client: ThunderIDClient
    public let i18n: ThunderIDI18n
    /// Coordinates refetching between the management queries and mutations built from this state.
    public let invalidator = ResourceInvalidator()

    /// Mirrors ``ThunderIDConfig/fetchUserProfile``.
    public private(set) var fetchUserProfileEnabled: Bool = true

    /// Cached `GET /users/me/meta` result, shared by every mounted view that needs the user type
    /// schema (e.g. `UserProfile` and `ChangeCredential`), so a screen that mounts several of them
    /// issues one request instead of one per view.
    private var userSchema: [String: AttributeSchema]?
    private var schemaTask: Task<[String: AttributeSchema], Error>?

    public var isSignedIn: Bool { user != nil }

    init(client: ThunderIDClient, i18n: ThunderIDI18n) {
        self.client = client
        self.i18n = i18n
    }

    func initialize(config: ThunderIDConfig) async {
        isLoading = true
        defer { isLoading = false }
        fetchUserProfileEnabled = config.fetchUserProfile
        do {
            _ = try await client.initialize(config: config)
            let signedIn = await (try? client.isSignedIn()) ?? false
            if signedIn {
                user = try? await client.getUser()
                if fetchUserProfileEnabled { launchUserProfileSync() }
            }
            isInitialized = true
            error = nil
        } catch {
            self.error = error.localizedDescription
            isInitialized = true
        }
    }

    /// Refreshes sign-in state (call after signIn/signOut).
    public func refresh() async {
        guard isInitialized else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let signedIn = try await client.isSignedIn()
            user = signedIn ? try await client.getUser() : nil
            userSchema = nil
            schemaTask = nil
            if signedIn && fetchUserProfileEnabled { launchUserProfileSync() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Returns the cached user type schema, fetching it once on first access. Concurrent callers
    /// during that first fetch share the same in-flight request rather than issuing their own.
    public func getUserSchema() async throws -> [String: AttributeSchema] {
        if let userSchema { return userSchema }
        if let schemaTask { return try await schemaTask.value }
        let task = Task { try await client.getUserSchema() }
        schemaTask = task
        defer { schemaTask = nil }
        let schema = try await task.value
        userSchema = schema
        return schema
    }

    /// Merges `profile`'s attributes into `user`'s claims and syncs the client's cache to match.
    func mergeUserProfile(_ profile: ThunderID.UserProfile) {
        guard let current = user else { return }
        let merged = User(claims: current.claims.merging(profile.attributes) { _, new in new })
        user = merged
        client.setCachedUser(merged)
    }

    private func launchUserProfileSync() {
        Task {
            guard let profile = try? await client.getUserProfile() else { return }
            mergeUserProfile(profile)
        }
    }

    /// Switches the active UI locale.
    public func setLocale(_ locale: String) {
        i18n.setLocale(locale)
    }
}
