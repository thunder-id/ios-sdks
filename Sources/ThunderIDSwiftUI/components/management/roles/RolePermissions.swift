// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// The permissions a role grants, grouped by resource server, rendered from the data it is given.
/// Adding is offered when both `onAdd` and `candidates` are set, removing when `onRemove` is set; a
/// removal asks for confirmation first.
public struct BaseRolePermissions<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let permissions: [RoleResourcePermissions]
    let resourceServerNames: [String: String]
    let candidates: [RolePermissionCandidate]?
    let isLoading: Bool
    let error: String?
    let isMutating: Bool
    let title: String?
    let description: String?
    let onAdd: ((RolePermission) -> Void)?
    let onRemove: ((RolePermission) -> Void)?
    let content: ((RolePermissionsState) -> Content)?

    init(
        permissions: [RoleResourcePermissions],
        resourceServerNames: [String: String] = [:],
        candidates: [RolePermissionCandidate]? = nil,
        isLoading: Bool = false,
        error: String? = nil,
        isMutating: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onAdd: ((RolePermission) -> Void)? = nil,
        onRemove: ((RolePermission) -> Void)? = nil,
        renderContent: ((RolePermissionsState) -> Content)?
    ) {
        self.permissions = permissions
        self.resourceServerNames = resourceServerNames
        self.candidates = candidates
        self.isLoading = isLoading
        self.error = error
        self.isMutating = isMutating
        self.title = title
        self.description = description
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.content = renderContent
    }

    /// - Parameters:
    ///   - resourceServerNames: Display names keyed by resource server identifier. A resource server
    ///     without one is named from `candidates`, or shown by its identifier.
    ///   - candidates: The resource servers whose permissions can be granted, each with its permissions.
    ///   - onAdd: Grants a permission. Adding is offered only when `candidates` is set too.
    ///   - onRemove: Takes a permission away. The built-in UI asks for confirmation first.
    ///   - content: Renders custom UI in place of the default view, from the granted permissions grouped
    ///     by resource server, the loading and error state, a resource server name lookup, and the add
    ///     and remove actions when they are allowed.
    public init(
        permissions: [RoleResourcePermissions],
        resourceServerNames: [String: String] = [:],
        candidates: [RolePermissionCandidate]? = nil,
        isLoading: Bool = false,
        error: String? = nil,
        isMutating: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onAdd: ((RolePermission) -> Void)? = nil,
        onRemove: ((RolePermission) -> Void)? = nil,
        @ViewBuilder content: @escaping (RolePermissionsState) -> Content
    ) {
        self.init(
            permissions: permissions,
            resourceServerNames: resourceServerNames,
            candidates: candidates,
            isLoading: isLoading,
            error: error,
            isMutating: isMutating,
            title: title,
            description: description,
            onAdd: onAdd,
            onRemove: onRemove,
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

    private var granted: [RoleResourcePermissions] {
        permissions.filter { !$0.permissions.isEmpty }
    }

    private var names: [String: String] {
        var names: [String: String] = [:]
        for candidate in candidates ?? [] {
            names[candidate.resourceServerId] = candidate.name
        }
        return names.merging(resourceServerNames) { _, given in given }
    }

    private var renderState: RolePermissionsState {
        RolePermissionsState(
            permissions: granted,
            isLoading: isLoading,
            error: error,
            names: names,
            candidates: onAdd == nil ? nil : candidates,
            isMutating: isMutating,
            onAdd: candidates == nil ? nil : onAdd,
            onRemove: onRemove
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        AdminSection(
            identifier: "admin-role-permissions",
            title: title ?? i18n.resolve("admin.roles.permissions.title"),
            description: description
        ) {
            if let onAdd, let candidates {
                RolePermissionPicker(
                    i18n: i18n,
                    candidates: candidates,
                    granted: Set(granted.flatMap { entry in
                        entry.permissions.map {
                            RolePermission(resourceServerId: entry.resourceServerId, permission: $0)
                        }
                    }),
                    isSubmitting: isMutating,
                    onAdd: onAdd
                )
            }
            permissionsContent
        }
    }

    @ViewBuilder
    private var permissionsContent: some View {
        let names = names
        if isLoading {
            AdminLoadingRow(label: i18n.resolve("admin.common.loading"))
        } else if let error {
            AdminErrorBanner(message: error)
        } else if granted.isEmpty {
            Text(i18n.resolve("admin.roles.permissions.empty"))
                .foregroundColor(.secondary)
        } else {
            ForEach(granted, id: \.resourceServerId) { entry in
                let name = names[entry.resourceServerId] ?? entry.resourceServerId
                AdminPanel(title: name) {
                    if let onRemove {
                        RolePermissionRows(
                            i18n: i18n,
                            resourceServerId: entry.resourceServerId,
                            permissions: entry.permissions,
                            isMutating: isMutating,
                            onRemove: onRemove
                        )
                    } else {
                        AdminChipList(
                            label: name,
                            emptyText: i18n.resolve("admin.roles.permissions.empty"),
                            items: entry.permissions.map { ($0, $0) }
                        )
                    }
                }
            }
        }
    }
}

public extension BaseRolePermissions where Content == EmptyView {
    init(
        permissions: [RoleResourcePermissions],
        resourceServerNames: [String: String] = [:],
        candidates: [RolePermissionCandidate]? = nil,
        isLoading: Bool = false,
        error: String? = nil,
        isMutating: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onAdd: ((RolePermission) -> Void)? = nil,
        onRemove: ((RolePermission) -> Void)? = nil
    ) {
        self.init(
            permissions: permissions,
            resourceServerNames: resourceServerNames,
            candidates: candidates,
            isLoading: isLoading,
            error: error,
            isMutating: isMutating,
            title: title,
            description: description,
            onAdd: onAdd,
            onRemove: onRemove,
            renderContent: nil
        )
    }
}

/// The permissions a role grants, loaded through the management API. Set `editable` to let the
/// signed-in user add permissions, picked from the resource servers and their actions, and remove
/// them; it is off by default, and a removal asks for confirmation first. Changes are saved through
/// `roles.update`. `administrationMode` chooses how a removal is saved: `.flow` runs the permission
/// removal flow the server configures, which revokes the scopes the permission granted first. It
/// defaults to `.native`.
public struct RolePermissions<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let roleId: String
    let editable: Bool
    let administrationMode: AdministrationMode
    let resourceServerNames: [String: String]
    let title: String?
    let description: String?
    let content: ((RolePermissionsState) -> Content)?

    init(
        roleId: String,
        editable: Bool = false,
        administrationMode: AdministrationMode = .native,
        resourceServerNames: [String: String] = [:],
        title: String? = nil,
        description: String? = nil,
        renderContent: ((RolePermissionsState) -> Content)?
    ) {
        self.roleId = roleId
        self.editable = editable
        self.administrationMode = administrationMode
        self.resourceServerNames = resourceServerNames
        self.title = title
        self.description = description
        self.content = renderContent
    }

    /// - Parameters:
    ///   - administrationMode: How a removed permission is saved. See ``AdministrationMode``.
    ///   - content: Renders custom UI in place of the default view. See ``BaseRolePermissions``.
    public init(
        roleId: String,
        editable: Bool = false,
        administrationMode: AdministrationMode = .native,
        resourceServerNames: [String: String] = [:],
        title: String? = nil,
        description: String? = nil,
        @ViewBuilder content: @escaping (RolePermissionsState) -> Content
    ) {
        self.init(
            roleId: roleId,
            editable: editable,
            administrationMode: administrationMode,
            resourceServerNames: resourceServerNames,
            title: title,
            description: description,
            renderContent: content
        )
    }

    public var body: some View {
        RolePermissionsHost(state: thunderState, props: self)
            .id("\(roleId)|\(editable)|\(administrationMode.rawValue)")
    }
}

public extension RolePermissions where Content == EmptyView {
    init(
        roleId: String,
        editable: Bool = false,
        administrationMode: AdministrationMode = .native,
        resourceServerNames: [String: String] = [:],
        title: String? = nil,
        description: String? = nil
    ) {
        self.init(
            roleId: roleId,
            editable: editable,
            administrationMode: administrationMode,
            resourceServerNames: resourceServerNames,
            title: title,
            description: description,
            renderContent: nil
        )
    }
}

private struct RolePermissionsHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var role: ResourceQuery<Role>
    @StateObject private var candidates: ResourceQuery<[RolePermissionCandidate]>
    @StateObject private var update: ResourceMutation<(id: String, request: UpdateRoleRequest), Role>
    let props: RolePermissions<Content>

    init(state: ThunderIDState, props: RolePermissions<Content>) {
        _role = StateObject(wrappedValue: state.roleQuery(id: props.roleId))
        _candidates = StateObject(wrappedValue: state.rolePermissionCandidatesQuery())
        _update = StateObject(
            wrappedValue: state.updateRoleMutation(administrationMode: props.administrationMode)
        )
        self.props = props
    }

    private var canEdit: Bool {
        props.editable && role.data != nil && role.data?.isReadOnly != true
    }

    private var optionsError: String? {
        guard canEdit else { return nil }
        return i18n.managementErrorMessage(candidates.error, fallbackKey: "admin.roles.permissions.options_error")
    }

    var body: some View {
        BaseRolePermissions(
            permissions: role.data?.permissions ?? [],
            resourceServerNames: props.resourceServerNames,
            candidates: canEdit ? (candidates.data ?? []) : nil,
            isLoading: role.isLoading,
            error: i18n.managementErrorMessage(role.error, fallbackKey: "admin.roles.permissions.error")
                ?? i18n.managementErrorMessage(update.error, fallbackKey: "admin.roles.permissions.update_error")
                ?? optionsError,
            isMutating: update.isLoading,
            title: props.title,
            description: props.description,
            onAdd: canEdit ? add : nil,
            onRemove: canEdit ? remove : nil,
            renderContent: props.content
        )
        .task {
            await role.refetch()
            guard props.editable else { return }
            await candidates.refetch()
        }
    }

    private func add(_ permission: RolePermission) {
        save { RolePermission.adding(permission, to: $0) }
    }

    private func remove(_ permission: RolePermission) {
        save { RolePermission.removing(permission, from: $0) }
    }

    private func save(_ change: ([RoleResourcePermissions]) -> [RoleResourcePermissions]) {
        guard let current = role.data else { return }
        let request = UpdateRoleRequest(
            name: current.name,
            ouId: current.ouId,
            description: current.description,
            permissions: change(current.permissions)
        )
        Task { await update.mutate((id: current.id, request: request)) }
    }
}
