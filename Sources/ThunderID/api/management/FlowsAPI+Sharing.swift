// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The values an organization unit has set for a flow's variables, keyed by variable identifier. Each
/// value is a string, a number or a boolean. A variable the unit has not set is absent, and the flow's
/// own value applies to it.
public struct FlowVariablesResponse: Codable {
    public let values: [String: AnyCodable]
}

/// Sets an organization unit's values for a flow's variables. It replaces every value the unit set.
public struct FlowVariablesRequest: Codable {
    /// The organization unit whose values are set. The flow has to be owned by, or shared with, it.
    public var ouId: String
    /// The value of each variable, keyed by identifier: a string, a number or a boolean, never null.
    public var values: [String: AnyCodable]

    public init(ouId: String, values: [String: AnyCodable]) {
        self.ouId = ouId
        self.values = values
    }
}

public extension FlowsAPI {
    // MARK: - Variables

    /// Returns the values an organization unit has set for a flow's variables.
    /// - Parameter ouId: The organization unit to read for. The flow has to be owned by, or shared with, it.
    func variables(id: String, ouId: String, fetcher: ThunderIDFetcher? = nil) async throws
        -> FlowVariablesResponse {
        try await transport.send("GET", [id, "variables"], query: .management([("ouId", ouId)]), fetcher: fetcher)
    }

    /// Replaces the values an organization unit has set for a flow's variables and returns them.
    func updateVariables(id: String, _ variables: FlowVariablesRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> FlowVariablesResponse {
        try await transport.send("PUT", [id, "variables"], body: variables, fetcher: fetcher)
    }

    // MARK: - Sharing

    /// Returns a page of the policies that share a flow into other organization units.
    func sharingPolicies(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> SharingPolicyListResponse {
        try await transport.sharingPolicies(id, limit: limit, offset: offset, fetcher: fetcher)
    }

    /// Returns one of a flow's sharing policies.
    func sharingPolicy(id: String, policyId: String, fetcher: ThunderIDFetcher? = nil) async throws -> SharingPolicy {
        try await transport.sharingPolicy(id, policyId: policyId, fetcher: fetcher)
    }

    /// Shares a flow into other organization units and returns the recorded policy.
    func createSharingPolicy(id: String, _ policy: SharingPolicyRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> SharingPolicy {
        try await transport.createSharingPolicy(id, policy, fetcher: fetcher)
    }

    /// Replaces one of a flow's sharing policies and returns it.
    func updateSharingPolicy(
        id: String,
        policyId: String,
        _ policy: SharingPolicyUpdateRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> SharingPolicy {
        try await transport.updateSharingPolicy(id, policyId: policyId, policy, fetcher: fetcher)
    }

    /// Deletes one of a flow's sharing policies.
    func deleteSharingPolicy(id: String, policyId: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.deleteSharingPolicy(id, policyId: policyId, fetcher: fetcher)
    }

    /// Returns what a flow looks like from an organization unit: whether it is visible there and the
    /// effective rule for each variable a policy named, keyed `variables.<identifier>`.
    func overlayRules(id: String, ouId: String, fetcher: ThunderIDFetcher? = nil) async throws -> ResolvedOverlay {
        try await transport.overlayRules(id, ouId: ouId, fetcher: fetcher)
    }
}
