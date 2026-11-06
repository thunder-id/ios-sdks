// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// One permission on one resource server: what ``RolePermissions`` adds to or removes from a role.
public struct RolePermission: Hashable {
    public let resourceServerId: String
    public let permission: String

    public init(resourceServerId: String, permission: String) {
        self.resourceServerId = resourceServerId
        self.permission = permission
    }

    /// `permissions` with `permission` granted, keeping the order of what is already there.
    public static func adding(_ permission: RolePermission, to permissions: [RoleResourcePermissions])
        -> [RoleResourcePermissions] {
        var result = permissions
        if let index = result.firstIndex(where: { $0.resourceServerId == permission.resourceServerId }) {
            if !result[index].permissions.contains(permission.permission) {
                result[index].permissions.append(permission.permission)
            }
        } else {
            result.append(
                RoleResourcePermissions(
                    resourceServerId: permission.resourceServerId,
                    permissions: [permission.permission]
                )
            )
        }
        return result
    }

    /// `permissions` without `permission`. A resource server left with no permission is dropped.
    public static func removing(_ permission: RolePermission, from permissions: [RoleResourcePermissions])
        -> [RoleResourcePermissions] {
        permissions.compactMap { entry in
            guard entry.resourceServerId == permission.resourceServerId else { return entry }
            let remaining = entry.permissions.filter { $0 != permission.permission }
            return remaining.isEmpty
                ? nil
                : RoleResourcePermissions(resourceServerId: entry.resourceServerId, permissions: remaining)
        }
    }
}

/// A resource server whose permissions a role can be granted, with those permissions: the ones its
/// actions define.
public struct RolePermissionCandidate: Hashable {
    public let resourceServerId: String
    public let name: String
    public let permissions: [String]

    public init(resourceServerId: String, name: String, permissions: [String]) {
        self.resourceServerId = resourceServerId
        self.name = name
        self.permissions = permissions
    }
}

/// Picks a resource server, then one of its permissions the role does not have yet, and adds it.
struct RolePermissionPicker: View {
    let i18n: ThunderIDI18n
    let candidates: [RolePermissionCandidate]
    let granted: Set<RolePermission>
    let isSubmitting: Bool
    let onAdd: (RolePermission) -> Void

    @State private var chosenServer = ""
    @State private var permission = ""

    private var server: RolePermissionCandidate? {
        candidates.first { $0.resourceServerId == chosenServer } ?? candidates.first
    }

    private var options: [AdminOption] {
        guard let server else { return [] }
        return server.permissions
            .filter { !granted.contains(RolePermission(resourceServerId: server.resourceServerId, permission: $0)) }
            .map { AdminOption(label: $0, value: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdminPicker(
                label: i18n.resolve("admin.roles.permissions.fields.resource_server"),
                name: "resourceServer",
                options: candidates.map { AdminOption(label: $0.name, value: $0.resourceServerId) },
                selection: Binding(
                    get: { server?.resourceServerId ?? "" },
                    set: {
                        chosenServer = $0
                        permission = ""
                    }
                )
            )
            if options.isEmpty {
                Text(i18n.resolve("admin.roles.permissions.fields.permission_empty"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                AdminPicker(
                    label: i18n.resolve("admin.roles.permissions.fields.permission"),
                    name: "permission",
                    options: options,
                    placeholder: i18n.resolve("admin.roles.permissions.fields.permission_placeholder"),
                    selection: $permission
                )
            }
            HStack {
                Spacer()
                Button(action: submit) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text(i18n.resolve("admin.roles.permissions.add"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(permission.isEmpty || isSubmitting)
                .accessibilityLabel(i18n.resolve("admin.roles.permissions.add"))
                .accessibilityIdentifier("admin-role-permissions-add")
            }
        }
    }

    private func submit() {
        guard let server, !permission.isEmpty else { return }
        onAdd(RolePermission(resourceServerId: server.resourceServerId, permission: permission))
        permission = ""
    }
}

/// The permissions granted on one resource server, each with a remove action that asks first.
struct RolePermissionRows: View {
    let i18n: ThunderIDI18n
    let resourceServerId: String
    let permissions: [String]
    let isMutating: Bool
    let onRemove: (RolePermission) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(permissions, id: \.self) { permission in
                HStack {
                    Text(permission)
                        .font(.subheadline)
                        .textSelection(.enabled)
                    Spacer()
                    AdminConfirmButton(
                        i18n: i18n,
                        title: i18n.resolve("admin.common.actions.remove"),
                        confirmText: i18n.resolve(
                            "admin.roles.permissions.remove_confirm",
                            ["permission": permission]
                        ),
                        isLoading: false,
                        identifier: "admin-role-permissions-remove-\(permission)"
                    ) {
                        onRemove(RolePermission(resourceServerId: resourceServerId, permission: permission))
                    }
                    .disabled(isMutating)
                    .accessibilityLabel(
                        i18n.resolve("admin.roles.permissions.remove_label", ["permission": permission])
                    )
                }
            }
        }
    }
}
