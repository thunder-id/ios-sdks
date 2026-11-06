// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// The kinds of resource that can be shared into other organization units.
public enum SharingResourceType: String, CaseIterable {
    case user
    case application
    case role
    case flow
}

/// The input of ``ThunderIDState/updateSharingPolicyMutation(resourceType:fetcher:)``.
public struct SharingPolicyUpdateInput {
    public let resourceId: String
    public let policyId: String
    public let request: SharingPolicyUpdateRequest

    public init(resourceId: String, policyId: String, request: SharingPolicyUpdateRequest) {
        self.resourceId = resourceId
        self.policyId = policyId
        self.request = request
    }
}

/// Reactive wrappers over the sharing policy and overlay rule operations of users, applications, roles
/// and flows. Each accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public extension ThunderIDState {
    func sharingPoliciesQuery(
        resourceType: SharingResourceType,
        resourceId: String,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) -> ResourceQuery<SharingPolicyListResponse> {
        let operations = SharingOperations(client: client, type: resourceType, fetcher: fetcher)
        let key = [SharingQueryKeys.sharingPolicies, resourceType.rawValue, resourceId]
            + listKey("", ["limit": limit, "offset": offset]).dropFirst()
        return query(key: key) { try await operations.list(resourceId, limit: limit, offset: offset) }
    }

    /// What the resource looks like from `ouId`: whether it is visible there and how each attribute may
    /// be overlaid.
    func overlayRulesQuery(
        resourceType: SharingResourceType,
        resourceId: String,
        ouId: String,
        fetcher: ThunderIDFetcher? = nil
    ) -> ResourceQuery<ResolvedOverlay> {
        let operations = SharingOperations(client: client, type: resourceType, fetcher: fetcher)
        return query(key: [SharingQueryKeys.overlayRules, resourceType.rawValue, resourceId, ouId]) {
            try await operations.overlayRules(resourceId, ouId: ouId)
        }
    }

    func createSharingPolicyMutation(resourceType: SharingResourceType, fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<(resourceId: String, request: SharingPolicyRequest), SharingPolicy> {
        let operations = SharingOperations(client: client, type: resourceType, fetcher: fetcher)
        return mutation(
            invalidating: { sharingKeys(resourceType, $0.resourceId) },
            perform: { input in try await operations.create(input.resourceId, input.request) }
        )
    }

    func updateSharingPolicyMutation(resourceType: SharingResourceType, fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<SharingPolicyUpdateInput, SharingPolicy> {
        let operations = SharingOperations(client: client, type: resourceType, fetcher: fetcher)
        return mutation(
            invalidating: { sharingKeys(resourceType, $0.resourceId) },
            perform: { input in try await operations.update(input.resourceId, input.policyId, input.request) }
        )
    }

    func deleteSharingPolicyMutation(resourceType: SharingResourceType, fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<(resourceId: String, policyId: String), Void> {
        let operations = SharingOperations(client: client, type: resourceType, fetcher: fetcher)
        return mutation(
            invalidating: { sharingKeys(resourceType, $0.resourceId) },
            perform: { input in try await operations.delete(input.resourceId, input.policyId) }
        )
    }
}

private func sharingKeys(_ type: SharingResourceType, _ resourceId: String) -> [[String]] {
    [
        [SharingQueryKeys.sharingPolicies, type.rawValue, resourceId],
        [SharingQueryKeys.overlayRules, type.rawValue, resourceId]
    ]
}

/// Routes the sharing operations to the API of one resource type.
private struct SharingOperations {
    let client: ThunderIDClient
    let type: SharingResourceType
    let fetcher: ThunderIDFetcher?

    func list(_ id: String, limit: Int?, offset: Int?) async throws -> SharingPolicyListResponse {
        switch type {
        case .user:
            return try await client.users.sharingPolicies(id: id, limit: limit, offset: offset, fetcher: fetcher)
        case .application:
            return try await client.applications.sharingPolicies(id: id, limit: limit, offset: offset, fetcher: fetcher)
        case .role:
            return try await client.roles.sharingPolicies(id: id, limit: limit, offset: offset, fetcher: fetcher)
        case .flow:
            return try await client.flows.sharingPolicies(id: id, limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func create(_ id: String, _ policy: SharingPolicyRequest) async throws -> SharingPolicy {
        switch type {
        case .user: return try await client.users.createSharingPolicy(id: id, policy, fetcher: fetcher)
        case .application: return try await client.applications.createSharingPolicy(id: id, policy, fetcher: fetcher)
        case .role: return try await client.roles.createSharingPolicy(id: id, policy, fetcher: fetcher)
        case .flow: return try await client.flows.createSharingPolicy(id: id, policy, fetcher: fetcher)
        }
    }

    func update(_ id: String, _ policyId: String, _ policy: SharingPolicyUpdateRequest) async throws -> SharingPolicy {
        switch type {
        case .user:
            return try await client.users.updateSharingPolicy(id: id, policyId: policyId, policy, fetcher: fetcher)
        case .application:
            return try await client.applications.updateSharingPolicy(
                id: id,
                policyId: policyId,
                policy,
                fetcher: fetcher
            )
        case .role:
            return try await client.roles.updateSharingPolicy(id: id, policyId: policyId, policy, fetcher: fetcher)
        case .flow:
            return try await client.flows.updateSharingPolicy(id: id, policyId: policyId, policy, fetcher: fetcher)
        }
    }

    func delete(_ id: String, _ policyId: String) async throws {
        switch type {
        case .user: try await client.users.deleteSharingPolicy(id: id, policyId: policyId, fetcher: fetcher)
        case .application:
            try await client.applications.deleteSharingPolicy(id: id, policyId: policyId, fetcher: fetcher)
        case .role: try await client.roles.deleteSharingPolicy(id: id, policyId: policyId, fetcher: fetcher)
        case .flow: try await client.flows.deleteSharingPolicy(id: id, policyId: policyId, fetcher: fetcher)
        }
    }

    func overlayRules(_ id: String, ouId: String) async throws -> ResolvedOverlay {
        switch type {
        case .user: return try await client.users.overlayRules(id: id, ouId: ouId, fetcher: fetcher)
        case .application: return try await client.applications.overlayRules(id: id, ouId: ouId, fetcher: fetcher)
        case .role: return try await client.roles.overlayRules(id: id, ouId: ouId, fetcher: fetcher)
        case .flow: return try await client.flows.overlayRules(id: id, ouId: ouId, fetcher: fetcher)
        }
    }
}
