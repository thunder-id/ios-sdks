// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

public extension AgentsAPI {
    /// Suspends an agent through the configured agent suspension flow. There is no management API for it,
    /// so it throws ``ThunderIDErrorCode/administrationFlowNotConfigured`` when no flow is configured.
    func suspend(id: String, operatorNote: String? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> AccountLifecycleResult {
        try await transport.runLifecycleFlow(
            .agentSuspend,
            subject: id,
            operatorNote: operatorNote,
            action: "agent suspension",
            fetcher: fetcher
        )
    }

    /// Lifts an agent's suspension through the configured flow. See ``suspend(id:operatorNote:fetcher:)``.
    func unsuspend(id: String, operatorNote: String? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> AccountLifecycleResult {
        try await transport.runLifecycleFlow(
            .agentUnsuspend,
            subject: id,
            operatorNote: operatorNote,
            action: "agent unsuspension",
            fetcher: fetcher
        )
    }

    /// Unlocks an agent locked after failed authentication attempts, through the configured flow. See
    /// ``suspend(id:operatorNote:fetcher:)``.
    func unlock(id: String, operatorNote: String? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> AccountLifecycleResult {
        try await transport.runLifecycleFlow(
            .agentUnlock,
            subject: id,
            operatorNote: operatorNote,
            action: "agent unlock",
            fetcher: fetcher
        )
    }
}
