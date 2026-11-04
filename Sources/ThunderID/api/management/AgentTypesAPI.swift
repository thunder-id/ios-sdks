// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Agent type management operations, reached through `ThunderIDClient.agentTypes`. The collection URL
/// comes from `endpoints.agentTypes`, otherwise `{baseUrl}/agent-types`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct AgentTypesAPI {
    let transport: ManagementTransport

    /// Returns a page of agent types, each with its resolved display data.
    public func list(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> AgentTypeListResponse {
        try await transport.list(
            query: .management([
                ("include", "display"),
                ("limit", limit.map(String.init)),
                ("offset", offset.map(String.init))
            ]),
            fetcher: fetcher
        )
    }

    /// Returns an agent type with its attribute schema.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> AgentTypeDetails {
        try await transport.get(id: id, query: .management([("include", "display")]), fetcher: fetcher)
    }

    /// Creates an agent type and returns it as the server stored it.
    public func create(_ agentType: CreateAgentTypeRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> AgentTypeDetails {
        try await transport.create(agentType, fetcher: fetcher)
    }

    /// Deletes an agent type.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.delete(id: id, fetcher: fetcher)
    }

    /// Updates an agent type and returns the updated type.
    public func update(id: String, _ agentType: UpdateAgentTypeRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> AgentTypeDetails {
        try await transport.update(id: id, agentType, fetcher: fetcher)
    }
}
