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

    /// Deletes a user. In `.flow` mode the configured user deletion flow runs instead, revoking the
    /// user's grants and ending their sessions before the record goes.
    public func delete(
        id: String,
        administrationMode: AdministrationMode = .native,
        fetcher: ThunderIDFetcher? = nil
    ) async throws {
        let ran = try await transport.runAdministrationFlow(
            administrationMode,
            .userDeletion,
            inputs: [AdministrationFlowInput.subject: id],
            action: "user deletion",
            fetcher: fetcher
        )
        if ran != nil { return }
        try await transport.delete(id: id, fetcher: fetcher)
    }

    /// Lists the resources that reference a user, such as agents that name the user as their owner, and
    /// what happens to each when the user is deleted.
    public func usages(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> UserUsagesResponse {
        try await transport.related(id: id, subPath: "usages", query: [], fetcher: fetcher)
    }

    /// Sets new values for some of a user's credential attributes, such as the password.
    public func updateCredentials(
        id: String,
        _ request: UpdateUserCredentialsRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws {
        let _: EmptyResponse = try await transport.action(
            id: id,
            subPath: "update-credentials",
            request,
            fetcher: fetcher
        )
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

    /// Returns a page of the types a user can be created as. ``ThunderIDClient/userTypes`` manages them.
    public func types(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> ManagedUserTypeListResponse {
        try await UserTypesAPI(transport: typesTransport).list(limit: limit, offset: offset, fetcher: fetcher)
    }
}
