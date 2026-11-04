// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// The built-in UI of ``BaseOrganizationUnitDetails`` once the unit is there.
struct OrganizationUnitDetailsView: View {
    let i18n: ThunderIDI18n
    let unit: OrganizationUnit
    let state: OrganizationUnitDetailsState
    let actions: AnyView?

    @State private var isEditing = false
    @State private var name = ""
    @State private var handle = ""
    @State private var unitDescription = ""

    private let prefix = "admin.organization_units"

    var body: some View {
        AdminSection(
            identifier: "admin-organization-unit-details",
            title: unit.name,
            description: unit.description,
            actions: { headerActions },
            content: {
                if let error = state.error {
                    AdminErrorBanner(message: error)
                }
                if isEditing {
                    editForm
                } else {
                    overview
                }
                childrenPanel
                AdminPanel(title: i18n.resolve("\(prefix).details.users")) {
                    AdminChipList(
                        label: i18n.resolve("\(prefix).details.users"),
                        emptyText: i18n.resolve("\(prefix).details.no_users"),
                        items: state.users.map { (id: $0.id, label: $0.display ?? $0.id) }
                    )
                }
                AdminPanel(title: i18n.resolve("\(prefix).details.groups")) {
                    AdminChipList(
                        label: i18n.resolve("\(prefix).details.groups"),
                        emptyText: i18n.resolve("\(prefix).details.no_groups"),
                        items: state.groups.map { (id: $0.id, label: $0.name) }
                    )
                }
                AdminPanel(title: i18n.resolve("\(prefix).details.roles")) {
                    AdminChipList(
                        label: i18n.resolve("\(prefix).details.roles"),
                        emptyText: i18n.resolve("\(prefix).details.no_roles"),
                        items: state.roles.map { (id: $0.id, label: $0.name) }
                    )
                }
            }
        )
    }

    private var overview: some View {
        AdminPanel(title: i18n.resolve("\(prefix).details.overview")) {
            AdminDetailList(items: [
                (i18n.resolve("\(prefix).fields.name"), unit.name),
                (i18n.resolve("\(prefix).fields.handle"), unit.handle),
                (i18n.resolve("\(prefix).fields.description"), unit.description ?? ""),
                (i18n.resolve("\(prefix).fields.parent"), unit.parent ?? i18n.resolve("\(prefix).fields.no_parent"))
            ])
        }
    }

    private var childrenPanel: some View {
        AdminPanel(title: i18n.resolve("\(prefix).details.children")) {
            AdminTable(
                identifier: "admin-organization-unit-children",
                rows: state.children,
                rowId: \.id,
                isLoading: false,
                error: nil,
                emptyText: i18n.resolve("\(prefix).details.no_children"),
                onSelect: state.onSelectChild,
                row: { child in AdminRowLabel(title: child.name, details: [child.handle]) },
                i18n: i18n
            )
        }
    }

    private var editForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdminTextField(label: i18n.resolve("\(prefix).fields.name"), name: "name", isRequired: true, text: $name)
            AdminTextField(
                label: i18n.resolve("\(prefix).fields.handle"),
                name: "handle",
                isRequired: true,
                text: $handle
            )
            AdminTextField(
                label: i18n.resolve("\(prefix).fields.description"),
                name: "description",
                text: $unitDescription
            )
            AdminFormActions(
                i18n: i18n,
                submitLabel: i18n.resolve("\(prefix).details.edit.save"),
                isSubmitting: state.isUpdating,
                canSubmit: canSave,
                onCancel: { isEditing = false },
                onSubmit: save
            )
        }
    }

    private var trimmedHandle: String { handle.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool { AdminHandle.optional(name) != nil && AdminHandle.isValid(trimmedHandle) }

    private func save() {
        guard canSave, let unitName = AdminHandle.optional(name) else { return }
        var fields = unit.fields
        fields.description = AdminHandle.optional(unitDescription)
        state.onUpdate?(
            OrganizationUnitRequest(handle: trimmedHandle, name: unitName, parent: unit.parent, fields: fields)
        )
        isEditing = false
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            actions
            if state.onUpdate != nil, !isEditing {
                Button(i18n.resolve("\(prefix).details.edit.action")) {
                    name = unit.name
                    handle = unit.handle
                    unitDescription = unit.description ?? ""
                    isEditing = true
                }
                .accessibilityIdentifier("admin-organization-unit-details-edit")
            }
            if let onDelete = state.onDelete {
                AdminConfirmButton(
                    i18n: i18n,
                    title: i18n.resolve("\(prefix).details.delete.action"),
                    confirmText: i18n.resolve("\(prefix).details.delete.confirm", ["name": unit.name]),
                    isLoading: state.isDeleting,
                    identifier: "admin-organization-unit-details-delete",
                    onConfirm: onDelete
                )
            }
        }
    }
}
