// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// ManagedGroup management operations, reached through `ThunderIDClient.groups`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct GroupsAPI {
    let transport: ManagementTransport

    /// Returns a page of groups.
    public func list(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> GroupListResponse {
        try await transport.list(
            query: .management([
                ("include", "display"),
                ("limit", limit.map(String.init)),
                ("offset", offset.map(String.init))
            ]),
            fetcher: fetcher
        )
    }

    /// Returns a single group.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> ManagedGroup {
        try await transport.get(id: id, query: .management([("include", "display")]), fetcher: fetcher)
    }

    /// Creates a group, optionally with its first members, and returns it as the server stored it.
    public func create(_ group: CreateGroupRequest, fetcher: ThunderIDFetcher? = nil) async throws -> ManagedGroup {
        try await transport.create(group, fetcher: fetcher)
    }

    /// Replaces a group's name and description and returns the updated group.
    public func update(id: String, _ group: UpdateGroupRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> ManagedGroup {
        try await transport.update(id: id, group, fetcher: fetcher)
    }

    /// Deletes a group.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.delete(id: id, fetcher: fetcher)
    }

    /// Returns a page of the users, agents and groups in a group.
    public func members(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> GroupMemberListResponse {
        try await transport.related(
            id: id,
            subPath: "members",
            query: .management([
                ("include", "display"),
                ("limit", limit.map(String.init)),
                ("offset", offset.map(String.init))
            ]),
            fetcher: fetcher
        )
    }

    /// Adds users, agents or groups to a group and returns the updated group.
    @discardableResult
    public func addMembers(id: String, _ members: [GroupMemberInput], fetcher: ThunderIDFetcher? = nil)
        async throws -> ManagedGroup {
        try await transport.action(id: id, subPath: "members/add", MembersBody(members: members), fetcher: fetcher)
    }

    /// Removes users, agents or groups from a group and returns the updated group.
    @discardableResult
    public func removeMembers(id: String, _ members: [GroupMemberInput], fetcher: ThunderIDFetcher? = nil)
        async throws -> ManagedGroup {
        try await transport.action(
            id: id,
            subPath: "members/remove",
            MembersBody(members: members),
            fetcher: fetcher
        )
    }
}

private struct MembersBody: Encodable {
    let members: [GroupMemberInput]
}
