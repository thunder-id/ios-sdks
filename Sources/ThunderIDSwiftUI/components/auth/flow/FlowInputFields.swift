// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

struct FlowInputFields: View {
    let inputs: [FlowInput]
    let bindValue: (String) -> Binding<String>

    var body: some View {
        ForEach(inputs, id: \.name) { input in
            FlowInputField(
                name: input.name,
                type: input.type,
                label: input.name,
                placeholder: input.name,
                binding: bindValue(input.name),
                options: input.options
            )
        }
    }
}

/// A single flow input field, rendered either from the flat fallback `FlowInput` list
/// (label/placeholder default to `input.name`) or from a `FlowComponent` in the component tree
/// (label/placeholder resolved from the component's own text via `FlowTemplateResolver`).
struct FlowInputField: View {
    let name: String
    let type: String?
    let label: String
    let placeholder: String
    let binding: Binding<String>
    /// The values a `SELECT` input offers. With any, the field is a picker; without, the user types.
    var options: [String]?

    /// Whether a component of `type` is a selection the step's input may offer options for: a `SELECT`, or
    /// the `OU_SELECT` of a Resolve OU step. Before sign-in no unit is ever listed, so it is typed.
    static func isSelection(_ type: String?) -> Bool {
        ["SELECT", "OU_SELECT"].contains(type?.uppercased() ?? "")
    }

    var body: some View {
        Group {
            if let options, !options.isEmpty {
                Picker(label, selection: binding) {
                    Text(placeholder).tag("")
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if type == "PASSWORD_INPUT" {
                SecureField(placeholder, text: binding)
            } else {
                TextField(placeholder, text: binding)
                    .autocorrectionDisabled()
                    .noAutocapitalization()
            }
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier("thunderid-field-\(name)")
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(Color.fieldBackground)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fieldBorder, lineWidth: 1))
    }
}

private extension View {
    @ViewBuilder
    func noAutocapitalization() -> some View {
        #if canImport(UIKit)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
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
