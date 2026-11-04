// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// How the server authenticates itself to an authorization details processor: `none`, `bearer`,
/// `basic` or `api_key`, with that method's fields in `properties`. Credential values come back
/// masked as `******`; sending a masked value back keeps the stored one while the endpoint is unchanged.
public struct OutboundAuthentication: Codable, Equatable {
    public var type: String
    public var properties: [String: String]?

    public init(type: String, properties: [String: String]? = nil) {
        self.type = type
        self.properties = properties
    }
}

/// The endpoint that authorizes and enriches the details of a type.
public struct AuthorizationDetailProcessor: Codable, Equatable {
    /// Absolute HTTPS URL of the processor. HTTP is accepted only on a loopback host.
    public var endpoint: String
    public var authentication: OutboundAuthentication?

    public init(endpoint: String, authentication: OutboundAuthentication? = nil) {
        self.endpoint = endpoint
        self.authentication = authentication
    }
}

/// A registered RFC 9396 authorization details type.
public struct AuthorizationDetailType: Codable {
    public let id: String
    /// The `type` value clients send in `authorization_details`.
    public let type: String
    public let name: String
    public let description: String?
    /// Increments when an update changes the schema, the consent template or `reuse`, or adds or
    /// removes the processor.
    public let version: Int?
    /// The JSON Schema every requested detail of this type must conform to.
    public let schema: [String: AnyCodable]
    public let consentTemplate: String?
    public let processor: AuthorizationDetailProcessor?
    /// Whether an earlier approval may stand in for the consent prompt.
    public let reuse: Bool?
    /// Whether the type is declared in configuration, so it cannot be updated or deleted.
    public let isReadOnly: Bool?
}

/// A page of authorization details types.
public struct AuthorizationDetailTypeListResponse: Codable {
    public let totalResults: Int?
    public let startIndex: Int?
    public let count: Int?
    public let types: [AuthorizationDetailType]
    public let links: [ApiPaginationLink]?
}

/// The payload used to create or replace an authorization details type. `type` cannot change after
/// creation.
public struct AuthorizationDetailTypeRequest: Codable {
    public var type: String
    public var name: String
    public var description: String?
    public var schema: [String: AnyCodable]
    public var consentTemplate: String?
    public var processor: AuthorizationDetailProcessor?
    public var reuse: Bool?

    public init(
        type: String,
        name: String,
        schema: [String: AnyCodable],
        description: String? = nil,
        consentTemplate: String? = nil,
        processor: AuthorizationDetailProcessor? = nil,
        reuse: Bool? = nil
    ) {
        self.type = type
        self.name = name
        self.description = description
        self.schema = schema
        self.consentTemplate = consentTemplate
        self.processor = processor
        self.reuse = reuse
    }
}
