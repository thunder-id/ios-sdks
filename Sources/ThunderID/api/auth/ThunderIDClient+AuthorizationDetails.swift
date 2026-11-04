// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A change a client may make to a granted detail at the token endpoint.
public struct AuthorizationDetailsModification: Codable, Equatable {
    /// The dot-separated path of the field.
    public let field: String
    /// `decrease`, `increase`, `removeItems` or `addItems`.
    public let modification: String
}

/// The public, request view of an authorization details type: what a client may send and change.
/// Processor, consent and reuse settings are never part of it.
public struct SupportedAuthorizationDetailsType: Codable {
    public let type: String
    public let name: String
    public let description: String?
    public let version: Int?
    /// The JSON Schema of the fields a client may send.
    public let schema: [String: AnyCodable]
    public let modifications: [AuthorizationDetailsModification]?
}

/// The authorization details types a client may request.
public struct AuthorizationDetailsTypesResponse: Codable {
    public let types: [SupportedAuthorizationDetailsType]
}

public extension ThunderIDClient {
    /// Returns the authorization details types (RFC 9396) a client may request, from the public
    /// `{baseUrl}/oauth2/authorization-details-types` endpoint. No sign-in is needed.
    func getSupportedAuthorizationDetailsTypes(fetcher: ThunderIDFetcher? = nil) async throws
        -> AuthorizationDetailsTypesResponse {
        try await authorizationDetailsTypesTransport().send("GET", fetcher: fetcher)
    }

    /// Returns one authorization details type a client may request. `type` may be a URI; it is
    /// percent-encoded as one path segment.
    func getSupportedAuthorizationDetailsType(_ type: String, fetcher: ThunderIDFetcher? = nil) async throws
        -> SupportedAuthorizationDetailsType {
        try await authorizationDetailsTypesTransport().send("GET", [type], fetcher: fetcher)
    }
}

private extension ThunderIDClient {
    func authorizationDetailsTypesTransport() throws -> ManagementTransport {
        var transport = try managementTransport("oauth2/authorization-details-types", override: nil)
        transport.requiresAuth = false
        return transport
    }
}
