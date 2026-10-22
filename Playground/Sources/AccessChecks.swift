// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderIDSwiftUI

/// The write round trip and the permission checks.
extension CheckContext {
    // MARK: - Group and role writes

    /// Creates a throwaway group, adds and removes a member, assigns a role to the group and
    /// removes it, then deletes both. Whatever it created is deleted even when a step fails.
    func adminWrites() async throws -> String {
        try await requireSignedIn()
        let ouId = try await ownOuId()
        let name = "playground-\(UUID().uuidString.prefix(8).lowercased())"
        let group = try await client.groups.create(
            CreateGroupRequest(name: name, ouId: ouId, description: "Created by the iOS playground")
        )
        log.record("group:created", "\(group.name) (\(group.id))", kind: .success)
        var steps = ["group created"]
        do {
            if let member = try await exerciseMembers(groupId: group.id) { steps.append(member) }
            steps.append(try await exerciseRole(name: name, ouId: ouId, groupId: group.id))
        } catch {
            try? await client.groups.delete(id: group.id)
            log.record("group:deleted", "cleanup after failure")
            throw error
        }
        try await client.groups.delete(id: group.id)
        log.record("group:deleted", group.id, kind: .success)
        steps.append("group deleted")
        return steps.joined(separator: ", ")
    }

    /// Adds the first listed user to the group, confirms the membership, and removes it again.
    private func exerciseMembers(groupId: String) async throws -> String? {
        guard let userId = try await client.users.list(limit: 1).users.first?.id else { return nil }
        let member = GroupMemberInput(id: userId, type: .user)
        try await client.groups.addMembers(id: groupId, [member])
        let members = try await client.groups.members(id: groupId, limit: 50)
        guard members.members.contains(where: { $0.id == userId }) else {
            throw CheckFailure("addMembers succeeded but members(id:) does not list the user")
        }
        try await client.groups.removeMembers(id: groupId, [member])
        log.record("group:members", "added and removed \(userId)", kind: .success)
        return "member added and removed"
    }

    /// Creates a role already assigned to the group, checks the assignment, removes it and
    /// deletes the role.
    private func exerciseRole(name: String, ouId: String, groupId: String) async throws -> String {
        let assignee = RoleAssignmentInput(id: groupId, type: .group)
        let role = try await client.roles.create(CreateRoleRequest(name: name, ouId: ouId, assignments: [assignee]))
        log.record("role:created", "\(role.name) (\(role.id))", kind: .success)
        do {
            let assigned = try await client.roles.assignments(id: role.id, type: .group, limit: 50)
            guard assigned.assignments.contains(where: { $0.id == groupId }) else {
                throw CheckFailure("The new role is not assigned to the group")
            }
            try await client.roles.removeAssignments(id: role.id, [assignee])
            try await client.roles.addAssignments(id: role.id, [assignee])
            try await client.roles.removeAssignments(id: role.id, [assignee])
        } catch {
            try? await client.roles.delete(id: role.id)
            throw error
        }
        try await client.roles.delete(id: role.id)
        log.record("role:deleted", role.id, kind: .success)
        return "role assigned, unassigned and deleted"
    }

    // MARK: - Permissions

    /// Runs the permission helpers on unsigned tokens built here, so it needs no session.
    func permissionHierarchy() throws -> String {
        let fromScope = ThunderIDPermissions.fromAccessToken(Self.unsignedToken(["scope": "openid system:user"]))
        let fromScopes = ThunderIDPermissions.fromAccessToken(Self.unsignedToken(["scopes": ["system"]]))
        guard fromScope == ["openid", "system:user"], fromScopes == ["system"],
              ThunderIDPermissions.fromAccessToken("not-a-jwt").isEmpty else {
            throw CheckFailure("Parsed \(fromScope) from scope and \(fromScopes) from scopes")
        }
        // (granted, required) pairs that must be satisfied, then pairs that must not.
        let covered: [([String], String)] = [
            (["system"], "system:group:view"),
            (["system:user"], "system:user:view"),
            ([], "")
        ]
        let uncovered: [([String], String)] = [
            (["system:user"], "system:users:view"),
            (["system:user:view"], "system:user")
        ]
        for (granted, required) in covered where !ThunderIDPermissions.has(granted, required) {
            throw CheckFailure("has(\(granted), \"\(required)\") should be true")
        }
        for (granted, required) in uncovered where ThunderIDPermissions.has(granted, required) {
            throw CheckFailure("has(\(granted), \"\(required)\") should be false")
        }
        return "Reads scope and scopes claims; system covers system:group:view, "
            + "system:user does not cover system:users:view"
    }

    /// Compares the client helper, the token itself and the SwiftUI `GrantedPermissions` object.
    func grantedPermissions() async throws -> String {
        try await requireSignedIn()
        let granted = await client.getGrantedPermissions()
        let fromToken = ThunderIDPermissions.fromAccessToken(try await client.getAccessToken())
        let observed = state.grantedPermissions()
        await observed.refresh()
        guard granted == fromToken, observed.permissions == granted else {
            throw CheckFailure("getGrantedPermissions(), the token and GrantedPermissions disagree")
        }
        log.record("permissions:granted", granted.joined(separator: " "), kind: .success)
        let admin = ["system:user:view", "system:group:view", "system:role:view"].filter(observed.can)
        return "\(granted.count) permissions in the access token; "
            + (admin.isEmpty ? "no management view permissions" : "can \(admin.joined(separator: ", "))")
    }

    /// An unsigned JWT with `claims` as its payload. `fromAccessToken` does not verify signatures.
    static func unsignedToken(_ claims: [String: Any]) -> String {
        func encode(_ object: [String: Any]) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return encode(["alg": "none"]) + "." + encode(claims) + ".sig"
    }
}
