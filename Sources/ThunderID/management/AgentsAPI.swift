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

    /// Returns a page of the types an agent can be registered as. ``ThunderIDClient/agentTypes`` manages them.
    public func types(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> AgentTypeListResponse {
        try await AgentTypesAPI(transport: typesTransport).list(limit: limit, offset: offset, fetcher: fetcher)
    }

    /// Gives an agent's OAuth client a new secret, generated here and saved on the agent. Fails with
    /// ``ThunderIDErrorCode/invalidInput`` before saving anything when the agent has no OAuth client.
    public func regenerateSecret(id: String, fetcher: ThunderIDFetcher? = nil) async throws
        -> RegenerateAgentSecretResult {
        let current = try await get(id: id, fetcher: fetcher)
        let inbound = current.inboundAuthConfig ?? []
        guard inbound.contains(where: { $0.type == "oauth2" }) else {
            throw ThunderIDError(
                code: .invalidInput,
                message: "The agent has no OAuth client, so it has no client secret to regenerate."
            )
        }
        let clientSecret = try SecretGenerator.generate()
        let rotated = inbound.map { entry -> AgentInboundAuthConfig in
            guard entry.type == "oauth2" else { return entry }
            var config = entry.config ?? OAuth2Config(grantTypes: [], responseTypes: [])
            config.clientSecret = clientSecret
            return AgentInboundAuthConfig(type: entry.type, config: config)
        }
        var payload = UpdateAgentRequest(restating: current)
        payload.inboundAuthConfig = rotated
        payload.delegated = DelegationGrantTypes.isDelegated(rotated)
        let agent = try await update(id: id, payload, fetcher: fetcher)
        return RegenerateAgentSecretResult(agent: agent, clientSecret: clientSecret)
    }

    private func page(_ limit: Int?, _ offset: Int?) -> [URLQueryItem] {
        .management([("limit", limit.map(String.init)), ("offset", offset.map(String.init))])
    }
}

extension UpdateAgentRequest {
    /// The agent's caller-settable fields, for a full update. The server sets `id` and `clientId`, and
    /// `ouHandle` is only display data, so they stay out.
    init(restating agent: Agent) {
        self.init()
        ouId = agent.ouId
        type = agent.type
        description = agent.description
        logoUrl = agent.logoUrl
        owner = agent.owner
        attributes = agent.attributes
        allowedUserTypes = agent.allowedUserTypes
        allowedAgentTypes = agent.allowedAgentTypes
        inboundAuthConfig = agent.inboundAuthConfig
        authFlowId = agent.authFlowId
        registrationFlowId = agent.registrationFlowId
        isRegistrationFlowEnabled = agent.isRegistrationFlowEnabled
        assertion = agent.assertion
        loginConsent = agent.loginConsent
    }
}
