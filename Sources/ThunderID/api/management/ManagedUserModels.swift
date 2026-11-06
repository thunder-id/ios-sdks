// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A user record managed through the ThunderID management API.
///
/// This is a server record, distinct from ``User``, which describes the signed-in user.
public struct ManagedUser: Codable {
    public let id: String
    public let ouId: String
    public let ouHandle: String?
    public let type: String
    public let attributes: [String: AnyCodable]?
    public let display: String?
    public let isReadOnly: Bool?
    /// The effective access status, set by the server on a read.
    public let status: AccessStatus?
}

/// A pagination link returned alongside a list response.
public struct ApiPaginationLink: Codable {
    public let href: String
    public let rel: String
}

/// A page of users.
public struct ManagedUserListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let users: [ManagedUser]
    public let links: [ApiPaginationLink]?
}

/// The payload used to create a user.
public struct CreateManagedUserRequest: Codable {
    public var ouId: String
    public var type: String
    public var groups: [String]?
    public var attributes: [String: AnyCodable]?

    public init(ouId: String, type: String, groups: [String]? = nil, attributes: [String: AnyCodable]? = nil) {
        self.ouId = ouId
        self.type = type
        self.groups = groups
        self.attributes = attributes
    }
}

/// The payload used to update a user.
public struct UpdateManagedUserRequest: Codable {
    public var ouId: String?
    public var type: String?
    public var groups: [String]?
    public var attributes: [String: AnyCodable]?

    public init(
        ouId: String? = nil,
        type: String? = nil,
        groups: [String]? = nil,
        attributes: [String: AnyCodable]? = nil
    ) {
        self.ouId = ouId
        self.type = type
        self.groups = groups
        self.attributes = attributes
    }
}

/// A type a user can be created as.
public struct ManagedUserType: Codable {
    public let id: String
    public let handle: String
    public let displayName: String?
    public let ouId: String?
    public let ouHandle: String?
    public let allowSelfRegistration: Bool?
    public let isReadOnly: Bool?
}

/// A page of user types.
public struct ManagedUserTypeListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let types: [ManagedUserType]
}

/// A resource that references a user, such as an agent that names the user as its owner.
public struct UserUsage: Codable {
    public let id: String
    public let displayName: String
    /// The kind of resource, such as `agent`.
    public let resourceType: String
    /// What happens to the resource when the user is deleted: `fallback`, `cascade` or `restrict`.
    public let behaviorOnDelete: String
}

/// The resources that reference a user. `totalResults` and `summary` are `nil` when the server could
/// not tell; `0` means there are none.
public struct UserUsagesResponse: Codable {
    public let count: Int
    public let totalResults: Int?
    /// The number of usages of each resource type, such as `agent`.
    public let summary: [String: Int]?
    public let usages: [UserUsage]
}

/// New values for some of a user's credential attributes, keyed by attribute name.
public struct UpdateUserCredentialsRequest: Codable {
    public var credentials: [String: String]

    public init(credentials: [String: String]) {
        self.credentials = credentials
    }
}
