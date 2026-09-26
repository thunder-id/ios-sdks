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
