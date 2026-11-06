// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Picks an identity of one of several kinds, for adding a group member or assigning a role.
struct IdentityPicker<IdentityType: RawRepresentable & Hashable>: View where IdentityType.RawValue == String {
    let i18n: ThunderIDI18n
    let addLabel: String
    let types: [IdentityType]
    let candidates: [IdentityType: [IdentityCandidate]]
    let excludedIds: Set<String>
    let isSubmitting: Bool
    let onAdd: (String, IdentityType) -> Void

    @State private var chosenType: String = ""
    @State private var identityId: String = ""

    private var type: IdentityType? {
        types.first { $0.rawValue == chosenType } ?? types.first
    }

    private var options: [AdminOption] {
        guard let type else { return [] }
        return (candidates[type] ?? [])
            .filter { !excludedIds.contains($0.id) }
            .map { AdminOption(label: $0.label, value: $0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdminPicker(
                label: i18n.resolve("admin.common.fields.identity_type"),
                name: "identityType",
                options: types.map {
                    AdminOption(label: i18n.resolve("admin.common.identity_types.\($0.rawValue)"), value: $0.rawValue)
                },
                selection: Binding(
                    get: { type?.rawValue ?? "" },
                    set: {
                        chosenType = $0
                        identityId = ""
                    }
                )
            )
            if options.isEmpty {
                Text(i18n.resolve("admin.common.fields.identity_empty"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                AdminPicker(
                    label: i18n.resolve("admin.common.fields.identity"),
                    name: "identity",
                    options: options,
                    placeholder: i18n.resolve("admin.common.fields.identity_placeholder"),
                    selection: $identityId
                )
            }
            HStack {
                Spacer()
                Button(action: submit) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text(addLabel)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(identityId.isEmpty || isSubmitting)
                .accessibilityLabel(addLabel)
                .accessibilityIdentifier("admin-identity-add")
            }
        }
    }

    private func submit() {
        guard let type, !identityId.isEmpty else { return }
        onAdd(identityId, type)
        identityId = ""
    }
}
