// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// Reactive wrappers over the signed-in user's own agents (`/users/me/agents`). These are the user's own
/// requests, so they take no `fetcher`: they go through the SDK's transport like the other `/users/me`
/// operations.
public extension ThunderIDState {
    func meAgentsQuery(kind: AgentKind? = nil, limit: Int? = nil, offset: Int? = nil)
        -> ResourceQuery<AgentListResponse> {
        let client = client
        let key = listKey(AgentQueryKeys.meAgents, ["limit": limit, "offset": offset])
            + ["kind=\(kind?.rawValue ?? "")"]
        return query(key: key) {
            try await client.getMeAgents(kind: kind, limit: limit, offset: offset)
        }
    }

    func meAgentQuery(id: String) -> ResourceQuery<Agent> {
        let client = client
        return query(key: [AgentQueryKeys.meAgent, id]) {
            try await client.getMeAgent(id: id)
        }
    }

    func updateMeAgentMutation() -> ResourceMutation<(id: String, request: UpdateMeAgentRequest), Agent> {
        let client = client
        return mutation(
            invalidating: { [[AgentQueryKeys.meAgent, $0.id], [AgentQueryKeys.meAgents]] },
            perform: { input in try await client.updateMeAgent(id: input.id, input.request) }
        )
    }

    func deleteMeAgentMutation() -> ResourceMutation<String, Void> {
        let client = client
        return mutation(
            invalidating: { [[AgentQueryKeys.meAgent, $0], [AgentQueryKeys.meAgents]] },
            perform: { id in try await client.deleteMeAgent(id: id) }
        )
    }

    /// Places or lifts the signed-in user's own suspension of one of their agents.
    func meAgentSuspensionMutation() -> ResourceMutation<(id: String, action: MeAgentSuspensionAction), Void> {
        let client = client
        return mutation(
            invalidating: { [[AgentQueryKeys.meAgent, $0.id], [AgentQueryKeys.meAgents]] },
            perform: { input in
                switch input.action {
                case .suspend: try await client.suspendMeAgent(id: input.id)
                case .unsuspend: try await client.unsuspendMeAgent(id: input.id)
                }
            }
        )
    }

    func suspendAllMeAgentsMutation() -> ResourceMutation<Void, SuspendAllMeAgentsResponse> {
        let client = client
        return mutation(
            invalidating: { _ in [[AgentQueryKeys.meAgent], [AgentQueryKeys.meAgents]] },
            perform: { _ in try await client.suspendAllMeAgents() }
        )
    }
}
