// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The agents the signed-in user owns, through the owner self-service API under `/users/me/agents`. These
/// are the user's own requests: they carry the user's token through the SDK's own transport, like the other
/// `/users/me` operations, and never `ThunderIDConfig.http.fetcher`. The token must be the user's own: a
/// delegated token, such as an agent's token for its owner, is refused.
public extension ThunderIDClient {
    /// Returns a page of the agents the signed-in user owns, in the organization unit the access token
    /// names. Pass ``AgentKind/personal`` as `kind` to list only personal agents.
    func getMeAgents(kind: AgentKind? = nil, limit: Int? = nil, offset: Int? = nil) async throws
        -> AgentListResponse {
        try await sendMeAgents(
            "GET",
            query: .management([
                ("kind", kind?.rawValue),
                ("limit", limit.map(String.init)),
                ("offset", offset.map(String.init))
            ])
        )
    }

    /// Returns one of the signed-in user's agents. An agent the user does not own, or one outside the
    /// organization unit the access token names, is not found.
    func getMeAgent(id: String) async throws -> Agent {
        try await sendMeAgents("GET", [id], query: .management([("include", "display")]))
    }

    /// Replaces the part of one of the signed-in user's personal agents its owner may change, and returns
    /// the updated agent. Read the agent first and send its editable fields back with the changes.
    func updateMeAgent(id: String, _ request: UpdateMeAgentRequest) async throws -> Agent {
        try await sendMeAgents("PUT", [id], body: try JSONEncoder().encode(request))
    }

    /// Deletes one of the signed-in user's personal agents.
    func deleteMeAgent(id: String) async throws {
        let _: EmptyResponse = try await sendMeAgents("DELETE", [id])
    }

    /// Suspends one of the signed-in user's personal agents, after the server revokes the tokens issued to
    /// it. The owner's suspension is independent of the organization's, and suspending again changes nothing.
    /// ``MeAgentSuspensionAction/available(for:)`` says whether to offer it.
    func suspendMeAgent(id: String) async throws {
        let _: EmptyResponse = try await sendMeAgents("POST", [id, "suspend"])
    }

    /// Lifts the signed-in user's own suspension of one of their personal agents. A suspension another
    /// party placed, such as the organization's, stays in force.
    func unsuspendMeAgent(id: String) async throws {
        let _: EmptyResponse = try await sendMeAgents("POST", [id, "unsuspend"])
    }

    /// Suspends every personal agent of the signed-in user that the user has not already suspended, in the
    /// organization unit the access token names, after the server revokes the tokens issued to each.
    func suspendAllMeAgents() async throws -> SuspendAllMeAgentsResponse {
        try await sendMeAgents("POST", ["suspend"])
    }
}

private extension ThunderIDClient {
    /// Sends a request to `/users/me/agents/{segments...}`, each segment percent-encoded on its own.
    func sendMeAgents<T: Decodable>(
        _ method: String,
        _ segments: [String] = [],
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> T {
        try requireInitialized()
        guard let httpClient else {
            throw ThunderIDError(code: .sdkNotInitialized, message: "Call initialize() before using the SDK")
        }
        var path = "/users/me/agents"
        for segment in segments {
            guard !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ThunderIDError(code: .invalidInput, message: "An agent identifier is required")
            }
            path += "/" + (segment.addingPercentEncoding(withAllowedCharacters: ManagementPath.allowed) ?? segment)
        }
        guard let base = httpClient.url(forPath: path), var components = URLComponents(
            url: base,
            resolvingAgainstBaseURL: false
        ) else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Invalid URL for \(path)")
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Invalid URL for \(path)")
        }
        return try await httpClient.send(method: method, url: url, body: body)
    }
}
