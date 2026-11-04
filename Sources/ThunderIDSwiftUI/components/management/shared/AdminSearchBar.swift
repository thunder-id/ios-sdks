// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Searches an admin list by one attribute. The server matches the whole value, so the search runs when
/// submitted rather than on every keystroke.
struct AdminSearchBar: View {
    let i18n: ThunderIDI18n
    let identifier: String
    let attributes: [AdminOption]
    let search: AdminSearch?
    let onSearch: (AdminSearch?) -> Void

    @State private var chosenAttribute = ""
    @State private var value = ""

    private var attribute: String {
        chosenAttribute.isEmpty ? (search?.attribute ?? attributes.first?.value ?? "") : chosenAttribute
    }

    private var label: String {
        attributes.first { $0.value == attribute }?.label ?? attribute
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if attributes.count > 1 {
                AdminPicker(
                    label: i18n.resolve("admin.common.search.attribute"),
                    name: "search-attribute",
                    options: attributes,
                    selection: Binding(get: { attribute }, set: { chosenAttribute = $0 })
                )
            }
            HStack(spacing: 8) {
                TextField(
                    i18n.resolve("admin.common.search.placeholder", ["attribute": label.lowercased()]),
                    text: $value
                )
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit(apply)
                .accessibilityLabel(label)
                .accessibilityIdentifier("\(identifier)-search")
                Button(i18n.resolve("admin.common.search.submit"), action: apply)
                    .accessibilityIdentifier("\(identifier)-search-submit")
                if search != nil {
                    Button(i18n.resolve("admin.common.search.clear")) {
                        value = ""
                        onSearch(nil)
                    }
                    .accessibilityIdentifier("\(identifier)-search-clear")
                }
            }
        }
        .onAppear { value = search?.value ?? "" }
    }

    private func apply() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        onSearch(trimmed.isEmpty ? nil : AdminSearch(attribute: attribute, value: trimmed))
    }
}
