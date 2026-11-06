// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// An organization unit, by identifier or by handle path such as `engineering/frontend`.
public enum OrganizationUnitReference: Equatable {
    case id(String)
    case path(String)

    /// The path segments under the collection: `{id}` or `tree/{a}/{b}`.
    func segments() throws -> [String] {
        switch self {
        case .id(let id): return [id]
        case .path(let path): return ["tree"] + (try ManagementPath.tree(path))
        }
    }
}

/// The settings of an organization unit that a caller sets, shared by every write.
public struct OrganizationUnitFields: Codable, Equatable {
    public var description: String?
    public var themeId: String?
    public var layoutId: String?
    public var authFlowId: String?
    public var registrationFlowId: String?
    public var isRegistrationFlowEnabled: Bool?
    public var recoveryFlowId: String?
    public var isRecoveryFlowEnabled: Bool?
    public var signOutFlowId: String?
    public var logoUrl: String?
    public var tosUri: String?
    public var policyUri: String?
    public var cookiePolicyUri: String?

    public init() {}
}

/// An organization unit.
@dynamicMemberLookup
public struct OrganizationUnit: Codable {
    public let id: String
    public let handle: String
    public let name: String
    /// The parent's identifier, or `nil` for a root.
    public let parent: String?
    public let createdAt: String?
    public let updatedAt: String?
    /// The settings, also readable directly, e.g. `unit.themeId`.
    public let fields: OrganizationUnitFields

    private enum CodingKeys: String, CodingKey {
        case id, handle, name, parent, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        handle = try container.decode(String.self, forKey: .handle)
        name = try container.decode(String.self, forKey: .name)
        parent = try container.decodeIfPresent(String.self, forKey: .parent)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        fields = try OrganizationUnitFields(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try fields.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(handle, forKey: .handle)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(parent, forKey: .parent)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<OrganizationUnitFields, Value>) -> Value {
        fields[keyPath: keyPath]
    }
}

/// An organization unit as a listing returns it.
public struct OrganizationUnitSummary: Codable {
    public let id: String
    public let handle: String
    public let name: String
    public let description: String?
    public let logoUrl: String?
    public let isReadOnly: Bool?
    public let createdAt: String?
    public let updatedAt: String?
}

/// A page of organization units.
public struct OrganizationUnitListResponse: Codable {
    public let totalResults: Int?
    public let startIndex: Int?
    public let count: Int?
    public let organizationUnits: [OrganizationUnitSummary]
    public let links: [ApiPaginationLink]?
}

/// The payload used to create an organization unit, and to update one by identifier.
public struct OrganizationUnitRequest: Codable {
    public var handle: String
    public var name: String
    /// The parent's identifier, or `nil` for a root.
    public var parent: String?
    public var fields: OrganizationUnitFields

    public init(handle: String, name: String, parent: String?, fields: OrganizationUnitFields = .init()) {
        self.handle = handle
        self.name = name
        self.parent = parent
        self.fields = fields
    }

    private enum CodingKeys: String, CodingKey {
        case handle, name, parent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        handle = try container.decode(String.self, forKey: .handle)
        name = try container.decode(String.self, forKey: .name)
        parent = try container.decodeIfPresent(String.self, forKey: .parent)
        fields = try OrganizationUnitFields(from: decoder)
    }

    /// `parent` is always sent, as `null` for a root, since the server requires it.
    public func encode(to encoder: Encoder) throws {
        try fields.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(handle, forKey: .handle)
        try container.encode(name, forKey: .name)
        try container.encode(parent, forKey: .parent)
    }
}

/// The payload used to update an organization unit by handle path. The parent cannot change.
public struct OrganizationUnitPathRequest: Codable {
    public var handle: String
    public var name: String
    public var fields: OrganizationUnitFields

    public init(handle: String, name: String, fields: OrganizationUnitFields = .init()) {
        self.handle = handle
        self.name = name
        self.fields = fields
    }

    private enum CodingKeys: String, CodingKey {
        case handle, name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        handle = try container.decode(String.self, forKey: .handle)
        name = try container.decode(String.self, forKey: .name)
        fields = try OrganizationUnitFields(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try fields.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(handle, forKey: .handle)
        try container.encode(name, forKey: .name)
    }
}

/// A user of an organization unit. `isOwned` is `false` for a user shared into it.
public struct OrganizationUnitUser: Codable {
    public let id: String
    public let type: String?
    public let display: String?
    public let isOwned: Bool?
}

/// A page of an organization unit's users.
public struct OrganizationUnitUserListResponse: Codable {
    public let totalResults: Int?
    public let startIndex: Int?
    public let count: Int?
    public let users: [OrganizationUnitUser]
    public let links: [ApiPaginationLink]?
}

/// A group of an organization unit.
public struct OrganizationUnitGroup: Codable {
    public let id: String
    public let name: String
}

/// A page of an organization unit's groups.
public struct OrganizationUnitGroupListResponse: Codable {
    public let totalResults: Int?
    public let startIndex: Int?
    public let count: Int?
    public let groups: [OrganizationUnitGroup]
    public let links: [ApiPaginationLink]?
}

/// A role of an organization unit.
public struct OrganizationUnitRole: Codable {
    public let id: String
    public let name: String
    public let description: String?
    public let isReadOnly: Bool?
}

/// A page of an organization unit's roles.
public struct OrganizationUnitRoleListResponse: Codable {
    public let totalResults: Int?
    public let startIndex: Int?
    public let count: Int?
    public let roles: [OrganizationUnitRole]
    public let links: [ApiPaginationLink]?
}
