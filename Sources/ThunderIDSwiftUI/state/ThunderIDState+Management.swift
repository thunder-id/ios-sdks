// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// Reactive wrappers over the management operations. Each accepts an optional `fetcher` that takes
/// precedence over `ThunderIDConfig.fetcher`.
public extension ThunderIDState {
    // MARK: - Applications

    func applicationsQuery(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<ApplicationListResponse> {
        let client = client
        return query(key: listKey(ApplicationQueryKeys.applications, ["limit": limit, "offset": offset])) {
            try await client.applications.list(limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func applicationQuery(id: String, fetcher: ThunderIDFetcher? = nil) -> ResourceQuery<Application> {
        let client = client
        return query(key: [ApplicationQueryKeys.application, id]) {
            try await client.applications.get(id: id, fetcher: fetcher)
        }
    }

    func createApplicationMutation(fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<ApplicationRequest, Application> {
        let client = client
        return mutation(
            invalidating: { _ in [[ApplicationQueryKeys.applications]] },
            perform: { request in try await client.applications.create(request, fetcher: fetcher) }
        )
    }

    func updateApplicationMutation(fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<(id: String, request: ApplicationRequest), Application> {
        let client = client
        return mutation(
            invalidating: { [[ApplicationQueryKeys.application, $0.id], [ApplicationQueryKeys.applications]] },
            perform: { input in try await client.applications.update(id: input.id, input.request, fetcher: fetcher) }
        )
    }

    func deleteApplicationMutation(fetcher: ThunderIDFetcher? = nil) -> ResourceMutation<String, Void> {
        let client = client
        return mutation(
            invalidating: { _ in [[ApplicationQueryKeys.applications]] },
            perform: { id in try await client.applications.delete(id: id, fetcher: fetcher) }
        )
    }

    // MARK: - Users

    func usersQuery(limit: Int? = nil, offset: Int? = nil, filter: String? = nil, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<ManagedUserListResponse> {
        let client = client
        let key = listKey(UserQueryKeys.users, ["limit": limit, "offset": offset]) + ["filter=\(filter ?? "")"]
        return query(key: key) {
            try await client.users.list(limit: limit, offset: offset, filter: filter, fetcher: fetcher)
        }
    }

    func userQuery(id: String, fetcher: ThunderIDFetcher? = nil) -> ResourceQuery<ManagedUser> {
        let client = client
        return query(key: [UserQueryKeys.user, id]) {
            try await client.users.get(id: id, fetcher: fetcher)
        }
    }

    func createUserMutation(fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<CreateManagedUserRequest, ManagedUser> {
        let client = client
        return mutation(
            invalidating: { _ in [[UserQueryKeys.users]] },
            perform: { request in try await client.users.create(request, fetcher: fetcher) }
        )
    }

    func updateUserMutation(fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<(id: String, request: UpdateManagedUserRequest), ManagedUser> {
        let client = client
        return mutation(
            invalidating: { [[UserQueryKeys.user, $0.id], [UserQueryKeys.users]] },
            perform: { input in try await client.users.update(id: input.id, input.request, fetcher: fetcher) }
        )
    }

    func deleteUserMutation(fetcher: ThunderIDFetcher? = nil) -> ResourceMutation<String, Void> {
        let client = client
        return mutation(
            invalidating: { _ in [[UserQueryKeys.users]] },
            perform: { id in try await client.users.delete(id: id, fetcher: fetcher) }
        )
    }

    // MARK: - Agents

    func agentsQuery(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<AgentListResponse> {
        let client = client
        return query(key: listKey(AgentQueryKeys.agents, ["limit": limit, "offset": offset])) {
            try await client.agents.list(limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func agentQuery(id: String, fetcher: ThunderIDFetcher? = nil) -> ResourceQuery<Agent> {
        let client = client
        return query(key: [AgentQueryKeys.agent, id]) {
            try await client.agents.get(id: id, fetcher: fetcher)
        }
    }

    func createAgentMutation(fetcher: ThunderIDFetcher? = nil) -> ResourceMutation<CreateAgentRequest, Agent> {
        let client = client
        return mutation(
            invalidating: { _ in [[AgentQueryKeys.agents]] },
            perform: { request in try await client.agents.create(request, fetcher: fetcher) }
        )
    }

    func updateAgentMutation(fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<(id: String, request: UpdateAgentRequest), Agent> {
        let client = client
        return mutation(
            invalidating: { [[AgentQueryKeys.agent, $0.id], [AgentQueryKeys.agents]] },
            perform: { input in try await client.agents.update(id: input.id, input.request, fetcher: fetcher) }
        )
    }

    func deleteAgentMutation(fetcher: ThunderIDFetcher? = nil) -> ResourceMutation<String, Void> {
        let client = client
        return mutation(
            invalidating: { _ in [[AgentQueryKeys.agents]] },
            perform: { id in try await client.agents.delete(id: id, fetcher: fetcher) }
        )
    }
}

private extension ThunderIDState {
    func query<Value>(key: [String], fetch: @escaping () async throws -> Value) -> ResourceQuery<Value> {
        ResourceQuery(key: key, invalidator: invalidator, fetch: fetch)
    }

    func mutation<Input, Output>(
        invalidating keys: @escaping (Input) -> [[String]],
        perform: @escaping (Input) async throws -> Output
    ) -> ResourceMutation<Input, Output> {
        ResourceMutation(invalidator: invalidator, invalidatedKeys: keys, perform: perform)
    }

    /// Builds a list query key: the collection key, then each parameter in name order.
    func listKey(_ collection: String, _ params: [String: Int?]) -> [String] {
        [collection] + params.keys.sorted().map { name in
            "\(name)=\(params[name].flatMap { $0 }.map(String.init) ?? "")"
        }
    }
}
