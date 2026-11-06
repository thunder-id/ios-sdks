// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One attribute of a user type or an agent type.
///
/// `type` is one of `string`, `email`, `mobile` (text, the last two with a known format), `number`,
/// `boolean`, `object` (with `properties`) or `array` (with `items`). The other fields apply to the
/// types the server allows them on.
public struct PropertyDefinition: Codable, Equatable {
    public var type: String
    public var displayName: String?
    public var required: Bool?
    public var unique: Bool?
    /// Text and number attributes only: whether the attribute holds a credential, such as a password.
    public var credential: Bool?
    /// Text attributes only: the allowed values.
    public var enumValues: [String]?
    /// Text attributes only: the pattern a value must match.
    public var regex: String?
    /// Object attributes only.
    public var properties: [String: PropertyDefinition]?
    /// Array attributes only: what each item holds.
    public var items: ArrayItemDefinition?

    public init(
        type: String,
        displayName: String? = nil,
        required: Bool? = nil,
        unique: Bool? = nil,
        credential: Bool? = nil,
        enumValues: [String]? = nil,
        regex: String? = nil,
        properties: [String: PropertyDefinition]? = nil,
        items: ArrayItemDefinition? = nil
    ) {
        self.type = type
        self.displayName = displayName
        self.required = required
        self.unique = unique
        self.credential = credential
        self.enumValues = enumValues
        self.regex = regex
        self.properties = properties
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case type, displayName, required, unique, credential, regex, properties, items
        case enumValues = "enum"
    }
}

/// What each item of an array attribute holds: a scalar (`string`, `email`, `mobile`, `number`,
/// `boolean`), optionally limited to `enumValues`, or an `object` with `properties`.
public struct ArrayItemDefinition: Codable, Equatable {
    public var type: String
    public var enumValues: [String]?
    public var properties: [String: PropertyDefinition]?

    public init(type: String, enumValues: [String]? = nil, properties: [String: PropertyDefinition]? = nil) {
        self.type = type
        self.enumValues = enumValues
        self.properties = properties
    }

    private enum CodingKeys: String, CodingKey {
        case type, properties
        case enumValues = "enum"
    }
}

/// The attributes of a user type or an agent type, keyed by attribute name.
public typealias EntityTypeSchema = [String: PropertyDefinition]

/// The attributes a type maps to the identity's display name and primary contacts.
public struct EntityTypeSystemAttributes: Codable, Equatable {
    public var display: String?
    public var primaryEmail: String?
    public var primaryMobile: String?

    public init(display: String? = nil, primaryEmail: String? = nil, primaryMobile: String? = nil) {
        self.display = display
        self.primaryEmail = primaryEmail
        self.primaryMobile = primaryMobile
    }
}

/// The attribute an agent type maps to the agent's display name.
public struct AgentTypeSystemAttributes: Codable, Equatable {
    public var display: String?

    public init(display: String? = nil) {
        self.display = display
    }
}

/// A user type with its attribute schema.
public struct ManagedUserTypeDetails: Codable {
    public let id: String
    public let handle: String
    public let displayName: String
    public let ouId: String
    public let ouHandle: String?
    public let allowSelfRegistration: Bool
    public let isReadOnly: Bool?
    public let schema: EntityTypeSchema
    public let systemAttributes: EntityTypeSystemAttributes?
}

/// The payload used to create a user type.
public struct CreateUserTypeRequest: Codable {
    public var handle: String
    public var displayName: String
    public var ouId: String
    public var schema: EntityTypeSchema
    public var allowSelfRegistration: Bool?
    public var systemAttributes: EntityTypeSystemAttributes?

    public init(
        handle: String,
        displayName: String,
        ouId: String,
        schema: EntityTypeSchema,
        allowSelfRegistration: Bool? = nil,
        systemAttributes: EntityTypeSystemAttributes? = nil
    ) {
        self.handle = handle
        self.displayName = displayName
        self.ouId = ouId
        self.schema = schema
        self.allowSelfRegistration = allowSelfRegistration
        self.systemAttributes = systemAttributes
    }
}

/// The payload used to update a user type. The handle cannot change.
public struct UpdateUserTypeRequest: Codable {
    public var displayName: String
    public var ouId: String
    public var schema: EntityTypeSchema
    public var allowSelfRegistration: Bool?
    public var systemAttributes: EntityTypeSystemAttributes?

    public init(
        displayName: String,
        ouId: String,
        schema: EntityTypeSchema,
        allowSelfRegistration: Bool? = nil,
        systemAttributes: EntityTypeSystemAttributes? = nil
    ) {
        self.displayName = displayName
        self.ouId = ouId
        self.schema = schema
        self.allowSelfRegistration = allowSelfRegistration
        self.systemAttributes = systemAttributes
    }
}

/// An agent type with its attribute schema.
public struct AgentTypeDetails: Codable {
    public let id: String
    public let handle: String
    public let displayName: String
    public let ouId: String
    public let ouHandle: String?
    public let allowSelfRegistration: Bool?
    public let schema: EntityTypeSchema
    public let systemAttributes: AgentTypeSystemAttributes?
}

/// The payload used to create an agent type.
public struct CreateAgentTypeRequest: Codable {
    public var handle: String
    public var displayName: String
    public var ouId: String
    public var schema: EntityTypeSchema
    public var allowSelfRegistration: Bool?
    public var systemAttributes: AgentTypeSystemAttributes?

    public init(
        handle: String,
        displayName: String,
        ouId: String,
        schema: EntityTypeSchema,
        allowSelfRegistration: Bool? = nil,
        systemAttributes: AgentTypeSystemAttributes? = nil
    ) {
        self.handle = handle
        self.displayName = displayName
        self.ouId = ouId
        self.schema = schema
        self.allowSelfRegistration = allowSelfRegistration
        self.systemAttributes = systemAttributes
    }
}

/// The payload used to update an agent type.
public struct UpdateAgentTypeRequest: Codable {
    public var displayName: String
    public var ouId: String
    public var schema: EntityTypeSchema
    public var systemAttributes: AgentTypeSystemAttributes?

    public init(
        displayName: String,
        ouId: String,
        schema: EntityTypeSchema,
        systemAttributes: AgentTypeSystemAttributes? = nil
    ) {
        self.displayName = displayName
        self.ouId = ouId
        self.schema = schema
        self.systemAttributes = systemAttributes
    }
}
