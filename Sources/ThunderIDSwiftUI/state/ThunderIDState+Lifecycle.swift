// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// The input of ``ThunderIDState/accountLifecycleMutation(kind:fetcher:)``.
public struct AccountLifecycleInput {
    /// Identifier of the user, agent or application to act on.
    public let subject: String
    public let action: AccountLifecycleAction
    /// The operator's note on a suspension, recorded by the flow.
    public let operatorNote: String?

    public init(subject: String, action: AccountLifecycleAction, operatorNote: String? = nil) {
        self.subject = subject
        self.action = action
        self.operatorNote = operatorNote
    }
}

/// Reactive wrappers over the account lifecycle actions (suspend, unsuspend, unlock). These actions have
/// no management API endpoint: they run only through the administration flows the server configures.
public extension ThunderIDState {
    /// The administration flows the server configures for the lifecycle actions of `kind`, keyed by
    /// `flow` server-config key. Pass the result to
    /// ``AccountLifecycleAction/available(for:status:configuredFlows:)``. Reading it needs a token that
    /// may read the server configuration, so load it only when the actions are on.
    func accountLifecycleFlowsQuery(
        kind: AccountLifecycleSubjectKind,
        fetcher: ThunderIDFetcher? = nil
    ) -> ResourceQuery<[AdministrationFlowConfigKey: String]> {
        let client = client
        return query(key: ["administration-flows", "account-lifecycle", kind.rawValue]) {
            try await client.administrationFlows.resolve(Array(kind.flowConfigKeys.values), fetcher: fetcher)
        }
    }

    /// Runs an account lifecycle action on an identity of `kind`, then refetches that identity and the
    /// list it appears in.
    func accountLifecycleMutation(
        kind: AccountLifecycleSubjectKind,
        fetcher: ThunderIDFetcher? = nil
    ) -> ResourceMutation<AccountLifecycleInput, AccountLifecycleResult> {
        let client = client
        return mutation(
            invalidating: { input in lifecycleKeys(kind, subject: input.subject) },
            perform: { input in
                try await client.runAccountLifecycleAction(
                    input.action,
                    kind: kind,
                    subject: input.subject,
                    operatorNote: input.operatorNote,
                    fetcher: fetcher
                )
            }
        )
    }
}

private func lifecycleKeys(_ kind: AccountLifecycleSubjectKind, subject: String) -> [[String]] {
    switch kind {
    case .user: return [[UserQueryKeys.user, subject], [UserQueryKeys.users]]
    case .agent: return [[AgentQueryKeys.agent, subject], [AgentQueryKeys.agents]]
    case .application: return [[ApplicationQueryKeys.application, subject], [ApplicationQueryKeys.applications]]
    }
}
