// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// The permissions a role grants, grouped by resource server, rendered from the data it is given.
public struct BaseRolePermissions<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let permissions: [RoleResourcePermissions]
    let resourceServerNames: [String: String]
    let isLoading: Bool
    let error: String?
    let title: String?
    let description: String?

    /// - Parameter resourceServerNames: Display names keyed by resource server identifier. A
    ///   resource server without one is shown by its identifier.
    let content: ((RolePermissionsState) -> Content)?

    init(
        permissions: [RoleResourcePermissions],
        resourceServerNames: [String: String] = [:],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        renderContent: ((RolePermissionsState) -> Content)?
    ) {
        self.permissions = permissions
        self.resourceServerNames = resourceServerNames
        self.isLoading = isLoading
        self.error = error
        self.title = title
        self.description = description
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view, from the granted permissions grouped by
    ///   resource server, the loading and error state, and a resource server name lookup.
    public init(
        permissions: [RoleResourcePermissions],
        resourceServerNames: [String: String] = [:],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        @ViewBuilder content: @escaping (RolePermissionsState) -> Content
    ) {
        self.init(
            permissions: permissions,
            resourceServerNames: resourceServerNames,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
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

    private var renderState: RolePermissionsState {
        RolePermissionsState(
            permissions: permissions.filter { !$0.permissions.isEmpty },
            isLoading: isLoading,
            error: error,
            names: resourceServerNames
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        AdminSection(
            identifier: "admin-role-permissions",
            title: title ?? i18n.resolve("admin.roles.permissions.title"),
            description: description
        ) {
            permissionsContent
        }
    }

    @ViewBuilder
    private var permissionsContent: some View {
        let granted = permissions.filter { !$0.permissions.isEmpty }
        if isLoading {
            AdminLoadingRow(label: i18n.resolve("admin.common.loading"))
        } else if let error {
            AdminErrorBanner(message: error)
        } else if granted.isEmpty {
            Text(i18n.resolve("admin.roles.permissions.empty"))
                .foregroundColor(.secondary)
        } else {
            ForEach(granted, id: \.resourceServerId) { entry in
                let name = resourceServerNames[entry.resourceServerId] ?? entry.resourceServerId
                AdminPanel(title: name) {
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

public extension BaseRolePermissions where Content == EmptyView {
    init(
        permissions: [RoleResourcePermissions],
        resourceServerNames: [String: String] = [:],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil
    ) {
        self.init(
            permissions: permissions,
            resourceServerNames: resourceServerNames,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            renderContent: nil
        )
    }
}

/// The permissions a role grants, loaded through the management API.
public struct RolePermissions<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    let roleId: String
    let resourceServerNames: [String: String]
    let title: String?
    let description: String?
    let content: ((RolePermissionsState) -> Content)?

    init(
        roleId: String,
        resourceServerNames: [String: String] = [:],
        title: String? = nil,
        description: String? = nil,
        renderContent: ((RolePermissionsState) -> Content)?
    ) {
        self.roleId = roleId
        self.resourceServerNames = resourceServerNames
        self.title = title
        self.description = description
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view. See ``BaseRolePermissions``.
    public init(
        roleId: String,
        resourceServerNames: [String: String] = [:],
        title: String? = nil,
        description: String? = nil,
        @ViewBuilder content: @escaping (RolePermissionsState) -> Content
    ) {
        self.init(
            roleId: roleId,
            resourceServerNames: resourceServerNames,
            title: title,
            description: description,
            renderContent: content
        )
    }

    public var body: some View {
        let state = thunderState
        AdminQueryReader(state.roleQuery(id: roleId)) { role in
            BaseRolePermissions(
                permissions: role.data?.permissions ?? [],
                resourceServerNames: resourceServerNames,
                isLoading: role.isLoading,
                error: i18n.managementErrorMessage(role.error, fallbackKey: "admin.roles.permissions.error"),
                title: title,
                description: description,
                renderContent: content
            )
        }
        .id(roleId)
    }
}

public extension RolePermissions where Content == EmptyView {
    init(
        roleId: String,
        resourceServerNames: [String: String] = [:],
        title: String? = nil,
        description: String? = nil
    ) {
        self.init(
            roleId: roleId,
            resourceServerNames: resourceServerNames,
            title: title,
            description: description,
            renderContent: nil
        )
    }
}
