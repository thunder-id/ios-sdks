// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The payload used to create a user in the organization unit a handle path names.
public struct CreateUserByPathRequest: Codable {
    public var type: String
    public var attributes: [String: AnyCodable]?

    public init(type: String, attributes: [String: AnyCodable]? = nil) {
        self.type = type
        self.attributes = attributes
    }
}

public extension UsersAPI {
    // MARK: - By organization unit path

    /// Returns a page of the users in the organization unit a handle path such as `engineering/frontend`
    /// names: the users it owns, then the users shared into it. Each segment is encoded on its own.
    func list(
        path: String,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ManagedUserListResponse {
        try await transport.send(
            "GET",
            ["tree"] + ManagementPath.tree(path),
            query: .page(limit, offset) + .management([("include", "display")]),
            fetcher: fetcher
        )
    }

    /// Creates a user in the organization unit a handle path names, and returns it as the server stored it.
    func create(path: String, _ user: CreateUserByPathRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> ManagedUser {
        try await transport.send("POST", ["tree"] + ManagementPath.tree(path), body: user, fetcher: fetcher)
    }

    // MARK: - Sharing

    /// Returns a page of the policies that share a user into other organization units.
    func sharingPolicies(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> SharingPolicyListResponse {
        try await transport.sharingPolicies(id, limit: limit, offset: offset, fetcher: fetcher)
    }

    /// Returns one of a user's sharing policies.
    func sharingPolicy(id: String, policyId: String, fetcher: ThunderIDFetcher? = nil) async throws -> SharingPolicy {
        try await transport.sharingPolicy(id, policyId: policyId, fetcher: fetcher)
    }

    /// Shares a user into other organization units and returns the recorded policy.
    func createSharingPolicy(id: String, _ policy: SharingPolicyRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> SharingPolicy {
        try await transport.createSharingPolicy(id, policy, fetcher: fetcher)
    }

    /// Replaces one of a user's sharing policies and returns it.
    func updateSharingPolicy(
        id: String,
        policyId: String,
        _ policy: SharingPolicyUpdateRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> SharingPolicy {
        try await transport.updateSharingPolicy(id, policyId: policyId, policy, fetcher: fetcher)
    }

    /// Deletes one of a user's sharing policies.
    func deleteSharingPolicy(id: String, policyId: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.deleteSharingPolicy(id, policyId: policyId, fetcher: fetcher)
    }

    /// Returns what a user looks like from an organization unit: whether it is visible there and how
    /// each attribute may be overlaid.
    func overlayRules(id: String, ouId: String, fetcher: ThunderIDFetcher? = nil) async throws -> ResolvedOverlay {
        try await transport.overlayRules(id, ouId: ouId, fetcher: fetcher)
    }

    // MARK: - Lifecycle

    /// Suspends a user through the configured user suspension flow. There is no management API for it,
    /// so it throws ``ThunderIDErrorCode/administrationFlowNotConfigured`` when no flow is configured.
    func suspend(id: String, operatorNote: String? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> AccountLifecycleResult {
        try await transport.runLifecycleFlow(
            .userSuspend,
            subject: id,
            operatorNote: operatorNote,
            action: "user suspension",
            fetcher: fetcher
        )
    }

    /// Lifts a user's suspension through the configured flow. See ``suspend(id:operatorNote:fetcher:)``.
    func unsuspend(id: String, operatorNote: String? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> AccountLifecycleResult {
        try await transport.runLifecycleFlow(
            .userUnsuspend,
            subject: id,
            operatorNote: operatorNote,
            action: "user unsuspension",
            fetcher: fetcher
        )
    }

    /// Unlocks a user locked after failed sign-in attempts, through the configured flow. See
    /// ``suspend(id:operatorNote:fetcher:)``.
    func unlock(id: String, operatorNote: String? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> AccountLifecycleResult {
        try await transport.runLifecycleFlow(
            .userUnlock,
            subject: id,
            operatorNote: operatorNote,
            action: "user unlock",
            fetcher: fetcher
        )
    }
}
