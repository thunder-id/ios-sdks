// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderIDSwiftUI

/// Checks for the management API (groups, roles, memberships, types) and the permission helpers.
/// The read checks only list and get; Group and role writes is the one check that changes the
/// server, so it runs only on tap and deletes what it creates.
extension CheckContext {
    static let managementRunners: [CapabilityID: Runner] = [
        .managementEndpoints: { try await $0.managementEndpoints() },
        .groups: { try await $0.groups() },
        .groupMembers: { try await $0.groupMembers() },
        .roles: { try await $0.roles() },
        .roleAssignments: { try await $0.roleAssignments() },
        .userGroups: { try await $0.userGroups() },
        .agentTypes: { try await $0.agentTypes() },
        .agentMemberships: { try await $0.agentMemberships() },
        .adminWrites: { try await $0.adminWrites() },
        .permissionHierarchy: { try $0.permissionHierarchy() },
        .grantedPermissions: { try await $0.grantedPermissions() }
    ]

    // MARK: - Management endpoints

    /// Compares the URL each collection should resolve to with the URL the SDK actually requests.
    /// A probe fetcher records the request and stops it, so nothing reaches the server.
    func managementEndpoints() async throws -> String {
        let resolved = config.resolvedEndpoints
        let moved = resolved.filter { $0.source != .baseUrl }.map(\.collection.path)
        let summary = moved.isEmpty
            ? "all \(resolved.count) collections on \(config.hostLabel)"
            : "\(moved.count) of \(resolved.count) collections overridden (\(moved.joined(separator: ", ")))"
        guard (try? await client.isSignedIn()) == true else {
            return "Resolved from config: \(summary). Sign in to confirm against the SDK's requests."
        }
        var mismatches: [String] = []
        for endpoint in resolved {
            let requested = await requestedURL(endpoint.collection.path)
            log.record("endpoint:resolved", "\(endpoint.collection.path) → \(requested ?? "no request")")
            if requested != endpoint.url {
                mismatches.append("\(endpoint.collection.path) went to \(requested ?? "nothing")")
            }
        }
        guard mismatches.isEmpty else {
            throw CheckFailure(mismatches.joined(separator: "; "))
        }
        return "SDK requests match: \(summary)"
    }

    /// The collection URL (without the query) the SDK builds for a list call on `path`.
    private func requestedURL(_ path: String) async -> String? {
        let probe = RequestProbe()
        let fetcher = probe.fetcher
        switch path {
        case "applications": _ = try? await client.applications.list(limit: 1, fetcher: fetcher)
        case "users": _ = try? await client.users.list(limit: 1, fetcher: fetcher)
        case "user-types": _ = try? await client.users.types(limit: 1, fetcher: fetcher)
        case "groups": _ = try? await client.groups.list(limit: 1, fetcher: fetcher)
        case "roles": _ = try? await client.roles.list(limit: 1, fetcher: fetcher)
        case "agents": _ = try? await client.agents.list(limit: 1, fetcher: fetcher)
        case "agent-types": _ = try? await client.agents.types(limit: 1, fetcher: fetcher)
        default: return nil
        }
        return probe.collectionURL
    }

    // MARK: - Groups

    func groups() async throws -> String {
        try await requireSignedIn()
        let page = try await client.groups.list(limit: 20)
        log.record("groups:listed", "\(page.totalResults) total", kind: .success)
        guard let first = page.groups.first else {
            return "groups.list() works; the server has no groups yet. Run Group and role writes."
        }
        let group = try await client.groups.get(id: first.id)
        guard group.id == first.id else {
            throw CheckFailure("groups.get(id:) returned \(group.id) for \(first.id)")
        }
        ids.groupId = group.id
        return "\(page.totalResults) groups; fetched \"\(group.name)\" in \(group.ouHandle ?? group.ouId)"
    }

    func groupMembers() async throws -> String {
        try await requireSignedIn()
        let groupId = try await firstGroupId()
        let page = try await client.groups.members(id: groupId, limit: 50)
        log.record("groups:members", "\(page.totalResults) in \(groupId)", kind: .success)
        return "\(page.totalResults) members (\(tally(page.members.map(\.type.rawValue)))) in \(short(groupId))"
    }

    // MARK: - Roles

    func roles() async throws -> String {
        try await requireSignedIn()
        let page = try await client.roles.list(limit: 20)
        log.record("roles:listed", "\(page.totalResults) total", kind: .success)
        guard let first = page.roles.first else {
            return "roles.list() works; the server has no roles yet. Run Group and role writes."
        }
        let role = try await client.roles.get(id: first.id)
        ids.roleId = role.id
        let permissions = role.permissions.reduce(0) { $0 + $1.permissions.count }
        return "\(page.totalResults) roles; \"\(role.name)\" grants \(permissions) permissions "
            + "on \(role.permissions.count) resource servers"
    }

    /// Reads every assignment, then only the user assignments, to exercise the `type` filter.
    func roleAssignments() async throws -> String {
        try await requireSignedIn()
        let roleId = try await firstRoleId()
        let all = try await client.roles.assignments(id: roleId, limit: 50)
        let users = try await client.roles.assignments(id: roleId, type: .user, limit: 50)
        guard users.assignments.allSatisfy({ $0.type == .user }) else {
            throw CheckFailure("assignments(type: .user) returned other assignee types")
        }
        log.record("roles:assignments", "\(all.totalResults) on \(roleId)", kind: .success)
        return "\(all.totalResults) assignments (\(tally(all.assignments.map(\.type.rawValue)))); "
            + "type filter returned \(users.totalResults) users"
    }

    // MARK: - Users and agents

    func userGroups() async throws -> String {
        try await requireSignedIn()
        let userId = try await ownUserId()
        let groups = try await client.users.groups(id: userId, limit: 50)
        let types = try await client.users.types(limit: 20)
        ids.userId = userId
        log.record("users:groups", "\(groups.totalResults) for \(userId)", kind: .success)
        let names = groups.groups.prefix(3).map(\.name).joined(separator: ", ")
        return "Member of \(groups.totalResults) groups\(names.isEmpty ? "" : " (\(names))"); "
            + "\(types.totalResults) user types (\(types.types.prefix(3).map(\.handle).joined(separator: ", ")))"
    }

    func agentTypes() async throws -> String {
        try await requireSignedIn()
        let page = try await client.agents.types(limit: 20)
        log.record("agents:types", "\(page.totalResults) total", kind: .success)
        let handles = page.types.prefix(4).map(\.handle).joined(separator: ", ")
        return "\(page.totalResults) agent types\(handles.isEmpty ? "" : ": \(handles)")"
    }

    func agentMemberships() async throws -> String {
        try await requireSignedIn()
        let agentId: String
        if let known = ids.agentId {
            agentId = known
        } else if let first = try await client.agents.list(limit: 1).agents.first {
            agentId = first.id
        } else {
            throw CheckFailure("The server has no agents. Create one to check its groups and roles.")
        }
        ids.agentId = agentId
        let groups = try await client.agents.groups(id: agentId, limit: 50)
        let roles = try await client.agents.roles(id: agentId, limit: 50)
        log.record("agents:memberships", "\(groups.totalResults) groups, \(roles.totalResults) roles", kind: .success)
        return "Agent \(short(agentId)): \(groups.totalResults) groups, \(roles.totalResults) roles"
            + (roles.roles.isEmpty ? "" : " (\(roles.roles.prefix(3).joined(separator: ", ")))")
    }

    // MARK: - Lookups

    func firstGroupId() async throws -> String {
        if let known = ids.groupId { return known }
        guard let first = try await client.groups.list(limit: 1).groups.first else {
            throw CheckFailure("The server has no groups. Run Group and role writes, or create one.")
        }
        ids.groupId = first.id
        return first.id
    }

    func firstRoleId() async throws -> String {
        if let known = ids.roleId { return known }
        guard let first = try await client.roles.list(limit: 1).roles.first else {
            throw CheckFailure("The server has no roles. Create one to check its assignments.")
        }
        ids.roleId = first.id
        return first.id
    }

    /// The signed-in user's own ID from their profile, or the first listed user when profile
    /// fetching is off.
    func ownUserId() async throws -> String {
        if let profile = try? await client.getUserProfile() { return profile.id }
        if let sub = state.user?.sub { return sub }
        guard let first = try await client.users.list(limit: 1).users.first else {
            throw CheckFailure("No user to read groups for")
        }
        return first.id
    }

    /// The organization unit new resources go into: the `ouId` claim, or the user's profile.
    func ownOuId() async throws -> String {
        if let claim = state.user?["ouId"] as? String, !claim.isEmpty { return claim }
        guard let ouId = try await client.getUserProfile().ouId else {
            throw CheckFailure("The signed-in user has no organization unit to create resources in")
        }
        return ouId
    }

    func tally(_ types: [String]) -> String {
        let counts = Dictionary(grouping: types) { $0 }.mapValues(\.count)
        guard !counts.isEmpty else { return "none" }
        return counts.keys.sorted().map { "\(counts[$0] ?? 0) \($0)" }.joined(separator: ", ")
    }

    func short(_ id: String) -> String {
        id.count > 12 ? String(id.prefix(8)) + "…" : id
    }
}

/// A fetcher that records the request the SDK built and stops it before it reaches the network.
private final class RequestProbe {
    private struct Stopped: Error {}

    private(set) var url: URL?

    var fetcher: ThunderIDFetcher {
        { [self] request in
            url = request.url
            throw Stopped()
        }
    }

    var collectionURL: String? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.query = nil
        return components.string
    }
}
