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
        ForEach(inputs.indices, id: \.self) { idx in
            fieldView(for: idx)
        }
    }

    @ViewBuilder
    private func fieldView(for idx: Int) -> some View {
        let input = inputs[idx]
        if input.type == "PASSWORD_INPUT" {
            SecureField(input.name, text: bindValue(input.name))
                .accessibilityLabel(input.name)
                .accessibilityIdentifier("thunderid-field-\(input.name)")
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(Color.fieldBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fieldBorder, lineWidth: 1))
        } else {
            TextField(input.name, text: bindValue(input.name))
                .accessibilityLabel(input.name)
                .accessibilityIdentifier("thunderid-field-\(input.name)")
                .autocorrectionDisabled()
                .noAutocapitalization()
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(Color.fieldBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fieldBorder, lineWidth: 1))
        }
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
