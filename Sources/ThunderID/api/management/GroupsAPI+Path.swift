// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The payload used to create a group in the organization unit a handle path names.
public struct CreateGroupByPathRequest: Codable {
    public var name: String
    public var description: String?
    /// The first members. Each must be owned by, or shared with, the organization unit.
    public var members: [GroupMemberInput]?

    public init(name: String, description: String? = nil, members: [GroupMemberInput]? = nil) {
        self.name = name
        self.description = description
        self.members = members
    }
}

public extension GroupsAPI {
    // MARK: - By organization unit path

    /// Returns a page of the groups in the organization unit a handle path such as `engineering/frontend`
    /// names. Each segment is encoded on its own, and the slashes between them stay.
    func list(
        path: String,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> GroupListResponse {
        try await transport.send(
            "GET",
            ["tree"] + ManagementPath.tree(path),
            query: .page(limit, offset) + .management([("include", "display")]),
            fetcher: fetcher
        )
    }

    /// Creates a group in the organization unit a handle path names, and returns it as the server stored it.
    func create(path: String, _ group: CreateGroupByPathRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> ManagedGroup {
        try await transport.send("POST", ["tree"] + ManagementPath.tree(path), body: group, fetcher: fetcher)
    }
}
