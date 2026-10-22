// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// An identity related to a group or a role.
struct AdminRelatedIdentity<IdentityType: RawRepresentable & Hashable> where IdentityType.RawValue == String {
    let id: String
    let type: IdentityType
    let display: String?

    var name: String { display ?? id }
}

/// The identities related to a group or a role, with an optional picker to add more and an
/// optional remove action per row. Shared by ``BaseGroupMembers`` and ``BaseRoleAssignments``.
struct AdminIdentityTable<IdentityType: RawRepresentable & Hashable>: View where IdentityType.RawValue == String {
    let i18n: ThunderIDI18n
    let identifier: String
    let title: String
    let description: String?
    let rows: [AdminRelatedIdentity<IdentityType>]
    let emptyText: String
    let addLabel: String
    let removeLabelKey: String
    let typeOrder: [IdentityType]
    let candidates: [IdentityType: [IdentityCandidate]]?
    let isLoading: Bool
    let error: String?
    let isMutating: Bool
    let onAdd: ((String, IdentityType) -> Void)?
    let onRemove: ((AdminRelatedIdentity<IdentityType>) -> Void)?
    /// Controls shown above the picker and table, such as a filter.
    var toolbar: AnyView?

    var body: some View {
        AdminSection(identifier: identifier, title: title, description: description) {
            if let toolbar {
                toolbar
            }
            if let onAdd, let candidates {
                IdentityPicker(
                    i18n: i18n,
                    addLabel: addLabel,
                    types: typeOrder.filter { candidates[$0] != nil },
                    candidates: candidates,
                    excludedIds: Set(rows.map(\.id)),
                    isSubmitting: isMutating,
                    onAdd: onAdd
                )
            }
            AdminTable(
                identifier: identifier,
                rows: rows,
                rowId: { "\($0.type.rawValue):\($0.id)" },
                isLoading: isLoading,
                error: error,
                emptyText: emptyText,
                row: { identity in
                    HStack {
                        AdminRowLabel(
                            title: identity.name,
                            details: [i18n.resolve("admin.common.identity_types.\(identity.type.rawValue)")]
                        )
                        if let onRemove {
                            Spacer()
                            Button(i18n.resolve("admin.common.actions.remove"), role: .destructive) {
                                onRemove(identity)
                            }
                            .disabled(isMutating)
                            .accessibilityLabel(i18n.resolve(removeLabelKey, ["name": identity.name]))
                            .accessibilityIdentifier("\(identifier)-remove-\(identity.id)")
                        }
                    }
                },
                i18n: i18n
            )
        }
    }
}
