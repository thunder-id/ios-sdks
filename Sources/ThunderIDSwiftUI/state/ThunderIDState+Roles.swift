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

    func updateRoleMutation(fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<(id: String, request: UpdateRoleRequest), Role> {
        let client = client
        return mutation(
            invalidating: { [[RoleQueryKeys.role, $0.id], [RoleQueryKeys.roles]] },
            perform: { input in try await client.roles.update(id: input.id, input.request, fetcher: fetcher) }
        )
    }

    func deleteRoleMutation(fetcher: ThunderIDFetcher? = nil) -> ResourceMutation<String, Void> {
        let client = client
        return mutation(
            invalidating: { _ in [[RoleQueryKeys.roles], [RoleQueryKeys.roleAssignments]] },
            perform: { id in try await client.roles.delete(id: id, fetcher: fetcher) }
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

    func removeRoleAssignmentsMutation(fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<RoleAssignmentsInput, Void> {
        let client = client
        return mutation(
            invalidating: { _ in [[RoleQueryKeys.roleAssignments]] },
            perform: { input in
                try await client.roles.removeAssignments(id: input.roleId, input.assignments, fetcher: fetcher)
            }
        )
    }
}
