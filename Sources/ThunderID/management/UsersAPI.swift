// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// User management operations, reached through `ThunderIDClient.users`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct UsersAPI {
    let transport: ManagementTransport
    /// Addresses the `userTypes` collection, which has its own `endpoints` override.
    let typesTransport: ManagementTransport

    /// Returns a page of users, each with its resolved `display` value.
    public func list(
        limit: Int? = nil,
        offset: Int? = nil,
        filter: String? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ManagedUserListResponse {
        try await transport.list(
            query: .management([
                ("limit", limit.map(String.init)),
                ("offset", offset.map(String.init)),
                ("filter", filter),
                ("include", "display")
            ]),
            fetcher: fetcher
        )
    }

    /// Returns a single user, with its resolved `display` value.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> ManagedUser {
        try await transport.get(id: id, query: .management([("include", "display")]), fetcher: fetcher)
    }

    /// Creates a user and returns it as the server stored it.
    public func create(_ user: CreateManagedUserRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> ManagedUser {
        try await transport.create(user, fetcher: fetcher)
    }

    /// Updates a user and returns the updated user.
    public func update(id: String, _ user: UpdateManagedUserRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> ManagedUser {
        try await transport.update(id: id, user, fetcher: fetcher)
    }

    /// Deletes a user.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.delete(id: id, fetcher: fetcher)
    }

    /// Returns a page of the groups a user belongs to.
    public func groups(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> MembershipGroupListResponse {
        try await transport.related(
            id: id,
            subPath: "groups",
            query: .management([("limit", limit.map(String.init)), ("offset", offset.map(String.init))]),
            fetcher: fetcher
        )
    }

    /// Returns a page of the types a user can be created as.
    public func types(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> ManagedUserTypeListResponse {
        try await typesTransport.list(
            query: .management([("limit", limit.map(String.init)), ("offset", offset.map(String.init))]),
            fetcher: fetcher
        )
    }
}
