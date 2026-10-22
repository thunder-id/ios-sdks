// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// The input of a group membership mutation: the group, and the identities to add or remove.
public typealias GroupMembersInput = (groupId: String, members: [GroupMemberInput])

/// Reactive wrappers over the group operations. Each accepts an optional `fetcher` that takes
/// precedence over `ThunderIDConfig.http.fetcher`.
public extension ThunderIDState {
    func groupsQuery(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<GroupListResponse> {
        let client = client
        return query(key: listKey(GroupQueryKeys.groups, ["limit": limit, "offset": offset])) {
            try await client.groups.list(limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func groupQuery(id: String, fetcher: ThunderIDFetcher? = nil) -> ResourceQuery<ManagedGroup> {
        let client = client
        return query(key: [GroupQueryKeys.group, id]) {
            try await client.groups.get(id: id, fetcher: fetcher)
        }
    }

    func groupMembersQuery(groupId: String, limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<GroupMemberListResponse> {
        let client = client
        let key = [GroupQueryKeys.groupMembers, groupId] + listKey("", ["limit": limit, "offset": offset]).dropFirst()
        return query(key: key) {
            try await client.groups.members(id: groupId, limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func createGroupMutation(fetcher: ThunderIDFetcher? = nil) -> ResourceMutation<CreateGroupRequest, ManagedGroup> {
        let client = client
        return mutation(
            invalidating: { _ in [[GroupQueryKeys.groups], [GroupQueryKeys.memberships]] },
            perform: { request in try await client.groups.create(request, fetcher: fetcher) }
        )
    }

    func updateGroupMutation(fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<(id: String, request: UpdateGroupRequest), ManagedGroup> {
        let client = client
        return mutation(
            invalidating: {
                [[GroupQueryKeys.group, $0.id], [GroupQueryKeys.groups], [GroupQueryKeys.memberships]]
            },
            perform: { input in try await client.groups.update(id: input.id, input.request, fetcher: fetcher) }
        )
    }

    func deleteGroupMutation(fetcher: ThunderIDFetcher? = nil) -> ResourceMutation<String, Void> {
        let client = client
        return mutation(
            invalidating: { _ in
                [[GroupQueryKeys.groups], [GroupQueryKeys.memberships], [RoleQueryKeys.roleAssignments]]
            },
            perform: { id in try await client.groups.delete(id: id, fetcher: fetcher) }
        )
    }

    func addGroupMembersMutation(fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<GroupMembersInput, ManagedGroup> {
        let client = client
        return mutation(invalidating: membershipKeys) { input in
            try await client.groups.addMembers(id: input.groupId, input.members, fetcher: fetcher)
        }
    }

    func removeGroupMembersMutation(fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<GroupMembersInput, ManagedGroup> {
        let client = client
        return mutation(invalidating: membershipKeys) { input in
            try await client.groups.removeMembers(id: input.groupId, input.members, fetcher: fetcher)
        }
    }
}

private func membershipKeys(_ input: GroupMembersInput) -> [[String]] {
    [
        [GroupQueryKeys.group, input.groupId],
        [GroupQueryKeys.groupMembers, input.groupId],
        [GroupQueryKeys.memberships],
        [RoleQueryKeys.roleAssignments]
    ]
}
