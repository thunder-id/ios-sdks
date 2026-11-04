// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A kind of identity the account lifecycle operations act on.
public enum AccountLifecycleSubjectKind: String, CaseIterable {
    case user
    case agent
    case application

    /// The `flow` server-config key naming the flow of each action this kind supports. Applications are
    /// never locked, so they have no unlock.
    public var flowConfigKeys: [AccountLifecycleAction: AdministrationFlowConfigKey] {
        switch self {
        case .user: return [.suspend: .userSuspend, .unsuspend: .userUnsuspend, .unlock: .userUnlock]
        case .agent: return [.suspend: .agentSuspend, .unsuspend: .agentUnsuspend, .unlock: .agentUnlock]
        case .application: return [.suspend: .applicationSuspend, .unsuspend: .applicationUnsuspend]
        }
    }
}

/// An account lifecycle operation an operator can run. Locking is automatic only, so there is no lock.
public enum AccountLifecycleAction: String, CaseIterable, Identifiable {
    case suspend
    case unsuspend
    case unlock

    public var id: String { rawValue }

    /// Whether the action changes access enough to ask the operator to confirm it first. Unlocking is
    /// remedial and runs straight away.
    public var requiresConfirmation: Bool { self != .unlock }

    /// The actions each status offers, most expected first. A suspended identity offers no unlock, since
    /// a read does not show a lock beneath the suspension: once unsuspended, a remaining lock reads as
    /// `LOCKED`.
    private static func allowed(by status: AccessStatusValue) -> [AccountLifecycleAction] {
        switch status {
        case .active: return [.suspend]
        case .locked: return [.unlock, .suspend]
        case .suspended: return [.unsuspend]
        default: return []
        }
    }

    /// The actions to offer for an identity: those its status allows, that apply to its kind, and whose
    /// administration flow is configured. These actions run only through their flows, so one with no
    /// flow is never offered.
    ///
    /// - Parameters:
    ///   - kind: The kind of identity.
    ///   - status: Its effective access status. An identity with none reads as active.
    ///   - configuredFlows: The flows the server configures, as ``AdministrationFlowsAPI/resolve(_:fetcher:)``
    ///     returns them.
    /// - Returns: The actions to offer, most expected first.
    public static func available(
        for kind: AccountLifecycleSubjectKind,
        status: AccessStatusValue?,
        configuredFlows: [AdministrationFlowConfigKey: String]
    ) -> [AccountLifecycleAction] {
        let configKeys = kind.flowConfigKeys
        return allowed(by: status ?? .active).filter { action in
            guard let configKey = configKeys[action], let flow = configuredFlows[configKey] else { return false }
            return !flow.isEmpty
        }
    }
}

/// The server's limit on an operator note.
public enum AccountLifecycleConstants {
    public static let operatorNoteMaxLength = 100
}

public extension ThunderIDClient {
    /// Runs an account lifecycle action against a user, agent or application, through the operation for
    /// that kind and action (for example ``UsersAPI/suspend(id:operatorNote:fetcher:)``). Each throws its
    /// own errors, so a missing flow throws ``ThunderIDErrorCode/administrationFlowNotConfigured``. An
    /// action that does not apply to the kind, such as unlocking an application, throws
    /// ``ThunderIDErrorCode/invalidInput`` without calling the server.
    ///
    /// Running a flow needs `baseUrl`, and a token that may read the server configuration and run
    /// administration flows.
    func runAccountLifecycleAction(
        _ action: AccountLifecycleAction,
        kind: AccountLifecycleSubjectKind,
        subject: String,
        operatorNote: String? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> AccountLifecycleResult {
        switch kind {
        case .user: return try await runUserLifecycleAction(action, subject, operatorNote, fetcher)
        case .agent: return try await runAgentLifecycleAction(action, subject, operatorNote, fetcher)
        case .application: return try await runApplicationLifecycleAction(action, subject, operatorNote, fetcher)
        }
    }
}

private extension ThunderIDClient {
    func runUserLifecycleAction(
        _ action: AccountLifecycleAction,
        _ subject: String,
        _ note: String?,
        _ fetcher: ThunderIDFetcher?
    ) async throws -> AccountLifecycleResult {
        let api = try users
        switch action {
        case .suspend: return try await api.suspend(id: subject, operatorNote: note, fetcher: fetcher)
        case .unsuspend: return try await api.unsuspend(id: subject, operatorNote: note, fetcher: fetcher)
        case .unlock: return try await api.unlock(id: subject, operatorNote: note, fetcher: fetcher)
        }
    }

    func runAgentLifecycleAction(
        _ action: AccountLifecycleAction,
        _ subject: String,
        _ note: String?,
        _ fetcher: ThunderIDFetcher?
    ) async throws -> AccountLifecycleResult {
        let api = try agents
        switch action {
        case .suspend: return try await api.suspend(id: subject, operatorNote: note, fetcher: fetcher)
        case .unsuspend: return try await api.unsuspend(id: subject, operatorNote: note, fetcher: fetcher)
        case .unlock: return try await api.unlock(id: subject, operatorNote: note, fetcher: fetcher)
        }
    }

    func runApplicationLifecycleAction(
        _ action: AccountLifecycleAction,
        _ subject: String,
        _ note: String?,
        _ fetcher: ThunderIDFetcher?
    ) async throws -> AccountLifecycleResult {
        switch action {
        case .suspend: return try await applications.suspend(id: subject, operatorNote: note, fetcher: fetcher)
        case .unsuspend: return try await applications.unsuspend(id: subject, operatorNote: note, fetcher: fetcher)
        case .unlock:
            throw ThunderIDError(
                code: .invalidInput,
                message: "The unlock action does not apply to applications: they are never locked."
            )
        }
    }
}
