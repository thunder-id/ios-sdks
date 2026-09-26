// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Agent management operations, reached through `ThunderIDClient.agents`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.fetcher`.
public struct AgentsAPI {
    let transport: ManagementTransport

    /// Returns a page of agents.
    public func list(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> AgentListResponse {
        try await transport.list(
            query: .management([
                ("limit", limit.map(String.init)),
                ("offset", offset.map(String.init)),
                ("include", "display")
            ]),
            fetcher: fetcher
        )
    }

    /// Returns a single agent.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> Agent {
        try await transport.get(id: id, query: .management([("include", "display")]), fetcher: fetcher)
    }

    /// Creates an agent and returns it as the server stored it.
    public func create(_ agent: CreateAgentRequest, fetcher: ThunderIDFetcher? = nil) async throws -> Agent {
        try await transport.create(agent, fetcher: fetcher)
    }

    /// Updates an agent and returns the updated agent.
    public func update(id: String, _ agent: UpdateAgentRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> Agent {
        try await transport.update(id: id, agent, fetcher: fetcher)
    }

    /// Deletes an agent.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.delete(id: id, fetcher: fetcher)
    }
}
