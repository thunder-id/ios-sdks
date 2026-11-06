// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// OpenID4VCI credential configuration operations, reached through `ThunderIDClient.credentialConfigurations`.
/// The collection URL comes from `endpoints.credentialConfigurations`, otherwise
/// `{baseUrl}/openid4vci/credential-configurations`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct CredentialConfigurationsAPI {
    let transport: ManagementTransport

    /// Returns every credential configuration, as summaries. The server does not page this listing.
    public func list(fetcher: ThunderIDFetcher? = nil) async throws -> [CredentialConfiguration] {
        try await transport.send("GET", fetcher: fetcher)
    }

    /// Returns a credential configuration.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> CredentialConfiguration {
        try await transport.send("GET", [id], fetcher: fetcher)
    }

    /// Creates a credential configuration and returns it.
    public func create(_ configuration: CredentialConfigurationRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> CredentialConfiguration {
        try await transport.send("POST", body: configuration, fetcher: fetcher)
    }

    /// Replaces a credential configuration and returns it.
    public func update(
        id: String,
        _ configuration: CredentialConfigurationRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> CredentialConfiguration {
        try await transport.send("PUT", [id], body: configuration, fetcher: fetcher)
    }

    /// Deletes a credential configuration. Deleting one that does not exist succeeds.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", [id], fetcher: fetcher)
    }
}
