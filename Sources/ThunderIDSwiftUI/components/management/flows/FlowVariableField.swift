// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// One variable as the delegated admin sees it, in a card: its label and description, whether it is
/// customized or follows the default, the input its type calls for, and what the default is. A variable the
/// unit may not set is shown as set by its owner. The label and description come from the flow and are not
/// translated again.
struct FlowVariableField: View {
    let i18n: ThunderIDI18n
    let definition: FlowVariableDefinition
    let rule: ResolvedFlowVariableRule
    let options: [FlowVariableOption]
    let value: FlowVariableValue?
    let error: String?
    let disabled: Bool
    let ouName: String
    let ownerName: String?
    let onCreateConnection: (() -> Void)?
    let onChange: (FlowVariableValue) -> Void

    private var identifier: String { definition.identifier }
    private var label: String { definition.label ?? definition.identifier }
    private var isDefault: Bool { value == rule.defaultValue }
    private var isSelect: Bool { definition.type == .select || definition.type == .connectionSelect }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if rule.editable {
                control
                hints
            } else {
                locked
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(rule.editable ? 0.04 : 0.02))
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("admin-flow-variable-\(identifier)")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.weight(.semibold))
                if let description = definition.description, !description.isEmpty {
                    Text(description)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
            if rule.editable && !isDefault {
                Text(i18n.resolve("admin.flowVariables.status.customized"))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .accessibilityIdentifier("admin-flow-variable-\(identifier)-customized")
            }
        }
    }

    @ViewBuilder private var control: some View {
        switch definition.type {
        case .booleanInput:
            toggle
        case .select, .connectionSelect:
            picker
        default:
            textField
        }
    }

    private var toggle: some View {
        Toggle(label, isOn: Binding(get: { value == .bool(true) }, set: { onChange(.bool($0)) }))
            .labelsHidden()
            .disabled(disabled || !rule.editable)
            .accessibilityLabel(label)
            .accessibilityIdentifier("admin-field-\(identifier)")
    }

    @ViewBuilder private var picker: some View {
        if options.isEmpty {
            Text(i18n.resolve("admin.flowVariables.no_options"))
                .foregroundColor(.secondary)
                .accessibilityIdentifier("admin-field-\(identifier)")
        } else {
            Picker(label, selection: Binding(get: { selection }, set: choose)) {
                Text(selectPlaceholder).tag("")
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(disabled)
            .accessibilityLabel(label)
            .accessibilityIdentifier("admin-field-\(identifier)")
        }
    }

    private var selection: String {
        guard let value, !isDefault else { return "" }
        return value.text
    }

    /// The first entry, the default, clears the choice.
    private func choose(_ raw: String) {
        if raw.isEmpty, let defaultValue = rule.defaultValue {
            onChange(defaultValue)
        } else {
            onChange(definition.options?.first { $0.text == raw } ?? .string(raw))
        }
    }

    private var selectPlaceholder: String {
        guard let defaultValue = rule.defaultValue, defaultValue != .string("") else {
            return i18n.resolve("admin.flowVariables.select_placeholder")
        }
        return i18n.resolve("admin.flowVariables.use_default", ["default": display(defaultValue)])
    }

    private var textField: some View {
        let placeholder = rule.defaultValue.flatMap { $0 == .string("") ? nil : display($0) }
            ?? i18n.resolve("admin.flowVariables.enter_value")
        return TextField(placeholder, text: Binding(get: { value?.text ?? "" }, set: type))
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .adminNoAutocapitalization()
            .flowVariableKeyboard(definition.type)
            .disabled(disabled)
            .accessibilityLabel(label)
            .accessibilityIdentifier("admin-field-\(identifier)")
    }

    /// A number is kept as typed until it reads back the same, so a value such as `1.` can still be completed.
    private func type(_ raw: String) {
        if definition.type == .numberInput, let number = Double(raw), FlowVariableValue.number(number).text == raw {
            onChange(.number(number))
        } else {
            onChange(.string(raw))
        }
    }

    @ViewBuilder private var hints: some View {
        if definition.type == .connectionSelect {
            HStack(spacing: 4) {
                Text(i18n.resolve("admin.flowVariables.connections_hint", ["ou": ouName]))
                if let onCreateConnection {
                    Button(i18n.resolve("admin.flowVariables.create_connection"), action: onCreateConnection)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("admin-flow-variable-\(identifier)-create-connection")
                }
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }
        if !isDefault, let defaultValue = rule.defaultValue {
            Text(i18n.resolve("admin.flowVariables.default_hint", ["default": display(defaultValue)]))
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        if let error {
            Text(error)
                .font(.footnote)
                .foregroundColor(.red)
                .accessibilityIdentifier("admin-flow-variable-\(identifier)-error")
        }
    }

    private var locked: some View {
        let owner = ownerName ?? i18n.resolve("admin.flowVariables.owner_fallback")
        return HStack(spacing: 6) {
            Image(systemName: "lock").accessibilityHidden(true)
            Text(lockedText(owner: owner))
                .font(.footnote)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("admin-flow-variable-\(identifier)-locked")
            if definition.type == .booleanInput {
                Spacer(minLength: 0)
                toggle
            }
        }
    }

    private func lockedText(owner: String) -> String {
        let setBy = i18n.resolve("admin.flowVariables.locked", ["owner": owner])
        let shown = display(value)
        return shown.isEmpty ? setBy : "\(setBy) · \(shown)"
    }

    /// The value as the admin reads it: a boolean as on or off, a choice by its label.
    private func display(_ shown: FlowVariableValue?) -> String {
        guard let shown else { return "" }
        if case .bool(let flag) = shown {
            return i18n.resolve(flag ? "admin.flowVariables.on" : "admin.flowVariables.off")
        }
        guard isSelect else { return shown.text }
        return options.first { $0.value == shown.text }?.label ?? shown.text
    }
}

private extension View {
    /// The keyboard a variable's type calls for, where the platform has one.
    @ViewBuilder
    func flowVariableKeyboard(_ type: FlowVariableType) -> some View {
        #if canImport(UIKit)
        switch type {
        case .emailInput: self.keyboardType(.emailAddress)
        case .phoneInput: self.keyboardType(.phonePad)
        case .numberInput: self.keyboardType(.decimalPad)
        default: self
        }
        #else
        self
        #endif
    }
}
