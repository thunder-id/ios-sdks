// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Authorization details type management operations (RFC 9396), reached through
/// `ThunderIDClient.authorizationDetailTypes`. The collection URL comes from
/// `endpoints.authorizationDetailTypes`, otherwise `{baseUrl}/authorization-detail-types`. A type's
/// processor can carry a credential, so request and response bodies are never logged.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct AuthorizationDetailTypesAPI {
    let transport: ManagementTransport

    /// Returns a page of the registered types.
    public func list(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> AuthorizationDetailTypeListResponse {
        try await transport.send("GET", query: .page(limit, offset), fetcher: fetcher)
    }

    /// Returns a type by its id.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> AuthorizationDetailType {
        try await transport.send("GET", [id], fetcher: fetcher)
    }

    /// Registers a type and returns it.
    public func create(_ type: AuthorizationDetailTypeRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> AuthorizationDetailType {
        try await transport.send("POST", body: type, fetcher: fetcher)
    }

    /// Replaces a type and returns it. A read-only type cannot be updated.
    public func update(id: String, _ type: AuthorizationDetailTypeRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> AuthorizationDetailType {
        try await transport.send("PUT", [id], body: type, fetcher: fetcher)
    }

    /// Deletes a type. A read-only type cannot be deleted.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", [id], fetcher: fetcher)
    }
}
