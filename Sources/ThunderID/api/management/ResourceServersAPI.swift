// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Resource server, resource and action management operations, reached through
/// `ThunderIDClient.resourceServers`. The collection URL comes from `endpoints.resourceServers`,
/// otherwise `{baseUrl}/resource-servers`. An action belongs to the server, or to one of its resources
/// when `resourceId` is given.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct ResourceServersAPI {
    let transport: ManagementTransport

    // MARK: - Resource servers

    /// Returns a page of resource servers.
    public func list(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> ResourceServerListResponse {
        try await transport.send("GET", query: .page(limit, offset), fetcher: fetcher)
    }

    /// Returns a resource server.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> ResourceServer {
        try await transport.send("GET", [id], fetcher: fetcher)
    }

    /// Creates a resource server and returns it as the server stored it.
    public func create(_ server: CreateResourceServerRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> ResourceServer {
        try await transport.send("POST", body: server, fetcher: fetcher)
    }

    /// Updates a resource server and returns it.
    public func update(id: String, _ server: UpdateResourceServerRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> ResourceServer {
        try await transport.send("PUT", [id], body: server, fetcher: fetcher)
    }

    /// Deletes a resource server.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", [id], fetcher: fetcher)
    }

    // MARK: - Resources

    /// Returns a page of a resource server's resources: the top-level ones, or the children of `parentId`.
    public func resources(
        resourceServerId: String,
        parentId: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ServerResourceListResponse {
        try await transport.send(
            "GET",
            [resourceServerId, "resources"],
            query: .management([("parentId", parentId)]) + .page(limit, offset),
            fetcher: fetcher
        )
    }

    /// Returns a resource.
    public func resource(resourceServerId: String, resourceId: String, fetcher: ThunderIDFetcher? = nil)
        async throws -> ServerResource {
        try await transport.send("GET", [resourceServerId, "resources", resourceId], fetcher: fetcher)
    }

    /// Creates a resource and returns it.
    public func createResource(
        resourceServerId: String,
        _ resource: CreateServerResourceRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ServerResource {
        try await transport.send("POST", [resourceServerId, "resources"], body: resource, fetcher: fetcher)
    }

    /// Updates a resource's name and description and returns it.
    public func updateResource(
        resourceServerId: String,
        resourceId: String,
        _ resource: UpdateNamedItemRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ServerResource {
        try await transport.send("PUT", [resourceServerId, "resources", resourceId], body: resource, fetcher: fetcher)
    }

    /// Deletes a resource.
    public func deleteResource(resourceServerId: String, resourceId: String, fetcher: ThunderIDFetcher? = nil)
        async throws {
        try await transport.sendWithoutResult("DELETE", [resourceServerId, "resources", resourceId], fetcher: fetcher)
    }

    // MARK: - Actions

    /// Returns a page of the actions on a resource server, or on one of its resources.
    /// - Parameter kind: `tool` or `resource`, to list only that kind.
    public func actions(
        resourceServerId: String,
        resourceId: String? = nil,
        kind: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ResourceActionListResponse {
        try await transport.send(
            "GET",
            actionsPath(resourceServerId, resourceId),
            query: .management([("kind", kind)]) + .page(limit, offset),
            fetcher: fetcher
        )
    }

    /// Returns an action.
    public func action(
        resourceServerId: String,
        resourceId: String? = nil,
        actionId: String,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ResourceAction {
        try await transport.send("GET", actionsPath(resourceServerId, resourceId) + [actionId], fetcher: fetcher)
    }

    /// Creates an action and returns it.
    public func createAction(
        resourceServerId: String,
        resourceId: String? = nil,
        _ action: CreateResourceActionRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ResourceAction {
        try await transport.send("POST", actionsPath(resourceServerId, resourceId), body: action, fetcher: fetcher)
    }

    /// Updates an action's name and description and returns it.
    public func updateAction(
        resourceServerId: String,
        resourceId: String? = nil,
        actionId: String,
        _ action: UpdateNamedItemRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ResourceAction {
        try await transport.send(
            "PUT",
            actionsPath(resourceServerId, resourceId) + [actionId],
            body: action,
            fetcher: fetcher
        )
    }

    /// Deletes an action. In `.flow` mode the configured action deletion flow runs instead, revoking the
    /// permission the action defines before the record goes.
    public func deleteAction(
        resourceServerId: String,
        resourceId: String? = nil,
        actionId: String,
        administrationMode: AdministrationMode = .native,
        fetcher: ThunderIDFetcher? = nil
    ) async throws {
        let path = actionsPath(resourceServerId, resourceId) + [actionId]
        var inputs = [
            AdministrationFlowInput.action: actionId,
            AdministrationFlowInput.resourceServer: resourceServerId
        ]
        if let resourceId {
            inputs[AdministrationFlowInput.resource] = resourceId
        }
        let ran = try await transport.runAdministrationFlow(
            administrationMode,
            .actionDeletion,
            inputs: inputs,
            action: "action deletion",
            fetcher: fetcher
        )
        if ran != nil { return }
        try await transport.sendWithoutResult("DELETE", path, fetcher: fetcher)
    }

    private func actionsPath(_ resourceServerId: String, _ resourceId: String?) -> [String] {
        resourceId.map { [resourceServerId, "resources", $0, "actions"] } ?? [resourceServerId, "actions"]
    }
}
