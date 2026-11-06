// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A role's name, description and overview, rendered from the data it is given. Deleting is offered
/// only when `onDelete` is set, and never for a read-only role; it asks for confirmation first.
/// `sections` is rendered under the overview once the role is there; ``RoleDetails`` puts the role's
/// ``RolePermissions`` and ``RoleAssignments`` in it.
public struct BaseRoleDetails<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let role: Role?
    let isLoading: Bool
    let error: String?
    let isDeleting: Bool
    let onDelete: (() -> Void)?
    let actions: AnyView?
    let sections: AnyView?
    let content: ((RoleDetailsState) -> Content)?

    init(
        role: Role?,
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        onDelete: (() -> Void)? = nil,
        actions: AnyView? = nil,
        sections: AnyView? = nil,
        renderContent: ((RoleDetailsState) -> Content)?
    ) {
        self.role = role
        self.isLoading = isLoading
        self.error = error
        self.isDeleting = isDeleting
        self.onDelete = onDelete
        self.actions = actions
        self.sections = sections
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view, from the role, the loading
    ///   and error state, and the delete action. `sections` is not rendered then.
    public init(
        role: Role?,
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        onDelete: (() -> Void)? = nil,
        actions: AnyView? = nil,
        sections: AnyView? = nil,
        @ViewBuilder content: @escaping (RoleDetailsState) -> Content
    ) {
        self.init(
            role: role,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            onDelete: onDelete,
            actions: actions,
            sections: sections,
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

    private var renderState: RoleDetailsState {
        RoleDetailsState(
            role: role,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            onDelete: role != nil && role?.isReadOnly != true ? onDelete : nil
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        if let role {
            details(role)
        } else {
            AdminSection(identifier: "admin-role-details") {
                if isLoading {
                    AdminLoadingRow(label: i18n.resolve("admin.common.loading"))
                } else {
                    AdminErrorBanner(message: error ?? i18n.resolve("admin.common.errors.not_found"))
                }
            }
        }
    }

    private func details(_ role: Role) -> some View {
        AdminSection(
            identifier: "admin-role-details",
            title: role.name,
            description: role.description,
            actions: { headerActions(role) },
            content: {
                if let error {
                    AdminErrorBanner(message: error)
                }
                AdminPanel(title: i18n.resolve("admin.roles.details.overview")) {
                    AdminDetailList(items: [
                        (i18n.resolve("admin.common.columns.organization_unit"), role.ouHandle ?? role.ouId)
                    ])
                }
                if let sections {
                    sections
                }
            }
        )
    }

    private func headerActions(_ role: Role) -> some View {
        HStack(spacing: 8) {
            actions
            if let onDelete, role.isReadOnly != true {
                AdminConfirmButton(
                    i18n: i18n,
                    title: i18n.resolve("admin.roles.details.delete.action"),
                    confirmText: i18n.resolve("admin.roles.details.delete.confirm", ["name": role.name]),
                    isLoading: isDeleting,
                    identifier: "admin-role-details-delete",
                    onConfirm: onDelete
                )
            }
        }
    }
}

public extension BaseRoleDetails where Content == EmptyView {
    init(
        role: Role?,
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        onDelete: (() -> Void)? = nil,
        actions: AnyView? = nil,
        sections: AnyView? = nil
    ) {
        self.init(
            role: role,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            onDelete: onDelete,
            actions: actions,
            sections: sections,
            renderContent: nil
        )
    }
}

/// A role's details, permissions and assignments, loaded through the management API. Set `editable`
/// to let the signed-in user add and remove the role's permissions and assign and unassign the role,
/// and `deletable` to let them delete it; both are off by default, a delete or a permission removal
/// asks for confirmation first, and a read-only role is never deleted. `administrationMode` chooses
/// how permissions and assignments are removed and how the role is deleted: `.flow` runs the flows
/// the server configures (the role deletion flow revokes the scopes the role granted first), falling
/// back to the API when none is configured. It defaults to `.native`. Assignees are offered from the
/// role's organization unit. With `content`, the custom UI replaces the whole view, permissions and
/// assignments included.
public struct RoleDetails<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let roleId: String
    let administrationMode: AdministrationMode
    let editable: Bool
    let deletable: Bool
    let onDeleted: (() -> Void)?
    let actions: AnyView?
    let content: ((RoleDetailsState) -> Content)?

    init(
        roleId: String,
        administrationMode: AdministrationMode = .native,
        editable: Bool = false,
        deletable: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((RoleDetailsState) -> Content)?
    ) {
        self.roleId = roleId
        self.administrationMode = administrationMode
        self.editable = editable
        self.deletable = deletable
        self.onDeleted = onDeleted
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameters:
    ///   - administrationMode: How assignments are removed and the role is deleted. See ``AdministrationMode``.
    ///   - content: Renders custom UI in place of the default view. See ``BaseRoleDetails``.
    public init(
        roleId: String,
        administrationMode: AdministrationMode = .native,
        editable: Bool = false,
        deletable: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (RoleDetailsState) -> Content
    ) {
        self.init(
            roleId: roleId,
            administrationMode: administrationMode,
            editable: editable,
            deletable: deletable,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        RoleDetailsHost(state: thunderState, props: self).id("\(roleId)|\(administrationMode.rawValue)")
    }
}

public extension RoleDetails where Content == EmptyView {
    init(
        roleId: String,
        administrationMode: AdministrationMode = .native,
        editable: Bool = false,
        deletable: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            roleId: roleId,
            administrationMode: administrationMode,
            editable: editable,
            deletable: deletable,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: nil
        )
    }
}

private struct RoleDetailsHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var role: ResourceQuery<Role>
    @StateObject private var deletion: ResourceMutation<String, Void>
    let props: RoleDetails<Content>

    init(state: ThunderIDState, props: RoleDetails<Content>) {
        _role = StateObject(wrappedValue: state.roleQuery(id: props.roleId))
        _deletion = StateObject(
            wrappedValue: state.deleteRoleMutation(administrationMode: props.administrationMode)
        )
        self.props = props
    }

    var body: some View {
        BaseRoleDetails(
            role: role.data,
            isLoading: role.isLoading,
            error: i18n.managementErrorMessage(role.error, fallbackKey: "admin.roles.details.error")
                ?? i18n.managementErrorMessage(deletion.error, fallbackKey: "admin.roles.details.delete.error"),
            isDeleting: deletion.isLoading,
            onDelete: props.deletable ? delete : nil,
            actions: props.actions,
            sections: AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    RolePermissions(
                        roleId: props.roleId,
                        editable: props.editable && role.data != nil,
                        administrationMode: props.administrationMode
                    )
                    RoleAssignments(
                        roleId: props.roleId,
                        editable: props.editable && role.data != nil,
                        administrationMode: props.administrationMode,
                        ouId: role.data?.ouId
                    )
                }
            ),
            renderContent: props.content
        )
        .task { await role.refetch() }
    }

    private func delete() {
        Task {
            if await deletion.mutate(props.roleId) != nil {
                props.onDeleted?()
            }
        }
    }
}
