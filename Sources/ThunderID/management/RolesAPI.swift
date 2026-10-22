// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Role management operations, reached through `ThunderIDClient.roles`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct RolesAPI {
    let transport: ManagementTransport

    /// Returns a page of roles.
    public func list(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> RoleListResponse {
        try await transport.list(
            query: .management([("limit", limit.map(String.init)), ("offset", offset.map(String.init))]),
            fetcher: fetcher
        )
    }

    /// Returns a single role with the permissions it grants.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> Role {
        try await transport.get(id: id, fetcher: fetcher)
    }

    /// Creates a role, optionally with its first assignments, and returns it as the server stored it.
    public func create(_ role: CreateRoleRequest, fetcher: ThunderIDFetcher? = nil) async throws -> Role {
        try await transport.create(role, fetcher: fetcher)
    }

    /// Replaces a role's name, description and permissions and returns the updated role.
    public func update(id: String, _ role: UpdateRoleRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> Role {
        try await transport.update(id: id, role, fetcher: fetcher)
    }

    /// Deletes a role.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
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

    /// Removes a role from users, groups, apps or agents.
    public func removeAssignments(
        id: String,
        _ assignments: [RoleAssignmentInput],
        fetcher: ThunderIDFetcher? = nil
    ) async throws {
        let _: EmptyResponse = try await transport.action(
            id: id,
            subPath: "assignments/remove",
            AssignmentsBody(assignments: assignments),
            fetcher: fetcher
        )
    }
}

private struct AssignmentsBody: Encodable {
    let assignments: [RoleAssignmentInput]
}
