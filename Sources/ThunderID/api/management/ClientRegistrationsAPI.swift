// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Dynamic client registration (RFC 7591) and client registration management (RFC 7592), reached
/// through `ThunderIDClient.clientRegistrations`. The collection URL comes from
/// `endpoints.clientRegistrations`, otherwise `{baseUrl}/oauth2/dcr/register`. A registration carries the
/// client's secret, so request and response bodies are never logged. A failure is answered as an OAuth
/// error, whose `error` and `error_description` are carried as ``ThunderIDError/serverError``.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct ClientRegistrationsAPI {
    let transport: ManagementTransport

    /// Registers a client and returns its registration with its `clientSecret`, which can be read only now.
    public func register(_ request: ClientRegistrationRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> ClientRegistration {
        try await transport.send("POST", body: request, fetcher: fetcher)
    }

    /// Returns a client's registration, without its secret.
    public func get(clientId: String, fetcher: ThunderIDFetcher? = nil) async throws -> ClientRegistration {
        try await transport.send("GET", [clientId], fetcher: fetcher)
    }

    /// Replaces a client's registered metadata and returns the registration, without its secret. Fields
    /// left out are not kept. The body carries `clientId` as `client_id`, as the server requires.
    /// Pass `clientSecret` to have the server check it against the client's current secret; it is never stored.
    public func update(
        clientId: String,
        _ request: ClientRegistrationRequest,
        clientSecret: String? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ClientRegistration {
        try await transport.send(
            "PUT",
            [clientId],
            body: ClientRegistrationUpdate(clientId: clientId, metadata: request, clientSecret: clientSecret),
            fetcher: fetcher
        )
    }

    /// Deletes a client's registration.
    public func delete(clientId: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", [clientId], fetcher: fetcher)
    }
}
