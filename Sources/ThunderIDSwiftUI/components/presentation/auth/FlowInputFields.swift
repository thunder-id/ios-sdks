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
                binding: bindValue(input.name)
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

    var body: some View {
        Group {
            if type == "PASSWORD_INPUT" {
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
