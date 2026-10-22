// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// The identities a role is assigned to, rendered from the data it is given. Assigning is offered
/// when both `onAssign` and `candidates` are set, for each assignee type `candidates` has an entry
/// for; unassigning when `onUnassign` is set.
public struct BaseRoleAssignments<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let assignments: [RoleAssignment]
    let candidates: [RoleAssigneeType: [IdentityCandidate]]?
    let isLoading: Bool
    let error: String?
    let isMutating: Bool
    let title: String?
    let description: String?
    let onAssign: ((RoleAssignmentInput) -> Void)?
    let onUnassign: ((RoleAssignment) -> Void)?
    let typeFilter: RoleAssigneeType?
    let onTypeFilterChange: ((RoleAssigneeType?) -> Void)?
    let content: ((RoleAssignmentsState) -> Content)?

    init(
        assignments: [RoleAssignment],
        candidates: [RoleAssigneeType: [IdentityCandidate]]? = nil,
        isLoading: Bool = false,
        error: String? = nil,
        isMutating: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onAssign: ((RoleAssignmentInput) -> Void)? = nil,
        onUnassign: ((RoleAssignment) -> Void)? = nil,
        typeFilter: RoleAssigneeType? = nil,
        onTypeFilterChange: ((RoleAssigneeType?) -> Void)? = nil,
        renderContent: ((RoleAssignmentsState) -> Content)?
    ) {
        self.assignments = assignments
        self.candidates = candidates
        self.isLoading = isLoading
        self.error = error
        self.isMutating = isMutating
        self.title = title
        self.description = description
        self.onAssign = onAssign
        self.onUnassign = onUnassign
        self.typeFilter = typeFilter
        self.onTypeFilterChange = onTypeFilterChange
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default table and picker, from the assignments, the
    ///   candidates, the loading and error state, and the assign and unassign actions.
    public init(
        assignments: [RoleAssignment],
        candidates: [RoleAssigneeType: [IdentityCandidate]]? = nil,
        isLoading: Bool = false,
        error: String? = nil,
        isMutating: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onAssign: ((RoleAssignmentInput) -> Void)? = nil,
        onUnassign: ((RoleAssignment) -> Void)? = nil,
        typeFilter: RoleAssigneeType? = nil,
        onTypeFilterChange: ((RoleAssigneeType?) -> Void)? = nil,
        @ViewBuilder content: @escaping (RoleAssignmentsState) -> Content
    ) {
        self.init(
            assignments: assignments,
            candidates: candidates,
            isLoading: isLoading,
            error: error,
            isMutating: isMutating,
            title: title,
            description: description,
            onAssign: onAssign,
            onUnassign: onUnassign,
            typeFilter: typeFilter,
            onTypeFilterChange: onTypeFilterChange,
            renderContent: content
        )
    }

    public var body: some View {
        if let content {
            content(renderState)
        } else {
            defaultBody
        }
    }

    private var renderState: RoleAssignmentsState {
        RoleAssignmentsState(
            assignments: assignments,
            candidates: onAssign == nil ? nil : candidates,
            isLoading: isLoading,
            error: error,
            isMutating: isMutating,
            onAssign: candidates == nil ? nil : onAssign,
            onUnassign: onUnassign,
            typeFilter: typeFilter,
            onTypeFilterChange: onTypeFilterChange
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        AdminIdentityTable(
            i18n: i18n,
            identifier: "admin-role-assignments",
            title: title ?? i18n.resolve("admin.roles.assignments.title"),
            description: description,
            rows: assignments.map { AdminRelatedIdentity(id: $0.id, type: $0.type, display: $0.display) },
            emptyText: i18n.resolve("admin.roles.assignments.empty"),
            addLabel: i18n.resolve("admin.roles.assignments.add"),
            removeLabelKey: "admin.roles.assignments.remove_label",
            typeOrder: [.user, .group, .agent, .app],
            candidates: candidates,
            isLoading: isLoading,
            error: error,
            isMutating: isMutating,
            onAdd: onAssign.map { assign in { id, type in assign(RoleAssignmentInput(id: id, type: type)) } },
            onRemove: onUnassign.map { unassign in
                { identity in
                    unassign(RoleAssignment(id: identity.id, type: identity.type, display: identity.display))
                }
            },
            toolbar: onTypeFilterChange.map { change in AnyView(typePicker(change)) }
        )
    }

    private func typePicker(_ change: @escaping (RoleAssigneeType?) -> Void) -> some View {
        let types: [RoleAssigneeType] = [.user, .group, .agent, .app]
        return AdminPicker(
            label: i18n.resolve("admin.common.filters.type"),
            name: "assignee-type",
            options: [AdminOption(label: i18n.resolve("admin.common.filters.all_types"), value: "")]
                + types.map {
                    AdminOption(label: i18n.resolve("admin.common.identity_types.\($0.rawValue)"), value: $0.rawValue)
                },
            selection: Binding(
                get: { typeFilter?.rawValue ?? "" },
                set: { change(RoleAssigneeType(rawValue: $0)) }
            )
        )
    }
}

public extension BaseRoleAssignments where Content == EmptyView {
    init(
        assignments: [RoleAssignment],
        candidates: [RoleAssigneeType: [IdentityCandidate]]? = nil,
        isLoading: Bool = false,
        error: String? = nil,
        isMutating: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onAssign: ((RoleAssignmentInput) -> Void)? = nil,
        onUnassign: ((RoleAssignment) -> Void)? = nil,
        typeFilter: RoleAssigneeType? = nil,
        onTypeFilterChange: ((RoleAssigneeType?) -> Void)? = nil
    ) {
        self.init(
            assignments: assignments,
            candidates: candidates,
            isLoading: isLoading,
            error: error,
            isMutating: isMutating,
            title: title,
            description: description,
            onAssign: onAssign,
            onUnassign: onUnassign,
            typeFilter: typeFilter,
            onTypeFilterChange: onTypeFilterChange,
            renderContent: nil
        )
    }
}

/// The identities a role is assigned to, loaded through the management API. Set `editable` to let
/// the signed-in user assign the role to users, groups and agents and remove assignments; it is
/// off by default.
public struct RoleAssignments<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let roleId: String
    let editable: Bool
    let filterable: Bool
    let title: String?
    let description: String?
    let content: ((RoleAssignmentsState) -> Content)?
    @State private var typeFilter: RoleAssigneeType?

    init(
        roleId: String,
        editable: Bool = false,
        filterable: Bool = true,
        title: String? = nil,
        description: String? = nil,
        renderContent: ((RoleAssignmentsState) -> Content)?
    ) {
        self.roleId = roleId
        self.editable = editable
        self.filterable = filterable
        self.title = title
        self.description = description
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default table and picker. See ``BaseRoleAssignments``.
    public init(
        roleId: String,
        editable: Bool = false,
        filterable: Bool = true,
        title: String? = nil,
        description: String? = nil,
        @ViewBuilder content: @escaping (RoleAssignmentsState) -> Content
    ) {
        self.init(
            roleId: roleId,
            editable: editable,
            filterable: filterable,
            title: title,
            description: description,
            renderContent: content
        )
    }

    public var body: some View {
        RoleAssignmentsHost(
            state: thunderState,
            props: self,
            typeFilter: typeFilter,
            onTypeFilterChange: filterable ? { typeFilter = $0 } : nil
        )
        .id("\(roleId)|\(editable)|\(typeFilter?.rawValue ?? "")")
    }
}

public extension RoleAssignments where Content == EmptyView {
    init(
        roleId: String,
        editable: Bool = false,
        filterable: Bool = true,
        title: String? = nil,
        description: String? = nil
    ) {
        self.init(
            roleId: roleId,
            editable: editable,
            filterable: filterable,
            title: title,
            description: description,
            renderContent: nil
        )
    }
}

private struct RoleAssignmentsHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var assignments: ResourceQuery<RoleAssignmentListResponse>
    @StateObject private var users: ResourceQuery<ManagedUserListResponse>
    @StateObject private var groups: ResourceQuery<GroupListResponse>
    @StateObject private var agents: ResourceQuery<AgentListResponse>
    @StateObject private var assign: ResourceMutation<RoleAssignmentsInput, Void>
    @StateObject private var unassign: ResourceMutation<RoleAssignmentsInput, Void>
    let props: RoleAssignments<Content>
    let typeFilter: RoleAssigneeType?
    let onTypeFilterChange: ((RoleAssigneeType?) -> Void)?

    init(
        state: ThunderIDState,
        props: RoleAssignments<Content>,
        typeFilter: RoleAssigneeType?,
        onTypeFilterChange: ((RoleAssigneeType?) -> Void)?
    ) {
        _assignments = StateObject(
            wrappedValue: state.roleAssignmentsQuery(roleId: props.roleId, type: typeFilter, limit: 100)
        )
        _users = StateObject(wrappedValue: state.usersQuery(limit: 100))
        _groups = StateObject(wrappedValue: state.groupsQuery(limit: 100))
        _agents = StateObject(wrappedValue: state.agentsQuery(limit: 100))
        _assign = StateObject(wrappedValue: state.addRoleAssignmentsMutation())
        _unassign = StateObject(wrappedValue: state.removeRoleAssignmentsMutation())
        self.props = props
        self.typeFilter = typeFilter
        self.onTypeFilterChange = onTypeFilterChange
    }

    var body: some View {
        BaseRoleAssignments(
            assignments: assignments.data?.assignments ?? [],
            candidates: props.editable ? candidates : nil,
            isLoading: assignments.isLoading,
            error: i18n.managementErrorMessage(assignments.error, fallbackKey: "admin.roles.assignments.error")
                ?? i18n.managementErrorMessage(
                    assign.error ?? unassign.error,
                    fallbackKey: "admin.roles.assignments.update_error"
                ),
            isMutating: assign.isLoading || unassign.isLoading,
            title: props.title,
            description: props.description,
            onAssign: props.editable ? addAssignment : nil,
            onUnassign: props.editable ? removeAssignment : nil,
            typeFilter: typeFilter,
            onTypeFilterChange: onTypeFilterChange,
            renderContent: props.content
        )
        .task {
            await assignments.refetch()
            guard props.editable else { return }
            await users.refetch()
            await groups.refetch()
            await agents.refetch()
        }
    }

    private var candidates: [RoleAssigneeType: [IdentityCandidate]] {
        [
            .user: AdminCandidates.users(users.data),
            .group: AdminCandidates.groups(groups.data),
            .agent: AdminCandidates.agents(agents.data)
        ]
    }

    private func addAssignment(_ assignment: RoleAssignmentInput) {
        Task { await assign.mutate((roleId: props.roleId, assignments: [assignment])) }
    }

    private func removeAssignment(_ assignment: RoleAssignment) {
        let input = RoleAssignmentInput(id: assignment.id, type: assignment.type)
        Task { await unassign.mutate((roleId: props.roleId, assignments: [input])) }
    }
}
