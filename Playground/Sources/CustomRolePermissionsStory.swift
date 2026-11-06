// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID
import ThunderIDSwiftUI

extension ExplorerCatalog {
    static func customRolePermissions(roleId: String) -> ComponentSpec {
        ComponentSpec(
            id: "customRolePermissions",
            name: "RolePermissions → list",
            group: "Custom rendering",
            defaults: ["source": "sample", "roleId": roleId],
            controls: [
                StoryControl(name: "source", kind: .options(["sample", "live"])),
                StoryControl(name: "roleId", kind: .text)
            ],
            stories: [
                Story(id: "sample", name: "Sample", preset: ["source": "sample"]),
                Story(id: "live", name: "Live (edits the role)", preset: ["source": "live"])
            ],
            isTall: true
        ) { values in
            let head = values.isLive
                ? "RolePermissions(roleId: \(quote(values.text("roleId"))), editable: true)"
                : "BaseRolePermissions(permissions: permissions, candidates: candidates, "
                    + "onAdd: { add($0) }, onRemove: { remove($0) })"
            return """
            \(head) { state in
                List {
                    ForEach(state.permissions, id: \\.resourceServerId) { entry in
                        Section(state.resourceServerName(for: entry.resourceServerId)) {
                            ForEach(entry.permissions, id: \\.self) { permission in
                                Text(permission).swipeActions {
                                    if state.onRemove != nil {
                                        // A custom render asks before removing, as the built-in UI does.
                                        Button("Remove", role: .destructive) { pending = permission }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            """
        }
    }
}

/// The permissions state drawn as plain sections, with an add menu and a confirmed removal.
struct CustomRolePermissionsStory: View {
    let values: PropValues
    let onEvent: (String) -> Void
    @State private var permissions = AdminSamples.permissions

    var body: some View {
        if values.isLive {
            if values.text("roleId").isEmpty {
                PreviewHint(text: "Set roleId, or run the Roles check to find one on the server.")
            } else {
                RolePermissions(roleId: values.text("roleId"), editable: true) { PermissionSections(state: $0) }
            }
        } else {
            BaseRolePermissions(
                permissions: permissions,
                resourceServerNames: AdminSamples.resourceServerNames,
                candidates: AdminSamples.permissionCandidates,
                onAdd: { permission in
                    permissions = RolePermission.adding(permission, to: permissions)
                    onEvent("onAdd: \(permission.permission)")
                },
                onRemove: { permission in
                    permissions = RolePermission.removing(permission, from: permissions)
                    onEvent("onRemove: \(permission.permission)")
                },
                content: { PermissionSections(state: $0) }
            )
        }
    }
}

private struct PermissionSections: View {
    let state: RolePermissionsState
    @State private var pending: RolePermission?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.isLoading {
                ProgressView()
            }
            if let error = state.error {
                Text(error).foregroundColor(.red)
            }
            ForEach(state.permissions, id: \.resourceServerId) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.resourceServerName(for: entry.resourceServerId))
                        .font(.system(size: 15, weight: .semibold))
                    ForEach(entry.permissions, id: \.self) { permission in
                        row(RolePermission(resourceServerId: entry.resourceServerId, permission: permission))
                    }
                }
            }
            addMenu
        }
        .confirmationDialog(
            "Remove \(pending?.permission ?? "")?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let pending { state.onRemove?(pending) }
                pending = nil
            }
        }
    }

    private func row(_ permission: RolePermission) -> some View {
        HStack {
            Text(permission.permission).font(.system(size: 14, design: .monospaced))
            Spacer()
            if state.onRemove != nil {
                Button(role: .destructive) { pending = permission } label: { Image(systemName: "minus.circle") }
                    .disabled(state.isMutating)
            }
        }
    }

    @ViewBuilder private var addMenu: some View {
        if let add = state.onAdd, let candidates = state.candidates {
            Menu("Add permission") {
                ForEach(candidates, id: \.resourceServerId) { server in
                    Section(server.name) {
                        ForEach(server.permissions, id: \.self) { permission in
                            Button(permission) {
                                add(RolePermission(resourceServerId: server.resourceServerId, permission: permission))
                            }
                        }
                    }
                }
            }
            .disabled(state.isMutating)
        }
    }
}
