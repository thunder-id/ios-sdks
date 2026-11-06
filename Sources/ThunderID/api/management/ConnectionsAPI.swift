// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Connection management operations, reached through `ThunderIDClient.connections`. The collection
/// URL comes from `endpoints.connections`, otherwise `{baseUrl}/connections`. Connections carry
/// credentials, so their request and response bodies are never logged.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct ConnectionsAPI {
    let transport: ManagementTransport

    /// Returns a page of every connection.
    /// - Parameter category: Only connections of this category, such as `identity-provider`,
    ///   `sms-provider`, `authorization-pdp`, `email-provider` or `http`.
    public func list(
        category: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ConnectionListResponse {
        try await transport.send(
            "GET",
            query: .management([("category", category)]) + .page(limit, offset),
            fetcher: fetcher
        )
    }

    /// Returns every connection of one vendor. The server does not page this listing.
    public func list(type: ConnectionType, fetcher: ThunderIDFetcher? = nil) async throws -> [ConnectionSummary] {
        try await transport.send("GET", [type.rawValue], fetcher: fetcher)
    }

    /// Returns a connection with its vendor settings.
    public func get(type: ConnectionType, id: String, fetcher: ThunderIDFetcher? = nil) async throws -> Connection {
        try await transport.send("GET", [type.rawValue, id], fetcher: fetcher)
    }

    /// Creates a connection of a vendor and returns it.
    public func create(type: ConnectionType, _ connection: ConnectionRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> Connection {
        try await transport.send("POST", [type.rawValue], body: connection, fetcher: fetcher)
    }

    /// Updates a connection and returns it.
    public func update(
        type: ConnectionType,
        id: String,
        _ connection: ConnectionRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> Connection {
        try await transport.send("PUT", [type.rawValue, id], body: connection, fetcher: fetcher)
    }

    /// Deletes a connection.
    public func delete(type: ConnectionType, id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", [type.rawValue, id], fetcher: fetcher)
    }

    /// Lists the flows that use a connection, and what happens to each when it is deleted. Every vendor
    /// but `http` has usages.
    public func usages(type: ConnectionType, id: String, fetcher: ThunderIDFetcher? = nil) async throws
        -> ResourceUsagesResponse {
        try await transport.send("GET", [type.rawValue, id, "usages"], fetcher: fetcher)
    }

    /// Returns what each vendor supports, such as its outbound authentication methods.
    /// - Parameter vendor: Only this vendor.
    public func meta(vendor: ConnectionType? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> ConnectionMetaResponse {
        try await transport.send("GET", ["meta"], query: .management([("vendor", vendor?.rawValue)]), fetcher: fetcher)
    }
}
