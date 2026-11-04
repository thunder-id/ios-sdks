// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// A labelled option for an admin picker.
public struct AdminOption: Hashable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// The frame every admin component renders in: a heading, an optional description and actions,
/// then the content. It is a section, not a screen: it renders no navigation of its own.
struct AdminSection<Content: View, Actions: View>: View {
    let identifier: String
    var title: String?
    var description: String?
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || description != nil || Actions.self != EmptyView.self {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title {
                            Text(title)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                        }
                        if let description, !description.isEmpty {
                            Text(description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    actions()
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

extension AdminSection where Actions == EmptyView {
    init(
        identifier: String,
        title: String? = nil,
        description: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            identifier: identifier,
            title: title,
            description: description,
            actions: { EmptyView() },
            content: content
        )
    }
}

/// A translated error, announced to assistive technologies.
struct AdminErrorBanner: View {
    let message: String

    var body: some View {
        FlowErrorBanner(message: message)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("admin-error")
    }
}

/// A loading indicator with a translated label.
struct AdminLoadingRow: View {
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(label).foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("admin-loading")
    }
}

/// A titled card grouping related details.
struct AdminPanel<Content: View>: View {
    let title: String
    var actions: AnyView?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                actions
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
    }
}

/// Label and value pairs.
struct AdminDetailList: View {
    let items: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline) {
                    Text(item.label).foregroundColor(.secondary)
                    Spacer(minLength: 8)
                    Text(item.value)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A wrapping list of labels, or `emptyText` when there are none.
struct AdminChipList: View {
    let label: String
    let emptyText: String
    let items: [(id: String, label: String)]

    var body: some View {
        if items.isEmpty {
            Text(emptyText)
                .font(.subheadline)
                .foregroundColor(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)], alignment: .leading) {
                ForEach(items, id: \.id) { item in
                    Text(item.label)
                        .font(.footnote)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityValue(items.map(\.label).joined(separator: ", "))
        }
    }
}

/// Previous and next controls with the current range.
struct AdminPagination: View {
    let i18n: ThunderIDI18n
    let limit: Int
    let offset: Int
    let total: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack {
            Text(range)
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
            Button(i18n.resolve("admin.common.pagination.previous")) { onChange(max(0, offset - limit)) }
                .disabled(offset == 0)
                .accessibilityIdentifier("admin-pagination-previous")
            Button(i18n.resolve("admin.common.pagination.next")) { onChange(offset + limit) }
                .disabled(offset + limit >= total)
                .accessibilityIdentifier("admin-pagination-next")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(i18n.resolve("admin.common.pagination.label"))
    }

    var range: String {
        let start = total == 0 ? 0 : offset + 1
        let end = min(offset + limit, total)
        return i18n.resolve(
            "admin.common.pagination.range",
            ["start": String(start), "end": String(end), "total": String(total)]
        )
    }
}

/// A destructive action that asks for confirmation before it runs.
struct AdminConfirmButton: View {
    let i18n: ThunderIDI18n
    let title: String
    let confirmText: String
    let isLoading: Bool
    let identifier: String
    let onConfirm: () -> Void
    @State private var isConfirming = false

    var body: some View {
        Button(role: .destructive) { isConfirming = true } label: {
            if isLoading {
                ProgressView()
            } else {
                Text(title)
            }
        }
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
        .alert(confirmText, isPresented: $isConfirming) {
            Button(i18n.resolve("admin.common.actions.cancel"), role: .cancel) {}
            Button(i18n.resolve("admin.common.actions.confirm"), role: .destructive, action: onConfirm)
                .accessibilityIdentifier("\(identifier)-confirm")
        }
    }
}

/// A labelled text input.
struct AdminTextField: View {
    let label: String
    let name: String
    var isSecure = false
    var isRequired = false
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isRequired ? "\(label) *" : label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Group {
                if isSecure {
                    SecureField(label, text: $text)
                } else {
                    TextField(label, text: $text)
                        .autocorrectionDisabled()
                        .adminNoAutocapitalization()
                }
            }
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(label)
            .accessibilityIdentifier("admin-field-\(name)")
        }
    }
}

/// A labelled single-choice menu.
struct AdminPicker: View {
    let label: String
    let name: String
    let options: [AdminOption]
    var placeholder: String?
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Picker(label, selection: $selection) {
                if let placeholder {
                    Text(placeholder).tag("")
                }
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(label)
            .accessibilityIdentifier("admin-field-\(name)")
        }
    }
}

/// The submit and optional cancel buttons of an admin form.
struct AdminFormActions: View {
    let i18n: ThunderIDI18n
    let submitLabel: String
    let isSubmitting: Bool
    let canSubmit: Bool
    let onCancel: (() -> Void)?
    let onSubmit: () -> Void

    var body: some View {
        HStack {
            Spacer()
            if let onCancel {
                Button(i18n.resolve("admin.common.actions.cancel"), action: onCancel)
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("admin-cancel")
            }
            Button(action: onSubmit) {
                if isSubmitting {
                    ProgressView()
                } else {
                    Text(submitLabel)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit || isSubmitting)
            .accessibilityLabel(submitLabel)
            .accessibilityIdentifier("admin-submit")
        }
    }
}
