// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// An organization unit's overview (name, handle, description, parent), its child units, and the users,
/// groups and roles in it, rendered from the data it is given. Editing is offered only when `onUpdate`
/// is set, and deleting only when `onDelete` is set; a delete asks for confirmation first.
public struct BaseOrganizationUnitDetails<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let renderState: OrganizationUnitDetailsState
    let actions: AnyView?
    let content: ((OrganizationUnitDetailsState) -> Content)?

    init(
        state: OrganizationUnitDetailsState,
        actions: AnyView?,
        renderContent: ((OrganizationUnitDetailsState) -> Content)?
    ) {
        self.renderState = state
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view, from the unit, its children,
    ///   users, groups and roles, the loading and error state, and the actions allowed.
    public init(
        unit: OrganizationUnit?,
        children: [OrganizationUnitSummary] = [],
        users: [OrganizationUnitUser] = [],
        groups: [OrganizationUnitGroup] = [],
        roles: [OrganizationUnitRole] = [],
        isLoading: Bool = false,
        error: String? = nil,
        isUpdating: Bool = false,
        isDeleting: Bool = false,
        onSelectChild: ((OrganizationUnitSummary) -> Void)? = nil,
        onUpdate: ((OrganizationUnitRequest) -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (OrganizationUnitDetailsState) -> Content
    ) {
        self.init(
            state: OrganizationUnitDetailsState(
                unit: unit,
                children: children,
                users: users,
                groups: groups,
                roles: roles,
                isLoading: isLoading,
                error: error,
                isUpdating: isUpdating,
                isDeleting: isDeleting,
                onSelectChild: onSelectChild,
                onUpdate: unit != nil ? onUpdate : nil,
                onDelete: unit != nil ? onDelete : nil
            ),
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        if let content {
            content(renderState)
        } else if let unit = renderState.unit {
            OrganizationUnitDetailsView(i18n: i18n, unit: unit, state: renderState, actions: actions)
        } else {
            AdminSection(identifier: "admin-organization-unit-details") {
                if renderState.isLoading {
                    AdminLoadingRow(label: i18n.resolve("admin.common.loading"))
                } else {
                    AdminErrorBanner(message: renderState.error ?? i18n.resolve("admin.common.errors.not_found"))
                }
            }
        }
    }
}

public extension BaseOrganizationUnitDetails where Content == EmptyView {
    init(
        unit: OrganizationUnit?,
        children: [OrganizationUnitSummary] = [],
        users: [OrganizationUnitUser] = [],
        groups: [OrganizationUnitGroup] = [],
        roles: [OrganizationUnitRole] = [],
        isLoading: Bool = false,
        error: String? = nil,
        isUpdating: Bool = false,
        isDeleting: Bool = false,
        onSelectChild: ((OrganizationUnitSummary) -> Void)? = nil,
        onUpdate: ((OrganizationUnitRequest) -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            state: OrganizationUnitDetailsState(
                unit: unit,
                children: children,
                users: users,
                groups: groups,
                roles: roles,
                isLoading: isLoading,
                error: error,
                isUpdating: isUpdating,
                isDeleting: isDeleting,
                onSelectChild: onSelectChild,
                onUpdate: unit != nil ? onUpdate : nil,
                onDelete: unit != nil ? onDelete : nil
            ),
            actions: actions,
            renderContent: nil
        )
    }
}

/// An organization unit's details, child units, and the users, groups and roles in it (the first
/// `limit` of each, read only), loaded through the management API. Set `editable` to let the signed-in
/// user change the name, handle and description, and `deletable` to let them delete the unit; both are
/// off by default, and a delete asks for confirmation first. The server refuses to delete a unit that
/// still holds child units or other resources, and to change a declarative unit; each refusal is shown
/// as its own translated message.
public struct OrganizationUnitDetails<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let organizationUnitId: String
    let limit: Int
    let editable: Bool
    let deletable: Bool
    let onSelectChild: ((OrganizationUnitSummary) -> Void)?
    let onDeleted: (() -> Void)?
    let actions: AnyView?
    let content: ((OrganizationUnitDetailsState) -> Content)?

    init(
        organizationUnitId: String,
        limit: Int = 20,
        editable: Bool = false,
        deletable: Bool = false,
        onSelectChild: ((OrganizationUnitSummary) -> Void)? = nil,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((OrganizationUnitDetailsState) -> Content)?
    ) {
        self.organizationUnitId = organizationUnitId
        self.limit = limit
        self.editable = editable
        self.deletable = deletable
        self.onSelectChild = onSelectChild
        self.onDeleted = onDeleted
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view. See ``BaseOrganizationUnitDetails``.
    public init(
        organizationUnitId: String,
        limit: Int = 20,
        editable: Bool = false,
        deletable: Bool = false,
        onSelectChild: ((OrganizationUnitSummary) -> Void)? = nil,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (OrganizationUnitDetailsState) -> Content
    ) {
        self.init(
            organizationUnitId: organizationUnitId,
            limit: limit,
            editable: editable,
            deletable: deletable,
            onSelectChild: onSelectChild,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        OrganizationUnitDetailsHost(state: thunderState, props: self).id("\(organizationUnitId)|\(limit)")
    }
}

public extension OrganizationUnitDetails where Content == EmptyView {
    init(
        organizationUnitId: String,
        limit: Int = 20,
        editable: Bool = false,
        deletable: Bool = false,
        onSelectChild: ((OrganizationUnitSummary) -> Void)? = nil,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            organizationUnitId: organizationUnitId,
            limit: limit,
            editable: editable,
            deletable: deletable,
            onSelectChild: onSelectChild,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: nil
        )
    }
}

private struct OrganizationUnitDetailsHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var unit: ResourceQuery<OrganizationUnit>
    @StateObject private var children: ResourceQuery<OrganizationUnitListResponse>
    @StateObject private var users: ResourceQuery<OrganizationUnitUserListResponse>
    @StateObject private var groups: ResourceQuery<OrganizationUnitGroupListResponse>
    @StateObject private var roles: ResourceQuery<OrganizationUnitRoleListResponse>
    @StateObject private var update: ResourceMutation<(id: String, request: OrganizationUnitRequest), OrganizationUnit>
    @StateObject private var deletion: ResourceMutation<String, Void>
    let props: OrganizationUnitDetails<Content>

    init(state: ThunderIDState, props: OrganizationUnitDetails<Content>) {
        let id = props.organizationUnitId
        _unit = StateObject(wrappedValue: state.organizationUnitQuery(id: id))
        _children = StateObject(wrappedValue: state.organizationUnitsQuery(parentId: id, limit: props.limit))
        _users = StateObject(wrappedValue: state.organizationUnitUsersQuery(id: id, limit: props.limit))
        _groups = StateObject(wrappedValue: state.organizationUnitGroupsQuery(id: id, limit: props.limit))
        _roles = StateObject(wrappedValue: state.organizationUnitRolesQuery(id: id, limit: props.limit))
        _update = StateObject(wrappedValue: state.updateOrganizationUnitMutation())
        _deletion = StateObject(wrappedValue: state.deleteOrganizationUnitMutation())
        self.props = props
    }

    var body: some View {
        BaseOrganizationUnitDetails(
            state: OrganizationUnitDetailsState(
                unit: unit.data,
                children: children.data?.organizationUnits ?? [],
                users: users.data?.users ?? [],
                groups: groups.data?.groups ?? [],
                roles: roles.data?.roles ?? [],
                isLoading: unit.isLoading,
                error: errorMessage,
                isUpdating: update.isLoading,
                isDeleting: deletion.isLoading,
                onSelectChild: props.onSelectChild,
                onUpdate: props.editable && unit.data != nil ? save : nil,
                onDelete: props.deletable && unit.data != nil ? delete : nil
            ),
            actions: props.actions,
            renderContent: props.content
        )
        .task {
            await unit.refetch()
            guard unit.data != nil else { return }
            await children.refetch()
            await users.refetch()
            await groups.refetch()
            await roles.refetch()
        }
    }

    private var errorMessage: String? {
        let prefix = "admin.organization_units"
        return i18n.managementErrorMessage(unit.error, fallbackKey: "\(prefix).details.error")
            ?? i18n.managementErrorMessage(
                update.error,
                fallbackKey: "\(prefix).details.edit.error",
                codeKeys: AdminHierarchyErrors.organizationUnitKeys
            )
            ?? i18n.managementErrorMessage(
                deletion.error,
                fallbackKey: "\(prefix).details.delete.error",
                codeKeys: AdminHierarchyErrors.organizationUnitDeleteKeys
            )
    }

    private func save(_ request: OrganizationUnitRequest) {
        Task { await update.mutate((id: props.organizationUnitId, request: request)) }
    }

    private func delete() {
        Task {
            if await deletion.mutate(props.organizationUnitId) != nil {
                props.onDeleted?()
            }
        }
    }
}
