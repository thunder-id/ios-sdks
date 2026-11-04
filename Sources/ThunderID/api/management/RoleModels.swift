// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The kind of identity a role can be assigned to.
public enum RoleAssigneeType: String, Codable, CaseIterable {
    case user
    case group
    case app
    case agent
}

/// The permissions a role grants on one resource server.
public struct RoleResourcePermissions: Codable, Hashable {
    public var resourceServerId: String
    public var permissions: [String]

    public init(resourceServerId: String, permissions: [String]) {
        self.resourceServerId = resourceServerId
        self.permissions = permissions
    }
}

/// An identity a role is assigned to.
public struct RoleAssignment: Codable, Hashable {
    public let id: String
    public let type: RoleAssigneeType
    /// The assignee's display name, resolved by the server.
    public let display: String?

    public init(id: String, type: RoleAssigneeType, display: String? = nil) {
        self.id = id
        self.type = type
        self.display = display
    }
}

/// Identifies an identity to assign a role to, or remove it from.
public struct RoleAssignmentInput: Codable, Hashable {
    public var id: String
    public var type: RoleAssigneeType

    public init(id: String, type: RoleAssigneeType) {
        self.id = id
        self.type = type
    }
}

/// The summary of a role returned in list responses.
public struct RoleSummary: Codable {
    public let id: String
    public let name: String
    public let description: String?
    public let ouId: String
    public let ouHandle: String?
    public let isReadOnly: Bool?
}

/// A role, with the permissions it grants.
public struct Role: Codable {
    public let id: String
    public let name: String
    public let description: String?
    public let ouId: String
    public let ouHandle: String?
    public let isReadOnly: Bool?
    public let permissions: [RoleResourcePermissions]
}

/// A page of roles.
public struct RoleListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let roles: [RoleSummary]
    public let links: [ApiPaginationLink]?
}

/// A page of a role's assignments.
public struct RoleAssignmentListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let assignments: [RoleAssignment]
    public let links: [ApiPaginationLink]?
}

/// The payload used to create a role, optionally with its first assignments.
public struct CreateRoleRequest: Codable {
    public var name: String
    public var ouId: String
    public var description: String?
    public var permissions: [RoleResourcePermissions]?
    public var assignments: [RoleAssignmentInput]?

    public init(
        name: String,
        ouId: String,
        description: String? = nil,
        permissions: [RoleResourcePermissions]? = nil,
        assignments: [RoleAssignmentInput]? = nil
    ) {
        self.name = name
        self.ouId = ouId
        self.description = description
        self.permissions = permissions
        self.assignments = assignments
    }
}

/// The payload used to replace a role's name, description and permissions. Assignment changes go
/// through `RolesAPI.addAssignments(id:_:)` and `RolesAPI.removeAssignments(id:_:)`.
public struct UpdateRoleRequest: Codable {
    public var name: String
    public var ouId: String
    public var description: String?
    public var permissions: [RoleResourcePermissions]

    public init(name: String, ouId: String, description: String? = nil, permissions: [RoleResourcePermissions]) {
        self.name = name
        self.ouId = ouId
        self.description = description
        self.permissions = permissions
    }
}
