// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// Reactive wrappers over the flow listing and a flow's variables. Each accepts an optional `fetcher` that
/// takes precedence over `ThunderIDConfig.http.fetcher`.
public extension ThunderIDState {
    /// A page of flows. With `ouId`, the flows that unit owns followed by the ones shared with it, each
    /// reporting ``ManagedFlow/isOwnedByOU``.
    func flowsQuery(
        flowType: String? = nil,
        ouId: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) -> ResourceQuery<ManagedFlowListResponse> {
        let client = client
        let key = listKey(FlowQueryKeys.flows, ["limit": limit, "offset": offset])
            + ["flowType=\(flowType ?? "")", "ouId=\(ouId ?? "")"]
        return query(key: key) {
            try await client.flows.list(flowType: flowType, ouId: ouId, limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    /// Loads the variables a flow declares for an organization unit and the values the unit has set, and
    /// saves them: the data behind ``FlowVariablesForm``, for building the form with any UI. Call
    /// ``FlowVariablesModel/load()`` (for example from a view's `.task`) to load it.
    func flowVariablesModel(flowId: String, ouId: String, fetcher: ThunderIDFetcher? = nil) -> FlowVariablesModel {
        let client = client
        let invalidator = invalidator
        return FlowVariablesModel(
            operations: FlowVariablesModel.Operations(
                flow: { try await client.flows.get(id: flowId, ouId: ouId, fetcher: fetcher) },
                values: { try await client.flows.variables(id: flowId, ouId: ouId, fetcher: fetcher) },
                overlay: { try await client.flows.overlayRules(id: flowId, ouId: ouId, fetcher: fetcher) },
                connections: { try await client.connections.list(ouId: ouId, limit: 100, fetcher: fetcher) },
                update: { values in
                    let saved = try await client.flows.updateVariables(
                        id: flowId,
                        FlowVariablesRequest(ouId: ouId, variables: values),
                        fetcher: fetcher
                    )
                    invalidator.invalidate([FlowVariableQueryKeys.values, flowId, ouId])
                    return saved
                }
            )
        )
    }
}

/// The variables a flow declares for an organization unit, the values the unit has set, what the unit may
/// do with each, and the connections a `CONNECTION_SELECT` variable can take. It produces no user-visible
/// side effect: failures are reported through ``error`` and ``saveError``.
@MainActor
public final class FlowVariablesModel: ObservableObject {
    /// The flow as the organization unit sees it.
    @Published public private(set) var flow: FlowDefinition?
    /// The variables the flow declares for the organization unit.
    @Published public private(set) var definitions: [FlowVariableDefinition] = []
    /// The connections the organization unit owns and the ones shared into it. Loaded only when a variable
    /// is a `CONNECTION_SELECT`.
    @Published public private(set) var connections: [ConnectionInstance] = []
    /// What the organization unit may do with each variable.
    @Published public private(set) var overlay: ResolvedOverlay?
    /// The values the organization unit has set. A variable it has not set is absent, and its default applies.
    @Published public private(set) var overrides: FlowVariableValues = [:]
    /// Why the variables could not be loaded.
    @Published public private(set) var error: Error?
    /// Why the last save failed.
    @Published public private(set) var saveError: Error?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isSaving = false
    /// Whether the flow, the unit's values and its rules have all arrived.
    @Published public private(set) var isLoaded = false

    struct Operations {
        let flow: () async throws -> FlowDefinition
        let values: () async throws -> FlowVariablesResponse
        let overlay: () async throws -> ResolvedOverlay
        let connections: () async throws -> ConnectionListResponse
        let update: (FlowVariableValues) async throws -> FlowVariablesResponse
    }

    private let operations: Operations

    init(operations: Operations) {
        self.operations = operations
    }

    /// Loads the flow, the unit's values and its rules, then the connections when a variable needs them.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let flow = operations.flow()
            async let values = operations.values()
            async let overlay = operations.overlay()
            let (loadedFlow, loadedValues, loadedOverlay) = try await (flow, values, overlay)
            self.flow = loadedFlow
            definitions = getFlowVariableDefinitions(loadedFlow)
            overrides = loadedValues.variableValues
            self.overlay = loadedOverlay
            error = nil
            isLoaded = true
            if definitions.contains(where: { $0.type == .connectionSelect }) {
                connections = try await operations.connections().connections
            }
        } catch {
            self.error = error
        }
    }

    /// Replaces the unit's overrides. A variable left out returns to its default. Never throws: read
    /// ``saveError`` to handle a failure.
    /// - Returns: The values the server saved, or `nil` when the save failed.
    @discardableResult
    public func save(_ values: FlowVariableValues) async -> FlowVariableValues? {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let saved = try await operations.update(values).variableValues
            overrides = saved
            return saved
        } catch {
            saveError = error
            return nil
        }
    }
}
