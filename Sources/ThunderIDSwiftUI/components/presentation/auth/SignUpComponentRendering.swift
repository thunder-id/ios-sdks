// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Renders the recursive `FlowComponent` tree returned under `data.meta.components`, used by
/// `SignUp` whenever the Flow Execution API response carries component metadata (spec §8.4).
extension SignUp {
    /// `AnyView`-erased because this function recurses (via `blockComponentView`) into itself —
    /// Swift's opaque `some View` return type inference cannot self-reference.
    func componentView(for component: FlowComponent, signUpState: SignUpState) -> AnyView {
        let type = component.type ?? ""
        if type == "TEXT" {
            return AnyView(textComponentView(component, signUpState: signUpState))
        } else if type == "BLOCK" {
            return AnyView(blockComponentView(component, signUpState: signUpState))
        } else if type.hasSuffix("_INPUT") {
            return AnyView(inputComponentView(component, signUpState: signUpState))
        } else if type == "RICH_TEXT" {
            return AnyView(richTextComponentView(component, signUpState: signUpState))
        } else if type == "DIVIDER" {
            return AnyView(dividerComponentView(component, signUpState: signUpState))
        } else if type == "ACTION" {
            return AnyView(actionComponentView(component, signUpState: signUpState))
        } else {
            return AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private func textComponentView(_ component: FlowComponent, signUpState: SignUpState) -> some View {
        let isHeading = component.variant == "HEADING_1"
        let isCentered = component.align == "center"
        Text(resolved(component.label, signUpState: signUpState))
            .font(isHeading ? .title2 : .body)
            .bold(isHeading)
            .frame(maxWidth: isCentered ? .infinity : nil, alignment: isCentered ? .center : .leading)
            .multilineTextAlignment(isCentered ? .center : .leading)
            .accessibilityAddTraits(isHeading ? .isHeader : [])
    }

    @ViewBuilder
    private func blockComponentView(_ component: FlowComponent, signUpState: SignUpState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array((component.components ?? []).enumerated()), id: \.offset) { _, child in
                componentView(for: child, signUpState: signUpState)
            }
        }
    }

    @ViewBuilder
    private func inputComponentView(_ component: FlowComponent, signUpState: SignUpState) -> some View {
        let name = component.ref ?? component.id ?? ""
        let label = resolved(component.label, signUpState: signUpState, fallback: name)
        let placeholder = resolved(component.placeholder, signUpState: signUpState, fallback: label)
        FlowInputField(
            name: name,
            type: component.type,
            label: label,
            placeholder: placeholder,
            binding: signUpState.binding(for: name)
        )
    }

    @ViewBuilder
    private func richTextComponentView(_ component: FlowComponent, signUpState: SignUpState) -> some View {
        RichTextLinks(html: resolved(component.label, signUpState: signUpState)) { actionRef in
            guard let action = signUpState.actions.first(where: { $0.ref == actionRef || $0.id == actionRef }) else {
                return
            }
            signUpState.submit(actionId: action.id)
        }
    }

    @ViewBuilder
    private func dividerComponentView(_ component: FlowComponent, signUpState: SignUpState) -> some View {
        let label = resolved(component.label, signUpState: signUpState, fallback: i18n.resolve("signIn.or"))
        HStack(spacing: 12) {
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
            Text(label)
                .font(.footnote)
                .foregroundColor(.secondary)
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
        }
    }

    @ViewBuilder
    private func actionComponentView(_ component: FlowComponent, signUpState: SignUpState) -> some View {
        if let action = signUpState.actions.first(where: { matches($0, component) }) {
            actionButton(for: action, signUpState: signUpState)
        } else {
            EmptyView()
        }
    }

    private func matches(_ action: FlowAction, _ component: FlowComponent) -> Bool {
        (component.ref != nil && component.ref == action.ref) || (component.id != nil && component.id == action.id)
    }

    private func resolved(_ text: String?, signUpState: SignUpState, fallback: String = "") -> String {
        guard let text else {
            return fallback
        }
        let value = signUpState.templateResolver?.resolve(text) ?? text
        return value.isEmpty ? fallback : value
    }
}
