// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The rows of an admin list with its loading, error, empty and pagination states. Rows are
/// selectable when `onSelect` is set. It does not scroll on its own, so it composes into the
/// application's own `List` or `ScrollView`.
struct AdminTable<Row, RowContent: View>: View {
    let identifier: String
    let rows: [Row]
    let rowId: (Row) -> String
    let isLoading: Bool
    let error: String?
    let emptyText: String
    var selectedId: String?
    var onSelect: ((Row) -> Void)?
    var pagination: AdminPagination?
    @ViewBuilder var row: (Row) -> RowContent
    let i18n: ThunderIDI18n

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error {
                AdminErrorBanner(message: error)
            } else if isLoading && rows.isEmpty {
                AdminLoadingRow(label: i18n.resolve("admin.common.loading"))
            } else if rows.isEmpty {
                Text(emptyText)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("\(identifier)-empty")
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Divider() }
                    rowView(item)
                }
            }
            if let pagination, error == nil, !rows.isEmpty {
                Divider()
                pagination.padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ item: Row) -> some View {
        let id = rowId(item)
        let isSelected = selectedId == id
        if let onSelect {
            Button { onSelect(item) } label: {
                row(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("\(identifier)-row-\(id)")
        } else {
            row(item)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("\(identifier)-row-\(id)")
        }
    }
}

/// The two-line cell most admin rows use: a name, then secondary details.
struct AdminRowLabel: View {
    let title: String
    let details: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundColor(.primary)
            let detailText = details.filter { !$0.isEmpty }.joined(separator: " · ")
            if !detailText.isEmpty {
                Text(detailText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// A generated initials avatar for a managed identity.
struct AdminAvatar: View {
    let name: String
    let size: CGFloat

    var body: some View {
        AvatarView(
            spec: AvatarSpec(
                shape: .circle,
                variant: .twoLetter,
                content: deriveAvatarContent(variant: .twoLetter, seedText: name),
                colors: name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
            )
        )
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
