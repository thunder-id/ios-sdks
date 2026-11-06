// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// The input of a role assignment mutation: the role, and the identities to assign or unassign.
public typealias RoleAssignmentsInput = (roleId: String, assignments: [RoleAssignmentInput])

/// Reactive wrappers over the role operations. Each accepts an optional `fetcher` that takes
/// precedence over `ThunderIDConfig.http.fetcher`.
public extension ThunderIDState {
    func rolesQuery(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<RoleListResponse> {
        let client = client
        return query(key: listKey(RoleQueryKeys.roles, ["limit": limit, "offset": offset])) {
            try await client.roles.list(limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func roleQuery(id: String, fetcher: ThunderIDFetcher? = nil) -> ResourceQuery<Role> {
        let client = client
        return query(key: [RoleQueryKeys.role, id]) {
            try await client.roles.get(id: id, fetcher: fetcher)
        }
    }

    func roleAssignmentsQuery(
        roleId: String,
        type: RoleAssigneeType? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) -> ResourceQuery<RoleAssignmentListResponse> {
        let client = client
        let key = [RoleQueryKeys.roleAssignments, roleId]
            + listKey("", ["limit": limit, "offset": offset]).dropFirst()
            + ["type=\(type?.rawValue ?? "")"]
        return query(key: key) {
            try await client.roles.assignments(id: roleId, type: type, limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func createRoleMutation(fetcher: ThunderIDFetcher? = nil) -> ResourceMutation<CreateRoleRequest, Role> {
        let client = client
        return mutation(
            invalidating: { _ in [[RoleQueryKeys.roles], [RoleQueryKeys.roleAssignments]] },
            perform: { request in try await client.roles.create(request, fetcher: fetcher) }
        )
    }

    /// Updates a role. In `.flow` mode an update that removes a permission runs the configured
    /// permission removal flow, which revokes the scopes the permission granted.
    func updateRoleMutation(administrationMode: AdministrationMode = .native, fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<(id: String, request: UpdateRoleRequest), Role> {
        let client = client
        return mutation(
            invalidating: { [[RoleQueryKeys.role, $0.id], [RoleQueryKeys.roles]] },
            perform: { input in
                try await client.roles.update(
                    id: input.id,
                    input.request,
                    administrationMode: administrationMode,
                    fetcher: fetcher
                )
            }
        )
    }

    /// Deletes a role. In `.flow` mode the configured role deletion flow runs instead, revoking the
    /// scopes the role granted before it goes.
    func deleteRoleMutation(
        administrationMode: AdministrationMode = .native,
        fetcher: ThunderIDFetcher? = nil
    ) -> ResourceMutation<String, Void> {
        let client = client
        return mutation(
            invalidating: { _ in [[RoleQueryKeys.roles], [RoleQueryKeys.roleAssignments]] },
            perform: { id in
                try await client.roles.delete(id: id, administrationMode: administrationMode, fetcher: fetcher)
            }
        )
    }

    func addRoleAssignmentsMutation(fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<RoleAssignmentsInput, Void> {
        let client = client
        return mutation(
            invalidating: { _ in [[RoleQueryKeys.roleAssignments]] },
            perform: { input in
                try await client.roles.addAssignments(id: input.roleId, input.assignments, fetcher: fetcher)
            }
        )
    }

    /// Removes role assignments. In `.flow` mode the configured assignment removal flow runs once for
    /// each assignee instead, revoking the scopes the assignment conveyed.
    func removeRoleAssignmentsMutation(
        administrationMode: AdministrationMode = .native,
        fetcher: ThunderIDFetcher? = nil
    ) -> ResourceMutation<RoleAssignmentsInput, Void> {
        let client = client
        return mutation(
            invalidating: { _ in [[RoleQueryKeys.roleAssignments]] },
            perform: { input in
                try await client.roles.removeAssignments(
                    id: input.roleId,
                    input.assignments,
                    administrationMode: administrationMode,
                    fetcher: fetcher
                )
            }
        )
    }
}

extension ThunderIDState {
    /// The resource servers a role's permissions can be picked from, each with the permissions its
    /// actions define. Reads up to `limit` resource servers and up to `limit` actions on each.
    func rolePermissionCandidatesQuery(limit: Int = 100, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<[RolePermissionCandidate]> {
        let client = client
        return query(key: listKey("role-permission-candidates", ["limit": limit])) {
            let servers = try await client.resourceServers.list(limit: limit, fetcher: fetcher).resourceServers
            var candidates: [RolePermissionCandidate] = []
            for server in servers {
                let actions = try await client.resourceServers.actions(
                    resourceServerId: server.id,
                    limit: limit,
                    fetcher: fetcher
                ).actions
                candidates.append(
                    RolePermissionCandidate(
                        resourceServerId: server.id,
                        name: server.name,
                        permissions: actions.map(\.permission)
                    )
                )
            }
            return candidates
        }
    }
}
