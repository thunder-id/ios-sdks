// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

public extension ApplicationsAPI {
    // MARK: - Sharing

    /// Returns a page of the policies that share an application into other organization units.
    func sharingPolicies(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> SharingPolicyListResponse {
        try await transport.sharingPolicies(id, limit: limit, offset: offset, fetcher: fetcher)
    }

    /// Returns one of an application's sharing policies.
    func sharingPolicy(id: String, policyId: String, fetcher: ThunderIDFetcher? = nil) async throws -> SharingPolicy {
        try await transport.sharingPolicy(id, policyId: policyId, fetcher: fetcher)
    }

    /// Shares an application into other organization units and returns the recorded policy.
    func createSharingPolicy(id: String, _ policy: SharingPolicyRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> SharingPolicy {
        try await transport.createSharingPolicy(id, policy, fetcher: fetcher)
    }

    /// Replaces one of an application's sharing policies and returns it.
    func updateSharingPolicy(
        id: String,
        policyId: String,
        _ policy: SharingPolicyUpdateRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> SharingPolicy {
        try await transport.updateSharingPolicy(id, policyId: policyId, policy, fetcher: fetcher)
    }

    /// Deletes one of an application's sharing policies.
    func deleteSharingPolicy(id: String, policyId: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.deleteSharingPolicy(id, policyId: policyId, fetcher: fetcher)
    }

    /// Returns what an application looks like from an organization unit: whether it is visible there and
    /// how each attribute may be overlaid.
    func overlayRules(id: String, ouId: String, fetcher: ThunderIDFetcher? = nil) async throws -> ResolvedOverlay {
        try await transport.overlayRules(id, ouId: ouId, fetcher: fetcher)
    }

    // MARK: - Lifecycle

    /// Suspends an application through the configured application suspension flow. There is no
    /// management API for it, so it throws ``ThunderIDErrorCode/administrationFlowNotConfigured`` when no
    /// flow is configured.
    func suspend(id: String, operatorNote: String? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> AccountLifecycleResult {
        try await transport.runLifecycleFlow(
            .applicationSuspend,
            subject: id,
            operatorNote: operatorNote,
            action: "application suspension",
            fetcher: fetcher
        )
    }

    /// Lifts an application's suspension through the configured flow. See
    /// ``suspend(id:operatorNote:fetcher:)``.
    func unsuspend(id: String, operatorNote: String? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> AccountLifecycleResult {
        try await transport.runLifecycleFlow(
            .applicationUnsuspend,
            subject: id,
            operatorNote: operatorNote,
            action: "application unsuspension",
            fetcher: fetcher
        )
    }
}
