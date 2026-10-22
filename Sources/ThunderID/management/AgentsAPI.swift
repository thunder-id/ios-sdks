// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Agent management operations, reached through `ThunderIDClient.agents`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct AgentsAPI {
    let transport: ManagementTransport
    /// Addresses the `agentTypes` collection, which has its own `endpoints` override.
    let typesTransport: ManagementTransport

    /// Returns a page of agents.
    /// - Parameter filter: A server-side filter on a custom agent attribute, such as `name eq "Calendar Agent"`.
    ///   ``ManagementFilter/equality(attribute:value:)`` builds one.
    public func list(
        limit: Int? = nil,
        offset: Int? = nil,
        filter: String? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> AgentListResponse {
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

    /// Returns a page of the groups an agent belongs to.
    public func groups(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> MembershipGroupListResponse {
        try await transport.related(id: id, subPath: "groups", query: page(limit, offset), fetcher: fetcher)
    }

    /// Returns a page of the names of the roles assigned to an agent.
    public func roles(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> AgentRoleListResponse {
        try await transport.related(id: id, subPath: "roles", query: page(limit, offset), fetcher: fetcher)
    }

    /// Returns a page of the types an agent can be registered as.
    public func types(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> AgentTypeListResponse {
        try await typesTransport.list(query: page(limit, offset), fetcher: fetcher)
    }

    private func page(_ limit: Int?, _ offset: Int?) -> [URLQueryItem] {
        .management([("limit", limit.map(String.init)), ("offset", offset.map(String.init))])
    }
}
