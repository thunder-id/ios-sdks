/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

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
