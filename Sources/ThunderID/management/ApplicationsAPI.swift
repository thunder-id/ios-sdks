// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Application management operations, reached through `ThunderIDClient.applications`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.fetcher`.
public struct ApplicationsAPI {
    let transport: ManagementTransport

    /// Returns a page of applications.
    public func list(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> ApplicationListResponse {
        try await transport.list(
            query: .management([("limit", limit.map(String.init)), ("offset", offset.map(String.init))]),
            fetcher: fetcher
        )
    }

    /// Returns a single application.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> Application {
        try await transport.get(id: id, fetcher: fetcher)
    }

    /// Creates an application and returns it as the server stored it.
    public func create(_ application: ApplicationRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> Application {
        try await transport.create(application, fetcher: fetcher)
    }

    /// Replaces an application's mutable fields and returns the updated application.
    public func update(id: String, _ application: ApplicationRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> Application {
        try await transport.update(id: id, application, fetcher: fetcher)
    }

    /// Deletes an application.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.delete(id: id, fetcher: fetcher)
    }
}
