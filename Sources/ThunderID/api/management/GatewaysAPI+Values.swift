// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A gateway's own variables and secrets. The calls pass through to the gateway and are answered in
/// the shapes of ``VariablesAPI`` and ``SecretsAPI``; a secret's value is held only by the gateway.
public extension GatewaysAPI {
    // MARK: - Variables

    /// Returns a page of a gateway's variables. See ``VariablesAPI/list(limit:offset:names:filter:fetcher:)``.
    func variables(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil,
        names: [String]? = nil,
        filter: String? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> VariableListResponse {
        try await transport.send(
            "GET",
            [id, "variables"],
            query: ManagementTransport.valueQuery(limit, offset, names, filter),
            fetcher: fetcher
        )
    }

    /// Returns one of a gateway's variables.
    func variable(id: String, name: String, fetcher: ThunderIDFetcher? = nil) async throws -> Variable {
        try await transport.send("GET", [id, "variables", name], fetcher: fetcher)
    }

    /// Creates a variable on a gateway and returns it.
    func createVariable(id: String, _ variable: ValueEntryRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> Variable {
        try await transport.send("POST", [id, "variables"], body: variable, fetcher: fetcher)
    }

    /// Updates a gateway's variable, or creates it when it does not exist, and returns it.
    func updateVariable(
        id: String,
        name: String,
        _ variable: ValueEntryUpdateRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> Variable {
        try await transport.send("PUT", [id, "variables", name], body: variable, fetcher: fetcher)
    }

    /// Deletes a gateway's variable.
    func deleteVariable(id: String, name: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", [id, "variables", name], fetcher: fetcher)
    }

    // MARK: - Secrets

    /// Returns a page of a gateway's secrets, without their values.
    func secrets(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil,
        names: [String]? = nil,
        filter: String? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> SecretListResponse {
        try await transport.send(
            "GET",
            [id, "secrets"],
            query: ManagementTransport.valueQuery(limit, offset, names, filter),
            fetcher: fetcher
        )
    }

    /// Returns one of a gateway's secrets, without its value.
    func secret(id: String, name: String, fetcher: ThunderIDFetcher? = nil) async throws -> Secret {
        try await transport.send("GET", [id, "secrets", name], fetcher: fetcher)
    }

    /// Creates a secret on a gateway and returns it, without its value.
    func createSecret(id: String, _ secret: ValueEntryRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> Secret {
        try await transport.send("POST", [id, "secrets"], body: secret, fetcher: fetcher)
    }

    /// Sets a gateway's secret, or creates it when it does not exist, and returns it without its value.
    func updateSecret(
        id: String,
        name: String,
        _ secret: ValueEntryUpdateRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> Secret {
        try await transport.send("PUT", [id, "secrets", name], body: secret, fetcher: fetcher)
    }

    /// Deletes a gateway's secret.
    func deleteSecret(id: String, name: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", [id, "secrets", name], fetcher: fetcher)
    }
}
