// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Flow management operations (the flow definitions, not their execution), reached through
/// `ThunderIDClient.flows`. The collection URL comes from `endpoints.flows`, otherwise `{baseUrl}/flows`.
/// The administration flows that state-changing operations run are always looked up on `baseUrl`; see
/// ``AdministrationFlowsAPI``.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct FlowsAPI {
    let transport: ManagementTransport

    /// Returns a page of flows, newest first.
    /// - Parameter flowType: Only flows of this type, such as `AUTHENTICATION` or `REGISTRATION`.
    public func list(
        flowType: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ManagedFlowListResponse {
        try await transport.send(
            "GET",
            query: .management([("flowType", flowType)]) + .page(limit, offset),
            fetcher: fetcher
        )
    }

    /// Returns a flow with its graph.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> FlowDefinition {
        try await transport.send("GET", [id], fetcher: fetcher)
    }

    /// Creates a flow and returns it.
    public func create(_ flow: FlowDefinitionRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> FlowDefinition {
        try await transport.send("POST", body: flow, fetcher: fetcher)
    }

    /// Saves a new version of a flow and returns it.
    public func update(id: String, _ flow: FlowDefinitionRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> FlowDefinition {
        try await transport.send("PUT", [id], body: flow, fetcher: fetcher)
    }

    /// Deletes a flow.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", [id], fetcher: fetcher)
    }

    /// Returns the saved versions of a flow.
    public func versions(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> FlowVersionListResponse {
        try await transport.send("GET", [id, "versions"], fetcher: fetcher)
    }

    /// Returns one saved version of a flow.
    public func version(id: String, version: Int, fetcher: ThunderIDFetcher? = nil) async throws -> FlowVersion {
        try await transport.send("GET", [id, "versions", String(version)], fetcher: fetcher)
    }

    /// Makes a saved version the flow's active one and returns the flow.
    public func restoreVersion(id: String, version: Int, fetcher: ThunderIDFetcher? = nil) async throws
        -> FlowDefinition {
        try await transport.send("POST", [id, "restore"], body: ["version": version], fetcher: fetcher)
    }

    /// Lists the applications and agents that use a flow, and what happens to each when it is deleted.
    public func usages(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> ResourceUsagesResponse {
        try await transport.send("GET", [id, "usages"], fetcher: fetcher)
    }
}
