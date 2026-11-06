// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The layers of a server configuration section: what the deployment fixes (`readOnly`), what the API
/// has written (`writable`), and the two combined (`merged`), which is what applies.
public struct ServerConfigLayers: Codable {
    public let readOnly: [String: AnyCodable]?
    public let writable: [String: AnyCodable]?
    public let merged: [String: AnyCodable]?
}

/// Server configuration operations, reached through `ThunderIDClient.serverConfig`. The collection URL
/// comes from `endpoints.serverConfig`, otherwise `{baseUrl}/server-config`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct ServerConfigAPI {
    let transport: ManagementTransport

    /// Returns the names of the configuration sections, such as `flow` and `accountAccess`.
    public func names(fetcher: ThunderIDFetcher? = nil) async throws -> [String] {
        try await transport.send("GET", fetcher: fetcher)
    }

    /// Returns a configuration section's layers.
    public func get(name: String, fetcher: ThunderIDFetcher? = nil) async throws -> ServerConfigLayers {
        try await transport.send("GET", [name], fetcher: fetcher)
    }

    /// Writes a configuration section's writable layer and returns the section's layers.
    public func update(name: String, _ value: [String: AnyCodable], fetcher: ThunderIDFetcher? = nil) async throws
        -> ServerConfigLayers {
        try await transport.send("PUT", [name], body: value, fetcher: fetcher)
    }
}
