// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Role management operations, reached through `ThunderIDClient.roles`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct RolesAPI {
    let transport: ManagementTransport

    /// Returns a page of roles, each with its resolved display data.
    public func list(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> RoleListResponse {
        try await transport.list(
            query: .management([
                ("include", "display"),
                ("limit", limit.map(String.init)),
                ("offset", offset.map(String.init))
            ]),
            fetcher: fetcher
        )
    }

    /// Returns a single role with the permissions it grants.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> Role {
        try await transport.get(id: id, query: .management([("include", "display")]), fetcher: fetcher)
    }

    /// Creates a role, optionally with its first assignments, and returns it as the server stored it.
    public func create(_ role: CreateRoleRequest, fetcher: ThunderIDFetcher? = nil) async throws -> Role {
        try await transport.create(role, fetcher: fetcher)
    }

    /// Replaces a role's name, description and permissions and returns the updated role.
    ///
    /// In `.flow` mode an update that removes a permission runs the configured permission removal flow,
    /// which revokes the scopes the permissions granted; the role's other fields are written first, so a
    /// rejected rename fails before anything is revoked.
    /// - Parameter current: The role as it is now. In `.flow` mode it tells whether the update removes a
    ///   permission; when `nil`, the role is read first.
    public func update(
        id: String,
        _ role: UpdateRoleRequest,
        current: Role? = nil,
        administrationMode: AdministrationMode = .native,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> Role {
        guard administrationMode == .flow else {
            return try await transport.update(id: id, role, fetcher: fetcher)
        }
        let before: Role
        if let current {
            before = current
        } else {
            before = try await get(id: id, fetcher: fetcher)
        }
        let action = "role permission change"
        guard Self.removesPermission(from: before.permissions, to: role.permissions),
              let flowId = try await transport.administrationFlowId(
                  .flow,
                  .rolePermissionRemoval,
                  action: action,
                  fetcher: fetcher
              ) else {
            return try await transport.update(id: id, role, fetcher: fetcher)
        }
        // The flow writes only the permissions, so the other fields go first.
        let otherFieldsChanged = role.name != before.name
            || (role.description ?? "") != (before.description ?? "")
            || role.ouId != before.ouId
        var unchangedPermissions = role
        unchangedPermissions.permissions = before.permissions
        let updated: Role = otherFieldsChanged
            ? try await transport.update(id: id, unchangedPermissions, fetcher: fetcher)
            : before
        _ = try await transport.administrationFlows.execute(
            flowId: flowId,
            inputs: [
                AdministrationFlowInput.permissions: try Self.encodePermissions(role.permissions),
                AdministrationFlowInput.role: id
            ],
            action: action,
            fetcher: fetcher
        )
        return Role(
            id: updated.id,
            name: updated.name,
            description: updated.description,
            ouId: updated.ouId,
            ouHandle: updated.ouHandle,
            isReadOnly: updated.isReadOnly,
            permissions: role.permissions
        )
    }

    /// Deletes a role. In `.flow` mode the configured role deletion flow runs instead, revoking the
    /// scopes the role granted before it goes.
    public func delete(
        id: String,
        administrationMode: AdministrationMode = .native,
        fetcher: ThunderIDFetcher? = nil
    ) async throws {
        let ran = try await transport.runAdministrationFlow(
            administrationMode,
            .roleDeletion,
            inputs: [AdministrationFlowInput.role: id],
            action: "role deletion",
            fetcher: fetcher
        )
        if ran != nil { return }
        try await transport.delete(id: id, fetcher: fetcher)
    }

    /// Returns a page of the users, groups, apps and agents a role is assigned to. Pass `type` to
    /// return only assignees of that type.
    public func assignments(
        id: String,
        type: RoleAssigneeType? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> RoleAssignmentListResponse {
        try await transport.related(
            id: id,
            subPath: "assignments",
            query: .management([
                ("include", "display"),
                ("limit", limit.map(String.init)),
                ("offset", offset.map(String.init)),
                ("type", type?.rawValue)
            ]),
            fetcher: fetcher
        )
    }

    /// Assigns a role to users, groups, apps or agents.
    public func addAssignments(id: String, _ assignments: [RoleAssignmentInput], fetcher: ThunderIDFetcher? = nil)
        async throws {
        let _: EmptyResponse = try await transport.action(
            id: id,
            subPath: "assignments/add",
            AssignmentsBody(assignments: assignments),
            fetcher: fetcher
        )
    }

    /// Removes a role from users, groups, apps or agents. In `.flow` mode the configured assignment
    /// removal flow runs once for each assignee instead, revoking the scopes the assignment conveyed.
    public func removeAssignments(
        id: String,
        _ assignments: [RoleAssignmentInput],
        administrationMode: AdministrationMode = .native,
        fetcher: ThunderIDFetcher? = nil
    ) async throws {
        let action = "role assignment removal"
        if let flowId = try await transport.administrationFlowId(
            administrationMode,
            .roleAssignmentRemoval,
            action: action,
            fetcher: fetcher
        ) {
            for assignment in assignments {
                _ = try await transport.administrationFlows.execute(
                    flowId: flowId,
                    inputs: [AdministrationFlowInput.assignee: assignment.id, AdministrationFlowInput.role: id],
                    action: action,
                    fetcher: fetcher
                )
            }
            return
        }
        let _: EmptyResponse = try await transport.action(
            id: id,
            subPath: "assignments/remove",
            AssignmentsBody(assignments: assignments),
            fetcher: fetcher
        )
    }
}

private extension RolesAPI {
    /// Whether the new permissions drop any of the current ones. Only a removal has anything to revoke.
    static func removesPermission(from current: [RoleResourcePermissions], to next: [RoleResourcePermissions])
        -> Bool {
        let retained = Set(next.flatMap { resource in
            resource.permissions.map { "\(resource.resourceServerId)\u{0}\($0)" }
        })
        return current.contains { resource in
            resource.permissions.contains { !retained.contains("\(resource.resourceServerId)\u{0}\($0)") }
        }
    }

    /// The permissions as the JSON array the permission removal flow reads.
    static func encodePermissions(_ permissions: [RoleResourcePermissions]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let json = String(bytes: try encoder.encode(permissions), encoding: .utf8) else {
            throw ThunderIDError(code: .invalidInput, message: "The permissions could not be encoded")
        }
        return json
    }
}

private struct AssignmentsBody: Encodable {
    let assignments: [RoleAssignmentInput]
}
