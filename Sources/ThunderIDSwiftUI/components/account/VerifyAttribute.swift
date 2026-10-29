// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Verifies one of the signed-in user's attributes, such as their email address, by running a self
/// attribute verification flow named by `flowHandle`. The flow sends a code or a link to the attribute's
/// stored value, and the component renders the steps the server describes. For a link it shows where the
/// link went and a Done action that reads the profile again.
///
/// Each showing starts a new verification and sends a new code or link, so give each attribute its own
/// view identity, for example `.id(attribute)`.
public struct VerifyAttribute<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    public let attribute: String
    public let flowHandle: String
    public let attributeDisplayName: String?
    public let onComplete: (() -> Void)?
    public let onDone: (() -> Void)?
    public let onCancel: (() -> Void)?
    public let onError: ((Error) -> Void)?
    let onProfileRead: ((ThunderID.UserProfile?) -> Void)?
    let content: ((VerifyAttributeState) -> Content)?

    init(
        attribute: String,
        flowHandle: String,
        attributeDisplayName: String?,
        onComplete: (() -> Void)?,
        onDone: (() -> Void)?,
        onCancel: (() -> Void)?,
        onError: ((Error) -> Void)?,
        onProfileRead: ((ThunderID.UserProfile?) -> Void)?,
        renderContent: ((VerifyAttributeState) -> Content)?
    ) {
        self.attribute = attribute
        self.flowHandle = flowHandle
        self.attributeDisplayName = attributeDisplayName
        self.onComplete = onComplete
        self.onDone = onDone
        self.onCancel = onCancel
        self.onError = onError
        self.onProfileRead = onProfileRead
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view. See ``BaseVerifyAttribute``.
    public init(
        attribute: String,
        flowHandle: String = AttributeVerification.defaultFlowHandle,
        attributeDisplayName: String? = nil,
        onComplete: (() -> Void)? = nil,
        onDone: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onError: ((Error) -> Void)? = nil,
        @ViewBuilder content: @escaping (VerifyAttributeState) -> Content
    ) {
        self.init(
            attribute: attribute,
            flowHandle: flowHandle,
            attributeDisplayName: attributeDisplayName,
            onComplete: onComplete,
            onDone: onDone,
            onCancel: onCancel,
            onError: onError,
            onProfileRead: nil,
            renderContent: content
        )
    }

    public var body: some View {
        BaseVerifyAttribute(
            attribute: attribute,
            flowHandle: flowHandle,
            attributeDisplayName: attributeDisplayName,
            onComplete: onComplete,
            onDone: onDone,
            onCancel: onCancel,
            onError: onError,
            onProfileRead: onProfileRead
        ) { state in
            if let content {
                content(state)
            } else {
                VerifyAttributeContent(state: state, i18n: i18n)
            }
        }
    }
}

public extension VerifyAttribute where Content == EmptyView {
    /// - Parameters:
    ///   - attribute: The attribute to verify: a top-level `email` or `mobile` property of the user schema.
    ///   - flowHandle: Handle of the `SELF_SERVICE` flow to run.
    ///   - attributeDisplayName: Label of the attribute; the schema's display name by default.
    ///   - onComplete: Called once the server has recorded the verification and the profile was read again.
    ///   - onDone: Called when the user selects Done after a link was sent and the profile was read again.
    ///   - onCancel: Shows a Cancel (or, once finished, Close) action that calls it.
    ///   - onError: Called when the server refuses the verification (`verificationFailed`) or a request fails.
    init(
        attribute: String,
        flowHandle: String = AttributeVerification.defaultFlowHandle,
        attributeDisplayName: String? = nil,
        onComplete: (() -> Void)? = nil,
        onDone: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.init(
            attribute: attribute,
            flowHandle: flowHandle,
            attributeDisplayName: attributeDisplayName,
            onComplete: onComplete,
            onDone: onDone,
            onCancel: onCancel,
            onError: onError,
            onProfileRead: nil,
            renderContent: nil
        )
    }
}

extension VerifyAttribute where Content == EmptyView {
    /// Also hands the profile read again to `onProfileRead`, for the styled `UserProfile`.
    init(
        attribute: String,
        flowHandle: String,
        attributeDisplayName: String?,
        onComplete: (() -> Void)?,
        onDone: (() -> Void)?,
        onCancel: (() -> Void)?,
        onError: ((Error) -> Void)?,
        onProfileRead: ((ThunderID.UserProfile?) -> Void)?
    ) {
        self.init(
            attribute: attribute,
            flowHandle: flowHandle,
            attributeDisplayName: attributeDisplayName,
            onComplete: onComplete,
            onDone: onDone,
            onCancel: onCancel,
            onError: onError,
            onProfileRead: onProfileRead,
            renderContent: nil
        )
    }
}

private struct VerifyAttributeContent: View {
    @ObservedObject var state: VerifyAttributeState
    let i18n: ThunderIDI18n

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if state.phase == .active {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.title)
                        .font(.title2)
                        .bold()
                        .accessibilityAddTraits(.isHeader)
                    Text(state.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if let destinationMessage = state.destinationMessage {
                        Text(destinationMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            if state.phase == .loading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if let error = state.error {
                FlowErrorBanner(message: error)
            }
            if state.phase == .complete {
                Label(state.successMessage, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            if state.phase == .active {
                VerifyAttributeStep(state: state, i18n: i18n)
            }
            footer
        }
    }

    @ViewBuilder private var footer: some View {
        if state.isAwaitingLink {
            Button(i18n.resolve("verifyAttribute.done")) { state.done() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(state.isLoading)
                .accessibilityIdentifier("thunderid-action-verificationDone")
        }
        if let onCancel = state.onCancel {
            let finished = state.phase == .complete || state.phase == .failed
            Button(i18n.resolve(finished ? "verifyAttribute.close" : "verifyAttribute.cancel"), action: onCancel)
                .frame(maxWidth: .infinity)
                .disabled(state.isLoading)
                .accessibilityIdentifier("thunderid-action-verificationCancel")
        }
    }
}

/// Renders the step's components, or its flat inputs and actions when it has none.
private struct VerifyAttributeStep: View {
    @ObservedObject var state: VerifyAttributeState
    let i18n: ThunderIDI18n

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.components.isEmpty {
                ForEach(state.inputs) { input in
                    field(name: input.name, type: input.type, label: nil)
                }
                ForEach(state.actions, id: \.id) { action in
                    actionButton(id: action.id, label: action.label, isResend: false)
                }
            } else {
                ForEach(Array(state.components.enumerated()), id: \.offset) { _, component in
                    componentView(component)
                }
            }
        }
    }

    /// `AnyView`-erased because it recurses into `BLOCK` children.
    private func componentView(_ component: FlowComponent) -> AnyView {
        switch component.type {
        case "TEXT":
            return AnyView(Text(state.text(component.label) ?? "").font(component.headingFont ?? .body))
        case "BLOCK":
            return AnyView(VStack(alignment: .leading, spacing: 12) {
                ForEach(Array((component.components ?? []).enumerated()), id: \.offset) { _, child in
                    componentView(child)
                }
            })
        case "ACTION", "RESEND":
            let id = component.id ?? component.ref ?? ""
            return AnyView(actionButton(id: id, label: component.label, isResend: component.type == "RESEND"))
        case let type? where type.hasSuffix("_INPUT"):
            return AnyView(field(name: component.ref ?? component.id ?? "", type: type, label: component.label))
        default:
            return AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private func field(name: String, type: String?, label: String?) -> some View {
        let isCode = type == "OTP_INPUT"
        let text = state.text(label) ?? (isCode ? i18n.resolve("verifyAttribute.code.label") : name)
        VStack(alignment: .leading, spacing: 4) {
            VerificationCodeField(
                name: name,
                label: text,
                isCode: isCode,
                maxLength: isCode ? state.codeLength : nil,
                binding: state.binding(for: name)
            )
            if let message = state.fieldErrors[name] {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
    }

    @ViewBuilder
    private func actionButton(id: String, label: String?, isResend: Bool) -> some View {
        let fallback = i18n.resolve(isResend ? "verifyAttribute.resend" : "verifyAttribute.submit")
        let title = state.text(label) ?? fallback
        if isResend {
            Button(title) { state.resend(actionId: id) }
                .frame(maxWidth: .infinity)
                .disabled(state.isLoading)
                .accessibilityIdentifier("thunderid-action-\(id)")
        } else {
            Button {
                state.submit(actionId: id)
            } label: {
                Group {
                    if state.isLoading && state.loadingActionId == id {
                        ProgressView()
                    } else {
                        Text(title)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isLoading)
            .accessibilityLabel(title)
            .accessibilityIdentifier("thunderid-action-\(id)")
        }
    }
}

/// An input from the step. A code field takes digits, is filled from a received message where the
/// platform supports it, and stops at the length of the code that was sent.
private struct VerificationCodeField: View {
    let name: String
    let label: String
    let isCode: Bool
    let maxLength: Int?
    let binding: Binding<String>

    private var capped: Binding<String> {
        Binding(
            get: { binding.wrappedValue },
            set: { value in binding.wrappedValue = maxLength.map { String(value.prefix($0)) } ?? value }
        )
    }

    var body: some View {
        TextField(label, text: capped)
            .autocorrectionDisabled()
            .codeEntry(isCode)
            .accessibilityLabel(label)
            .accessibilityIdentifier("thunderid-field-\(name)")
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4), lineWidth: 1))
    }
}

private extension View {
    @ViewBuilder
    func codeEntry(_ isCode: Bool) -> some View {
        #if canImport(UIKit)
        if isCode {
            self.keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
        } else {
            self.textInputAutocapitalization(.never)
        }
        #else
        self
        #endif
    }
}
