// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The kind of identity a group can contain.
public enum GroupMemberType: String, Codable, CaseIterable {
    case user
    case group
    case agent
}

/// A member of a group.
public struct GroupMember: Codable, Hashable {
    public let id: String
    public let type: GroupMemberType
    /// The member's display name, resolved by the server.
    public let display: String?

    public init(id: String, type: GroupMemberType, display: String? = nil) {
        self.id = id
        self.type = type
        self.display = display
    }
}

/// Identifies an identity to add to, or remove from, a group.
public struct GroupMemberInput: Codable, Hashable {
    public var id: String
    public var type: GroupMemberType

    public init(id: String, type: GroupMemberType) {
        self.id = id
        self.type = type
    }
}

/// A group of users, agents and other groups. Named to stay clear of SwiftUI's `Group`.
public struct ManagedGroup: Codable {
    public let id: String
    public let name: String
    public let description: String?
    public let ouId: String
    public let ouHandle: String?
    public let members: [GroupMember]?
}

/// A page of groups.
public struct GroupListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let groups: [ManagedGroup]
    public let links: [ApiPaginationLink]?
}

/// A page of a group's members.
public struct GroupMemberListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let members: [GroupMember]
    public let links: [ApiPaginationLink]?
}

/// The payload used to create a group.
public struct CreateGroupRequest: Codable {
    public var name: String
    public var ouId: String
    public var description: String?
    public var members: [GroupMemberInput]?

    public init(name: String, ouId: String, description: String? = nil, members: [GroupMemberInput]? = nil) {
        self.name = name
        self.ouId = ouId
        self.description = description
        self.members = members
    }
}

/// The payload used to update a group. Membership changes go through
/// `GroupsAPI.addMembers(id:_:)` and `GroupsAPI.removeMembers(id:_:)`.
public struct UpdateGroupRequest: Codable {
    public var name: String
    public var ouId: String
    public var description: String?

    public init(name: String, ouId: String, description: String? = nil) {
        self.name = name
        self.ouId = ouId
        self.description = description
    }
}

/// A group an identity belongs to.
public struct MembershipGroup: Codable, Hashable {
    public let id: String
    public let name: String
    public let ouId: String
}

/// A page of the groups an identity belongs to.
public struct MembershipGroupListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let groups: [MembershipGroup]
    public let links: [ApiPaginationLink]?
}
