// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A search an admin list applies on the server: the attribute to match and the value it must equal.
public struct AdminSearch: Equatable {
    public let attribute: String
    public let value: String

    public init(attribute: String, value: String) {
        self.attribute = attribute
        self.value = value
    }
}

/// What an admin list hands its `content` closure, so the rows can be shown with any UI.
public struct AdminListState<Row> {
    public let rows: [Row]
    public let isLoading: Bool
    /// A translated message, or `nil` when there is nothing to report.
    public let error: String?
    public let limit: Int
    public let offset: Int
    /// The total on the server, or the number of rows given when it is unknown.
    public let totalResults: Int
    public let selectedId: String?
    /// Shows the page that starts at the given offset. `nil` when the list is not paginated.
    public let onPageChange: ((Int) -> Void)?
    /// Chooses a row. `nil` when rows are not selectable.
    public let onSelect: ((Row) -> Void)?
    /// The search currently applied, if any.
    public let search: AdminSearch?
    /// The attributes that can be searched, with translated labels.
    public let searchAttributes: [AdminOption]
    /// Applies a search on the server, or clears it with `nil`. `nil` when the list cannot be searched.
    public let onSearch: ((AdminSearch?) -> Void)?
}

/// What ``BaseGroupCreate`` and ``BaseRoleCreate`` hand their `content` closure.
public struct NamedResourceFormState {
    public let name: Binding<String>
    public let description: Binding<String>
    /// Whether the values can be submitted.
    public let isValid: Bool
    public let isSubmitting: Bool
    public let error: String?
    /// Submits the current values. Does nothing while they are not valid or a submission is in flight.
    public let submit: () -> Void
    public let onCancel: (() -> Void)?
}

/// What ``BaseUserCreate`` hands its `content` closure.
public struct UserCreateFormState {
    public let userTypes: [AdminOption]
    public let fields: [UserCreateField]
    /// The chosen user type. The first one is chosen until another is set.
    public let type: Binding<String>
    /// The attribute values, keyed by attribute name.
    public let values: [String: String]
    /// Whether a type is chosen and every required attribute has a value.
    public let isValid: Bool
    public let isSubmitting: Bool
    public let error: String?
    let bindingFor: (String) -> Binding<String>
    /// Submits the chosen type and the non-empty attributes. Does nothing while they are not valid.
    public let submit: () -> Void
    public let onCancel: (() -> Void)?

    /// A binding to one attribute's value.
    public func value(for name: String) -> Binding<String> { bindingFor(name) }
}

/// What ``BaseAgentCreate`` hands its `content` closure.
public struct AgentCreateFormState {
    public let agentTypes: [AdminOption]
    public let name: Binding<String>
    /// The chosen agent type. The first one is chosen until another is set.
    public let type: Binding<String>
    public let description: Binding<String>
    public let isValid: Bool
    public let isSubmitting: Bool
    public let error: String?
    /// Submits the current values. Does nothing while they are not valid or a submission is in flight.
    public let submit: () -> Void
    public let onCancel: (() -> Void)?
}

/// What ``BaseUserDetails`` hands its `content` closure.
public struct UserDetailsState {
    public let user: ManagedUser?
    /// The user's display name, or an empty string while there is no user.
    public let displayName: String
    /// The user's attributes, without the hidden ones.
    public let attributes: [String: AnyCodable]
    public let groups: [MembershipGroup]
    public let isLoading: Bool
    public let error: String?
    public let isDeleting: Bool
    public let isUpdating: Bool
    /// Deletes the user. `nil` when deletion is not allowed, including for read-only users.
    public let onDelete: (() -> Void)?
    /// Saves the given attributes. `nil` when editing is not allowed, including for read-only users.
    public let onUpdate: (([String: AnyCodable]) -> Void)?
}

/// What ``BaseAgentDetails`` hands its `content` closure.
public struct AgentDetailsState {
    public let agent: Agent?
    public let groups: [MembershipGroup]
    public let roles: [String]
    public let isLoading: Bool
    public let error: String?
    public let isDeleting: Bool
    /// Deletes the agent. `nil` when deletion is not allowed, including for read-only agents.
    public let onDelete: (() -> Void)?
}

/// What ``BaseGroupMembers`` hands its `content` closure.
public struct GroupMembersState {
    public let members: [GroupMember]
    /// The identities that can be added, keyed by member type. `nil` when adding is not allowed.
    public let candidates: [GroupMemberType: [IdentityCandidate]]?
    public let isLoading: Bool
    public let error: String?
    public let isMutating: Bool
    /// Adds a member. `nil` when adding is not allowed.
    public let onAdd: ((GroupMemberInput) -> Void)?
    /// Removes a member. `nil` when removing is not allowed.
    public let onRemove: ((GroupMember) -> Void)?
}

/// What ``BaseRoleAssignments`` hands its `content` closure.
public struct RoleAssignmentsState {
    public let assignments: [RoleAssignment]
    /// The identities the role can be assigned to, keyed by type. `nil` when assigning is not allowed.
    public let candidates: [RoleAssigneeType: [IdentityCandidate]]?
    public let isLoading: Bool
    public let error: String?
    public let isMutating: Bool
    /// Assigns the role. `nil` when assigning is not allowed.
    public let onAssign: ((RoleAssignmentInput) -> Void)?
    /// Removes an assignment. `nil` when unassigning is not allowed.
    public let onUnassign: ((RoleAssignment) -> Void)?
    /// The assignee type the list is narrowed to, or `nil` for every type.
    public let typeFilter: RoleAssigneeType?
    /// Narrows the list to one assignee type on the server, or back to every type with `nil`.
    /// `nil` when the list cannot be filtered.
    public let onTypeFilterChange: ((RoleAssigneeType?) -> Void)?
}

/// What ``BaseRolePermissions`` hands its `content` closure.
public struct RolePermissionsState {
    /// The resource servers the role grants at least one permission on, with those permissions.
    public let permissions: [RoleResourcePermissions]
    public let isLoading: Bool
    public let error: String?
    let names: [String: String]

    /// A resource server's display name, or its identifier when the name is missing.
    public func resourceServerName(for resourceServerId: String) -> String {
        names[resourceServerId] ?? resourceServerId
    }
}
