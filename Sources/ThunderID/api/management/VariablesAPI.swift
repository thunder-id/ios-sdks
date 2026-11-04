// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Server-level variable operations, reached through `ThunderIDClient.variables`. The collection URL
/// comes from `endpoints.variables`, otherwise `{baseUrl}/variables`. Variable values can be
/// sensitive, so request and response bodies are never logged.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct VariablesAPI {
    let transport: ManagementTransport

    /// Returns a page of variables with their values, in name order.
    /// - Parameters:
    ///   - names: Only these names. A name with nothing stored is absent from the result.
    ///   - filter: A server-side filter on the names.
    public func list(
        limit: Int? = nil,
        offset: Int? = nil,
        names: [String]? = nil,
        filter: String? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> VariableListResponse {
        try await transport.send(
            "GET",
            query: ManagementTransport.valueQuery(limit, offset, names, filter),
            fetcher: fetcher
        )
    }

    /// Returns a variable.
    public func get(name: String, fetcher: ThunderIDFetcher? = nil) async throws -> Variable {
        try await transport.send("GET", [name], fetcher: fetcher)
    }

    /// Creates a variable and returns it.
    public func create(_ variable: ValueEntryRequest, fetcher: ThunderIDFetcher? = nil) async throws -> Variable {
        try await transport.send("POST", body: variable, fetcher: fetcher)
    }

    /// Updates a variable, or creates it when it does not exist, and returns it.
    public func update(name: String, _ variable: ValueEntryUpdateRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> Variable {
        try await transport.send("PUT", [name], body: variable, fetcher: fetcher)
    }

    /// Deletes a variable.
    public func delete(name: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", [name], fetcher: fetcher)
    }
}

/// Server-level secret operations, reached through `ThunderIDClient.secrets`. The collection URL comes
/// from `endpoints.secrets`, otherwise `{baseUrl}/secrets`. A secret's value is write-only: it is never
/// returned, and request bodies are never logged.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct SecretsAPI {
    let transport: ManagementTransport

    /// Returns a page of secrets, each saying whether a value is set, in name order.
    /// - Parameters:
    ///   - names: Only these names. A name with nothing stored is absent from the result.
    ///   - filter: A server-side filter on the names.
    public func list(
        limit: Int? = nil,
        offset: Int? = nil,
        names: [String]? = nil,
        filter: String? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> SecretListResponse {
        try await transport.send(
            "GET",
            query: ManagementTransport.valueQuery(limit, offset, names, filter),
            fetcher: fetcher
        )
    }

    /// Returns a secret, without its value.
    public func get(name: String, fetcher: ThunderIDFetcher? = nil) async throws -> Secret {
        try await transport.send("GET", [name], fetcher: fetcher)
    }

    /// Creates a secret and returns it, without its value.
    public func create(_ secret: ValueEntryRequest, fetcher: ThunderIDFetcher? = nil) async throws -> Secret {
        try await transport.send("POST", body: secret, fetcher: fetcher)
    }

    /// Sets a secret's value, or creates it when it does not exist, and returns it without its value.
    public func update(name: String, _ secret: ValueEntryUpdateRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> Secret {
        try await transport.send("PUT", [name], body: secret, fetcher: fetcher)
    }

    /// Deletes a secret.
    public func delete(name: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", [name], fetcher: fetcher)
    }
}
