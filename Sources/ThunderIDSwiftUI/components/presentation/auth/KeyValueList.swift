// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Displays label and value pairs as a two-column grid, with an optional label above it. Rendered for a
/// `KEY_VALUE_LIST` flow component, e.g. the account-linking prompt's matched attributes.
struct KeyValueList: View {
    let label: String
    let pairs: [KeyValuePair]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
            }
            // Two columns rather than a row each, so every value starts at the same edge however
            // long the labels beside them are.
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 12) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    GridRow {
                        Text(pair.label)
                            .foregroundColor(.secondary)
                        Text(pair.value)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            .cornerRadius(8)
        }
    }
}
