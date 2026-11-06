// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Gateway management operations, reached through `ThunderIDClient.gateways`. The collection URL comes
/// from `endpoints.gateways`, otherwise `{baseUrl}/gateways`. Gateways carry keys and secrets, so
/// request and response bodies are never logged.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct GatewaysAPI {
    let transport: ManagementTransport

    /// Returns every registered gateway. The server does not page this listing.
    public func list(fetcher: ThunderIDFetcher? = nil) async throws -> [Gateway] {
        try await transport.send("GET", fetcher: fetcher)
    }

    /// Returns a gateway.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> Gateway {
        try await transport.send("GET", [id], fetcher: fetcher)
    }

    /// Registers a gateway and returns it with its key, which can be read only now.
    public func create(_ gateway: RegisterGatewayRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> GatewayRegistration {
        try await transport.send("POST", body: gateway, fetcher: fetcher)
    }

    /// Updates a gateway and returns it.
    public func update(id: String, _ gateway: UpdateGatewayRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> Gateway {
        try await transport.send("PUT", [id], body: gateway, fetcher: fetcher)
    }

    /// Removes a gateway.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", [id], fetcher: fetcher)
    }

    // MARK: - Configuration

    /// Applies a configuration version to a gateway, or reports what it would change on a dry run.
    public func applyConfiguration(
        id: String,
        _ request: ApplyGatewayConfigurationRequest = .init(),
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> GatewayApplyResult {
        try await transport.send("POST", [id, "apply"], body: request, fetcher: fetcher)
    }

    /// Reverts a gateway to the configuration it ran before the last apply.
    public func revertConfiguration(
        id: String,
        _ request: RevertGatewayConfigurationRequest = .init(),
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> GatewayApplyResult {
        try await transport.send("POST", [id, "revert"], body: request, fetcher: fetcher)
    }

    /// Returns the difference between the configuration a gateway runs and the current version.
    public func configurationDiff(id: String, fetcher: ThunderIDFetcher? = nil) async throws
        -> GatewayConfigurationDiff {
        try await transport.send("GET", [id, "diff"], fetcher: fetcher)
    }

    /// Returns the configuration a gateway runs.
    public func appliedConfiguration(id: String, fetcher: ThunderIDFetcher? = nil) async throws
        -> GatewayAppliedConfiguration {
        try await transport.send("GET", [id, "applied-configuration"], fetcher: fetcher)
    }

    /// Returns the configuration version a gateway runs.
    public func appliedVersion(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> GatewayAppliedVersion {
        try await transport.send("GET", [id, "applied-version"], fetcher: fetcher)
    }
}
