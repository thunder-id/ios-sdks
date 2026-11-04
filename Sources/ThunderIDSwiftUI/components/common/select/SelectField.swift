// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// The i18n keys a ``SelectField`` reads for its own wording.
struct SelectMessages {
    let placeholder: String
    let empty: String

    static let standard = SelectMessages(placeholder: "select.placeholder", empty: "select.empty")
}

/// A single-choice field: a trigger that opens a sheet listing `options`.
///
/// It only shows the options it is given and reports what the user does, so it knows nothing about
/// fetching. To list options a page at a time, pass `onLoadMore` and keep the list up to date, for
/// example with ``InfiniteOptionsState``.
///
/// - The placeholder row clears the choice unless the field is `required`.
/// - A "Load more" row follows the last option while `onLoadMore` is set. Choosing it asks for more
///   options and never changes the selection. It is disabled while `loading` and stays available after a
///   failed load, so choosing it again repeats the request.
/// - A `value` that is not among `options` is labelled by the option last picked here, then by
///   `selectedOption`, then by the value itself.
public struct SelectField: View {
    @EnvironmentObject private var i18n: ThunderIDI18n

    private let name: String
    @Binding private var value: String
    private let options: [SelectOption]
    private let label: String
    private let placeholder: String?
    private let error: String?
    private let isRequired: Bool
    private let isDisabled: Bool
    private let loading: Bool
    private let onLoadMore: (() -> Void)?
    private let emptyText: String?
    private let selectedOption: SelectOption?
    private let messages: SelectMessages

    @State private var isPresented = false
    @State private var pickedOption: SelectOption?

    /// - Parameters:
    ///   - name: Identifies the field for accessibility and tests (`thunderid-field-<name>`).
    ///   - value: The submitted value of the chosen option, or an empty string.
    ///   - options: The options to list.
    ///   - label: The field's label.
    ///   - placeholder: Text of the row that clears the choice, and of the trigger while nothing is chosen.
    ///   - error: A validation message shown below the field.
    ///   - required: Whether a choice is mandatory. A required field cannot be cleared.
    ///   - disabled: Whether the field ignores taps.
    ///   - loading: Whether options are being fetched.
    ///   - onLoadMore: Called when the "Load more" row is chosen. Pass it only while more options may exist.
    ///   - emptyText: Shown when there are no options, nothing is loading and there is nothing more to load.
    ///   - selectedOption: Labels `value` while it is not among `options`, such as a value loaded from saved data.
    public init(
        name: String,
        value: Binding<String>,
        options: [SelectOption],
        label: String,
        placeholder: String? = nil,
        error: String? = nil,
        required: Bool = false,
        disabled: Bool = false,
        loading: Bool = false,
        onLoadMore: (() -> Void)? = nil,
        emptyText: String? = nil,
        selectedOption: SelectOption? = nil
    ) {
        self.init(
            name: name,
            value: value,
            options: options,
            label: label,
            placeholder: placeholder,
            error: error,
            required: required,
            disabled: disabled,
            loading: loading,
            onLoadMore: onLoadMore,
            emptyText: emptyText,
            selectedOption: selectedOption,
            messages: .standard
        )
    }

    init(
        name: String,
        value: Binding<String>,
        options: [SelectOption],
        label: String,
        placeholder: String? = nil,
        error: String? = nil,
        required: Bool = false,
        disabled: Bool = false,
        loading: Bool = false,
        onLoadMore: (() -> Void)? = nil,
        emptyText: String? = nil,
        selectedOption: SelectOption? = nil,
        messages: SelectMessages
    ) {
        self.name = name
        _value = value
        self.options = options
        self.label = label
        self.placeholder = placeholder
        self.error = error
        isRequired = required
        isDisabled = disabled
        self.loading = loading
        self.onLoadMore = onLoadMore
        self.emptyText = emptyText
        self.selectedOption = selectedOption
        self.messages = messages
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                Text(isRequired ? "\(label) *" : label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
            Button {
                isPresented = true
            } label: {
                HStack {
                    Text(triggerLabel ?? placeholderText)
                        .foregroundColor(triggerLabel == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Color.fieldBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fieldBorder, lineWidth: 1))
            }
            .disabled(isDisabled)
            .accessibilityLabel(accessibleLabel)
            .accessibilityValue(triggerLabel ?? placeholderText)
            .accessibilityIdentifier("thunderid-field-\(name)")
            .sheet(isPresented: $isPresented) {
                SelectListView(
                    options: options,
                    value: value,
                    placeholderText: placeholderText,
                    clearable: !isRequired,
                    outsideOption: outsideOption,
                    loading: loading,
                    onLoadMore: onLoadMore,
                    emptyText: emptyText ?? i18n.resolve(messages.empty),
                    i18n: i18n,
                    name: name
                ) { option in
                    pickedOption = option
                    value = option?.value ?? ""
                    isPresented = false
                }
            }
            if let error {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
    }

    private var placeholderText: String {
        placeholder ?? i18n.resolve(messages.placeholder)
    }

    private var accessibleLabel: String {
        guard isRequired else { return label }
        return "\(label), \(i18n.resolve("select.required"))"
    }

    /// The option that labels `value` while it is not among the loaded options.
    private var outsideOption: SelectOption? {
        guard !options.contains(where: { $0.value == value }) else { return nil }
        return resolveSelectOption(for: value, in: options, picked: pickedOption, selectedOption: selectedOption)
    }

    /// The label of the chosen option, or `nil` when nothing is chosen.
    private var triggerLabel: String? {
        guard !value.isEmpty else { return nil }
        return resolveSelectOption(for: value, in: options, picked: pickedOption, selectedOption: selectedOption)?.label
            ?? value
    }
}

private struct SelectListView: View {
    let options: [SelectOption]
    let value: String
    let placeholderText: String
    let clearable: Bool
    let outsideOption: SelectOption?
    let loading: Bool
    let onLoadMore: (() -> Void)?
    let emptyText: String
    let i18n: ThunderIDI18n
    let name: String
    let onSelect: (SelectOption?) -> Void

    private var layout: SelectListLayout {
        SelectListLayout(optionCount: options.count, loading: loading, canLoadMore: onLoadMore != nil)
    }

    var body: some View {
        NavigationStack {
            List {
                Button { onSelect(nil) } label: {
                    Text(placeholderText).foregroundColor(.secondary)
                }
                .disabled(!clearable)
                .accessibilityAddTraits(value.isEmpty ? .isSelected : [])
                .accessibilityIdentifier("thunderid-option-clear")

                if let outsideOption {
                    optionRow(outsideOption)
                }
                ForEach(options) { option in
                    optionRow(option)
                }
                switch layout.status {
                case .loading:
                    statusRow(i18n.resolve("select.loading"), showsProgress: true)
                case .empty:
                    Text(emptyText).foregroundColor(.secondary)
                case .none:
                    EmptyView()
                }
                if layout.showsLoadMore {
                    Button { onLoadMore?() } label: {
                        if loading {
                            statusRow(i18n.resolve("select.loadingMore"), showsProgress: true)
                        } else {
                            Text(i18n.resolve("select.loadMore"))
                        }
                    }
                    .disabled(loading)
                    .accessibilityIdentifier("thunderid-load-more-\(name)")
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func optionRow(_ option: SelectOption) -> some View {
        Button {
            guard !option.disabled else { return }
            onSelect(option)
        } label: {
            HStack {
                Text(option.label).foregroundColor(option.disabled ? .secondary : .primary)
                Spacer()
                if option.value == value {
                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                }
            }
        }
        .disabled(option.disabled)
        .accessibilityAddTraits(option.value == value ? .isSelected : [])
        .accessibilityIdentifier("thunderid-option-\(option.value)")
    }

    private func statusRow(_ text: String, showsProgress: Bool) -> some View {
        HStack(spacing: 12) {
            Spacer()
            if showsProgress { ProgressView() }
            Text(text).foregroundColor(.secondary)
            Spacer()
        }
    }
}

private extension Color {
    static var fieldBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var fieldBorder: Color {
        #if canImport(UIKit)
        Color(uiColor: .separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }
}
