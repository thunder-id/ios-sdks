// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Renders the recursive `FlowComponent` tree returned under `data.meta.components`, used by
/// `SignIn` whenever the Flow Execution API response carries component metadata (spec §8.4).
extension SignIn {
    /// `AnyView`-erased because this function recurses (via `blockComponentView`) into itself —
    /// Swift's opaque `some View` return type inference cannot self-reference.
    func componentView(for component: FlowComponent, signInState: SignInState) -> AnyView {
        let type = component.type ?? ""
        if type == "TEXT" {
            return AnyView(textComponentView(component, signInState: signInState))
        } else if type == "BLOCK" {
            return AnyView(blockComponentView(component, signInState: signInState))
        } else if type.hasSuffix("_INPUT") {
            return AnyView(inputComponentView(component, signInState: signInState))
        } else if type == "RICH_TEXT" {
            return AnyView(richTextComponentView(component, signInState: signInState))
        } else if type == "DIVIDER" {
            return AnyView(dividerComponentView(component, signInState: signInState))
        } else if type == "ACTION" {
            return AnyView(actionComponentView(component, signInState: signInState))
        } else {
            return AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private func textComponentView(_ component: FlowComponent, signInState: SignInState) -> some View {
        let isHeading = component.variant == "HEADING_1"
        let isCentered = component.align == "center"
        Text(resolved(component.label, signInState: signInState))
            .font(isHeading ? .title2 : .body)
            .bold(isHeading)
            .frame(maxWidth: isCentered ? .infinity : nil, alignment: isCentered ? .center : .leading)
            .multilineTextAlignment(isCentered ? .center : .leading)
            .accessibilityAddTraits(isHeading ? .isHeader : [])
    }

    @ViewBuilder
    private func blockComponentView(_ component: FlowComponent, signInState: SignInState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array((component.components ?? []).enumerated()), id: \.offset) { _, child in
                componentView(for: child, signInState: signInState)
            }
        }
    }

    @ViewBuilder
    private func inputComponentView(_ component: FlowComponent, signInState: SignInState) -> some View {
        let name = component.ref ?? component.id ?? ""
        let label = resolved(component.label, signInState: signInState, fallback: name)
        let placeholder = resolved(component.placeholder, signInState: signInState, fallback: label)
        FlowInputField(
            name: name,
            type: component.type,
            label: label,
            placeholder: placeholder,
            binding: signInState.binding(for: name)
        )
    }

    @ViewBuilder
    private func richTextComponentView(_ component: FlowComponent, signInState: SignInState) -> some View {
        RichTextLinks(html: resolved(component.label, signInState: signInState)) { actionRef in
            guard let action = signInState.actions.first(where: { $0.ref == actionRef || $0.id == actionRef }) else {
                return
            }
            signInState.submit(actionId: action.id)
        }
    }

    @ViewBuilder
    private func dividerComponentView(_ component: FlowComponent, signInState: SignInState) -> some View {
        let label = resolved(component.label, signInState: signInState, fallback: i18n.resolve("signIn.or"))
        HStack(spacing: 12) {
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
            Text(label)
                .font(.footnote)
                .foregroundColor(.secondary)
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
        }
    }

    @ViewBuilder
    private func actionComponentView(_ component: FlowComponent, signInState: SignInState) -> some View {
        if let action = signInState.actions.first(where: { matches($0, component) }) {
            actionButton(for: action, signInState: signInState)
        } else {
            EmptyView()
        }
    }

    private func matches(_ action: FlowAction, _ component: FlowComponent) -> Bool {
        (component.ref != nil && component.ref == action.ref) || (component.id != nil && component.id == action.id)
    }

    private func resolved(_ text: String?, signInState: SignInState, fallback: String = "") -> String {
        guard let text else {
            return fallback
        }
        let value = signInState.templateResolver?.resolve(text) ?? text
        return value.isEmpty ? fallback : value
    }
}
