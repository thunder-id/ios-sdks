// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The vendor of a connection, which is also its path under `/connections`.
public enum ConnectionType: String, Codable, CaseIterable {
    case authzenPdp = "authzen-pdp"
    case emailSmtp = "email-smtp"
    case github
    case google
    case http
    case oauth
    case oidc
    case smsGateway = "sms-gateway"
    case twilio
    case vonage
}

/// A connection in the listing of every connection.
public struct ConnectionInstance: Codable {
    public let id: String
    public let name: String
    public let description: String?
    /// The vendor, such as `google`. A `String` so a vendor added on the server still reads.
    public let type: String
    /// The categories the connection serves, such as `identity-provider` or `email-provider`.
    public let categories: [String]
}

/// A page of every connection.
public struct ConnectionListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let connections: [ConnectionInstance]
    public let links: [ApiPaginationLink]?
}

/// A connection in the listing of one vendor's connections.
public struct ConnectionSummary: Codable {
    public let id: String
    public let name: String
    public let description: String?
}

/// A connection with its vendor settings.
///
/// The settings differ by vendor (for example `clientId`, `redirectUri` and `attributeConfiguration`
/// for an identity provider, `host` and `port` for SMTP, `url` and `headers` for HTTP), so they are kept
/// as JSON in ``settings``, with names as the server's connections API gives them. Credentials the
/// server returns, such as a client secret, are among them: do not log a connection.
public struct Connection: Codable {
    public let id: String?
    public let name: String?
    public let description: String?
    public let type: String?
    /// Every vendor setting, keyed by name.
    public let settings: [String: AnyCodable]

    private static let named: Set<String> = ["id", "name", "description", "type"]

    private enum CodingKeys: String, CodingKey {
        case id, name, description, type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        settings = try decoder.remainingFields(excluding: Self.named)
    }

    public func encode(to encoder: Encoder) throws {
        try encoder.encodeFields(settings, excluding: Self.named)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(type, forKey: .type)
    }
}

/// The payload used to create or update a connection: its name and description, and the vendor's
/// settings as the server's connections API names them, such as `clientId` and `redirectUri`.
public struct ConnectionRequest: Encodable {
    public var name: String
    public var description: String?
    public var settings: [String: AnyCodable]

    public init(name: String, description: String? = nil, settings: [String: AnyCodable] = [:]) {
        self.name = name
        self.description = description
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case name, description
    }

    public func encode(to encoder: Encoder) throws {
        try encoder.encodeFields(settings, excluding: ["name", "description"])
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

/// One field of an outbound authentication method.
public struct OutboundAuthField: Codable {
    public let key: String?
    public let type: String?
    public let required: Bool?
    /// Whether the field holds a credential.
    public let credential: Bool?
    public let displayName: String?
}

/// An outbound authentication method a vendor supports, with the fields it takes.
public struct OutboundAuthMethod: Codable {
    public let type: String?
    public let displayName: String?
    public let fields: [OutboundAuthField]?
}

/// The authentication methods of one vendor.
public struct ConnectionVendorAuthentication: Codable {
    public let methods: [OutboundAuthMethod]?
}

/// What one vendor supports.
public struct ConnectionVendorMeta: Codable {
    public let vendor: String?
    public let authentication: ConnectionVendorAuthentication?
}

/// What each connection vendor supports.
public struct ConnectionMetaResponse: Codable {
    public let vendors: [ConnectionVendorMeta]?
}
