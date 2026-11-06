// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// OpenID4VP presentation definition operations, reached through `ThunderIDClient.presentationDefinitions`.
/// The collection URL comes from `endpoints.presentationDefinitions`, otherwise
/// `{baseUrl}/openid4vp/presentation-definitions`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct PresentationDefinitionsAPI {
    let transport: ManagementTransport

    /// Returns every presentation definition, as summaries. The server does not page this listing.
    public func list(fetcher: ThunderIDFetcher? = nil) async throws -> [PresentationDefinition] {
        try await transport.send("GET", fetcher: fetcher)
    }

    /// Returns a presentation definition.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> PresentationDefinition {
        try await transport.send("GET", [id], fetcher: fetcher)
    }

    /// Creates a presentation definition and returns it.
    public func create(_ definition: PresentationDefinitionRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> PresentationDefinition {
        try await transport.send("POST", body: definition, fetcher: fetcher)
    }

    /// Replaces a presentation definition and returns it.
    public func update(
        id: String,
        _ definition: PresentationDefinitionRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> PresentationDefinition {
        try await transport.send("PUT", [id], body: definition, fetcher: fetcher)
    }

    /// Deletes a presentation definition. Deleting one that does not exist succeeds.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", [id], fetcher: fetcher)
    }
}
