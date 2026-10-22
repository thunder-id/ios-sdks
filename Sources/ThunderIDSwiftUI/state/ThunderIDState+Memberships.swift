// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// Reactive wrappers over the relationship and type lookups of users and agents. Each accepts an
/// optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public extension ThunderIDState {
    func userGroupsQuery(userId: String, limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<MembershipGroupListResponse> {
        let client = client
        let key = [GroupQueryKeys.memberships, "user", userId]
            + listKey("", ["limit": limit, "offset": offset]).dropFirst()
        return query(key: key) {
            try await client.users.groups(id: userId, limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func userTypesQuery(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<ManagedUserTypeListResponse> {
        let client = client
        return query(key: listKey(UserQueryKeys.userTypes, ["limit": limit, "offset": offset])) {
            try await client.users.types(limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func agentGroupsQuery(agentId: String, limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<MembershipGroupListResponse> {
        let client = client
        let key = [GroupQueryKeys.memberships, "agent", agentId]
            + listKey("", ["limit": limit, "offset": offset]).dropFirst()
        return query(key: key) {
            try await client.agents.groups(id: agentId, limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func agentRolesQuery(agentId: String, limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<AgentRoleListResponse> {
        let client = client
        let key = [RoleQueryKeys.roleAssignments, "agent", agentId]
            + listKey("", ["limit": limit, "offset": offset]).dropFirst()
        return query(key: key) {
            try await client.agents.roles(id: agentId, limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func agentTypesQuery(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<AgentTypeListResponse> {
        let client = client
        return query(key: listKey(AgentQueryKeys.agentTypes, ["limit": limit, "offset": offset])) {
            try await client.agents.types(limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    /// The permissions the signed-in user's access token carries. Call
    /// ``GrantedPermissions/refresh()`` (for example from a view's `.task`) to load them.
    func grantedPermissions() -> GrantedPermissions {
        GrantedPermissions(client: client)
    }
}

/// The permissions the signed-in user's access token carries, for deciding what to show. The server
/// still authorizes every request.
@MainActor
public final class GrantedPermissions: ObservableObject {
    @Published public private(set) var permissions: [String] = []
    @Published public private(set) var isLoading: Bool = false

    private let client: ThunderIDClient

    init(client: ThunderIDClient) {
        self.client = client
    }

    /// Reads the permissions from the current access token.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        permissions = await client.getGrantedPermissions()
    }

    /// Whether the granted permissions satisfy `required`, where `system` covers `system:user:view`.
    public func can(_ required: String) -> Bool {
        ThunderIDPermissions.has(permissions, required)
    }
}
