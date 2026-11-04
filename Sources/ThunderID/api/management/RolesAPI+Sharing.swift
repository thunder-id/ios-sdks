// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

public extension RolesAPI {
    // MARK: - Sharing

    /// Returns a page of the policies that share a role into other organization units.
    func sharingPolicies(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> SharingPolicyListResponse {
        try await transport.sharingPolicies(id, limit: limit, offset: offset, fetcher: fetcher)
    }

    /// Returns one of a role's sharing policies.
    func sharingPolicy(id: String, policyId: String, fetcher: ThunderIDFetcher? = nil) async throws -> SharingPolicy {
        try await transport.sharingPolicy(id, policyId: policyId, fetcher: fetcher)
    }

    /// Shares a role into other organization units and returns the recorded policy.
    func createSharingPolicy(id: String, _ policy: SharingPolicyRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> SharingPolicy {
        try await transport.createSharingPolicy(id, policy, fetcher: fetcher)
    }

    /// Replaces one of a role's sharing policies and returns it.
    func updateSharingPolicy(
        id: String,
        policyId: String,
        _ policy: SharingPolicyUpdateRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> SharingPolicy {
        try await transport.updateSharingPolicy(id, policyId: policyId, policy, fetcher: fetcher)
    }

    /// Deletes one of a role's sharing policies.
    func deleteSharingPolicy(id: String, policyId: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.deleteSharingPolicy(id, policyId: policyId, fetcher: fetcher)
    }

    /// Returns what a role looks like from an organization unit: whether it is visible there and what
    /// the unit may do with its `assignments`.
    func overlayRules(id: String, ouId: String, fetcher: ThunderIDFetcher? = nil) async throws -> ResolvedOverlay {
        try await transport.overlayRules(id, ouId: ouId, fetcher: fetcher)
    }
}
