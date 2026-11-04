// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// User type management operations, reached through `ThunderIDClient.userTypes`. The collection URL
/// comes from `endpoints.userTypes`, otherwise `{baseUrl}/user-types`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct UserTypesAPI {
    let transport: ManagementTransport

    /// Returns a page of user types, each with its resolved display data.
    public func list(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> ManagedUserTypeListResponse {
        try await transport.list(
            query: .management([
                ("include", "display"),
                ("limit", limit.map(String.init)),
                ("offset", offset.map(String.init))
            ]),
            fetcher: fetcher
        )
    }

    /// Returns a user type with its attribute schema.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> ManagedUserTypeDetails {
        try await transport.get(id: id, query: .management([("include", "display")]), fetcher: fetcher)
    }

    /// Creates a user type and returns it as the server stored it.
    public func create(_ userType: CreateUserTypeRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> ManagedUserTypeDetails {
        try await transport.create(userType, fetcher: fetcher)
    }

    /// Updates a user type and returns the updated type.
    public func update(id: String, _ userType: UpdateUserTypeRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> ManagedUserTypeDetails {
        try await transport.update(id: id, userType, fetcher: fetcher)
    }

    /// Deletes a user type.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.delete(id: id, fetcher: fetcher)
    }
}
