// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Administration flow operations, reached through `ThunderIDClient.administrationFlows`.
///
/// The management operations that take an ``AdministrationMode`` run these for you in `.flow` mode. Use
/// them directly to run an administration flow the SDK has no operation for, or to show which
/// operations a deployment routes through a flow. The flows and their configuration live on the server
/// at `baseUrl`, so these calls go to `{baseUrl}/server-config/flow`, `{baseUrl}/flows` and
/// `{baseUrl}/flow/execute` whatever `endpoints` overrides are set.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct AdministrationFlowsAPI {
    let transport: ManagementTransport

    /// Reads the handle configured for each of several operations in one request. An operation with no
    /// handle is absent from the result.
    ///
    /// Read failures propagate: treating one as "no flow configured" would perform the operation
    /// through the API directly, which revokes nothing, and report it as a success.
    public func resolveHandles(
        _ configKeys: [AdministrationFlowConfigKey],
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> [AdministrationFlowConfigKey: String] {
        try transport.requireFlowBaseUrl()
        let layers: AdministrationFlowConfigLayers = try await transport.server(
            method: "GET",
            path: "server-config/flow",
            fetcher: fetcher
        )
        let section = layers.merged ?? [:]
        var handles: [AdministrationFlowConfigKey: String] = [:]
        for configKey in configKeys {
            if let handle = section[configKey.rawValue]?.defaultHandle, !handle.isEmpty {
                handles[configKey] = handle
            }
        }
        return handles
    }

    /// Finds the administration flows carrying the given handles, in one walk of the listing that stops
    /// once every handle is found. A handle with no flow is absent from the result.
    ///
    /// The listing is paged and newest first, which puts the bootstrap flows last, so pages of
    /// ``AdministrationFlowConstants/pageSize`` are walked until the handles are found or the listing ends.
    public func find(handles: [String], fetcher: ThunderIDFetcher? = nil) async throws -> [String: ManagedFlow] {
        try transport.requireFlowBaseUrl()
        var wanted = Set(handles)
        var found: [String: ManagedFlow] = [:]
        let pageSize = AdministrationFlowConstants.pageSize
        var offset = 0
        while !wanted.isEmpty {
            // Sequential: a page is requested only when the previous one did not complete the set.
            let page: ManagedFlowListResponse = try await transport.server(
                method: "GET",
                path: "flows",
                query: .management([
                    ("flowType", AdministrationFlowConstants.flowType),
                    ("limit", String(pageSize)),
                    ("offset", String(offset))
                ]),
                fetcher: fetcher
            )
            for flow in page.flows
            where wanted.contains(flow.handle) && flow.flowType == AdministrationFlowConstants.flowType {
                found[flow.handle] = flow
                wanted.remove(flow.handle)
            }
            // A short page is the last one, so the handles still wanted do not exist.
            if page.flows.count < pageSize {
                break
            }
            offset += pageSize
        }
        return found
    }

    /// Resolves each operation whose configured handle names an existing administration flow to that
    /// flow's identifier, in one configuration read and one listing walk. An operation with no flow is
    /// absent.
    public func resolve(
        _ configKeys: [AdministrationFlowConfigKey],
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> [AdministrationFlowConfigKey: String] {
        let handles = try await resolveHandles(configKeys, fetcher: fetcher)
        let flows = try await find(handles: Array(Set(handles.values)), fetcher: fetcher)
        return handles.compactMapValues { flows[$0]?.id }
    }

    /// Finds the administration flow the server configures for an operation, or returns `nil` when none
    /// is configured so the caller calls the API directly.
    ///
    /// Only an unset handle yields `nil`: that is the deployment asking for the direct call. A handle
    /// that names a flow that no longer exists throws ``ThunderIDErrorCode/administrationFlowNotFound``
    /// instead, since falling back would make the change without the revocation the configuration asks for.
    public func resolveId(
        _ configKey: AdministrationFlowConfigKey,
        action: String = "administration",
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> String? {
        guard let handle = try await resolveHandles([configKey], fetcher: fetcher)[configKey] else {
            return nil
        }
        guard let flow = try await find(handles: [handle], fetcher: fetcher)[handle] else {
            throw ThunderIDError(
                code: .administrationFlowNotFound,
                message: "The configured \(action) flow \"\(handle)\" no longer exists, so the action was not "
                    + "performed. Restore the flow or clear the handle from the server configuration."
            )
        }
        return flow.id
    }

    /// Runs an administration flow to completion in one call and returns the values it produced.
    ///
    /// Every input the flow needs is given up front, so it should finish without pausing. A flow that
    /// asks for more input throws ``ThunderIDErrorCode/administrationFlowIncomplete``; a step that refuses
    /// throws ``ThunderIDErrorCode/administrationFlowFailed`` with the step's error as
    /// ``ThunderIDError/flowError``.
    public func execute(
        flowId: String,
        inputs: [String: String],
        action: String = "administration",
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> [String: String] {
        try transport.requireFlowBaseUrl()
        let result: AdministrationFlowExecutionResponse = try await transport.server(
            method: "POST",
            path: "flow/execute",
            body: try JSONEncoder().encode(AdministrationFlowExecutionRequest(flowId: flowId, inputs: inputs)),
            fetcher: fetcher
        )
        switch result.flowStatus {
        case "COMPLETE":
            return result.data?.additionalData ?? [:]
        case "INCOMPLETE":
            throw ThunderIDError(
                code: .administrationFlowIncomplete,
                message: "The \(action) flow requires additional input and could not be completed."
            )
        default:
            let flowError = result.error ?? FlowError()
            throw ThunderIDError(
                code: .administrationFlowFailed,
                message: flowError.message?.defaultValue ?? flowError.description?.defaultValue
                    ?? "The \(action) flow did not complete.",
                flowError: flowError
            )
        }
    }

    /// Runs the administration flow the server configures for an operation and returns the values it
    /// produced, or returns `nil` when none is configured so the caller calls the API directly. See
    /// ``resolveId(_:action:fetcher:)``.
    public func run(
        _ configKey: AdministrationFlowConfigKey,
        inputs: [String: String],
        action: String = "administration",
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> [String: String]? {
        guard let flowId = try await resolveId(configKey, action: action, fetcher: fetcher) else {
            return nil
        }
        return try await execute(flowId: flowId, inputs: inputs, action: action, fetcher: fetcher)
    }
}

extension ManagementTransport {
    /// The administration flows of the server this transport talks to.
    var administrationFlows: AdministrationFlowsAPI {
        AdministrationFlowsAPI(transport: self)
    }

    /// Fails before any request when there is no `baseUrl`: the flows live on the server, not under a
    /// collection URL.
    func requireFlowBaseUrl() throws {
        _ = try requireBaseUrl(
            "A `baseUrl` is required to run an administration flow: running one needs the server URL, "
                + "not only a collection URL."
        )
    }

    /// Runs `mode`'s flow for `configKey`, or returns `nil` when the operation should call the API
    /// directly: in `.native` mode, or in `.flow` mode with no flow configured.
    func runAdministrationFlow(
        _ mode: AdministrationMode,
        _ configKey: AdministrationFlowConfigKey,
        inputs: [String: String],
        action: String,
        fetcher: ThunderIDFetcher?
    ) async throws -> [String: String]? {
        guard mode == .flow else { return nil }
        return try await administrationFlows.run(configKey, inputs: inputs, action: action, fetcher: fetcher)
    }

    /// The flow identifier `mode` asks for, or `nil` when the operation should call the API directly.
    func administrationFlowId(
        _ mode: AdministrationMode,
        _ configKey: AdministrationFlowConfigKey,
        action: String,
        fetcher: ThunderIDFetcher?
    ) async throws -> String? {
        guard mode == .flow else { return nil }
        return try await administrationFlows.resolveId(configKey, action: action, fetcher: fetcher)
    }
}
