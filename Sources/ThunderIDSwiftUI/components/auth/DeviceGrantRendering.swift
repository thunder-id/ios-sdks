// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Runs the `DEVICE_GRANT` flow for ``DeviceGrant``.
@MainActor
final class DeviceGrantModel: ObservableObject {
    struct Context {
        let client: ThunderIDClient
        let i18n: ThunderIDI18n
        let onComplete: ((DeviceGrantResult) -> Void)?
        let onError: ((String) -> Void)?
    }

    /// The server's code for a user code that is wrong or no longer usable. The step asks for it again.
    static let invalidCodeError = "FET-1131"

    @Published private(set) var flow: EmbeddedFlowResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var result: DeviceGrantResult?
    @Published private(set) var resolver: FlowTemplateResolver?
    private var hasStarted = false
    private var expiry: Task<Void, Never>?

    deinit { expiry?.cancel() }

    func start(userCode: String?, applicationId: String?, context: Context) async {
        guard !hasStarted else { return }
        hasStarted = true
        if let applicationId {
            Task { [weak self] in
                guard let meta = try? await context.client.getFlowMeta(applicationId: applicationId) else { return }
                self?.resolver = FlowTemplateResolver(meta: meta)
            }
        }
        await run(context: context, failureKey: "deviceGrant.errors.start") {
            try await context.client.verifyDeviceCode(userCode: userCode, applicationId: applicationId)
        }
    }

    func submit(actionId: String?, inputs: [String: String], context: Context) async {
        guard let flow, let flowId = flow.flowId, !isLoading else { return }
        let payload = EmbeddedSignInPayload(
            flowId: flowId,
            actionId: actionId,
            inputs: inputs,
            challengeToken: flow.challengeToken
        )
        await run(context: context, failureKey: "deviceGrant.errors.continue") {
            try await context.client.verifyDeviceCode(payload: payload)
        }
    }

    private func run(
        context: Context,
        failureKey: String,
        call: () async throws -> DeviceCodeVerificationResponse
    ) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            apply(try await call().flow, context: context)
        } catch {
            flow = nil
            finish(.failed, message: context.i18n.resolve(failureKey), context: context)
        }
    }

    func apply(_ response: EmbeddedFlowResponse, context: Context) {
        expiry?.cancel()
        switch response.flowStatus {
        case .complete:
            flow = nil
            finish(.approved, message: nil, context: context)
        case .error:
            flow = nil
            finish(.denied, message: translated(response.error), context: context)
        case .promptOnly:
            flow = response
            result = nil
            if response.error?.code == Self.invalidCodeError {
                error = context.i18n.resolve("deviceGrant.errors.invalidCode")
            } else if response.error != nil {
                error = translated(response.error) ?? context.i18n.resolve("deviceGrant.errors.continue")
            }
            scheduleExpiry(response, context: context)
        }
    }

    /// The server's message for `error`, translated through the flow metadata, or `nil` when there is no
    /// translation. The server's own English text is never shown.
    private func translated(_ error: FlowError?) -> String? {
        guard let error else { return nil }
        return resolver?.translate(error.message)
    }

    private func finish(_ outcome: DeviceGrantResult, message: String?, context: Context) {
        result = outcome
        error = message
        if outcome == .failed {
            context.onError?(message ?? context.i18n.resolve("deviceGrant.messages.failed"))
        } else {
            context.onComplete?(outcome)
        }
    }

    /// Ends the flow as expired when the step's `stepTimeout` (epoch milliseconds) passes first.
    private func scheduleExpiry(_ response: EmbeddedFlowResponse, context: Context) {
        guard let deadline = Self.deadline(response.data?.additionalData?["stepTimeout"]?.value) else { return }
        let flowId = response.flowId
        let delay = max(0, deadline.timeIntervalSinceNow)
        expiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.flow?.flowId == flowId else { return }
            self.flow = nil
            self.finish(.expired, message: nil, context: context)
        }
    }

    static func deadline(_ raw: Any?) -> Date? {
        let milliseconds: Double?
        switch raw {
        case let value as Double: milliseconds = value
        case let value as Int: milliseconds = Double(value)
        case let value as String: milliseconds = Double(value)
        default: milliseconds = nil
        }
        guard let milliseconds, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}

/// The built-in UI of ``BaseDeviceGrant``: the outcome once there is one, otherwise the flow step.
struct DeviceGrantDefaultView: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let state: DeviceGrantState

    var body: some View {
        if let result = state.result {
            DeviceGrantResultCard(i18n: i18n, result: result, message: state.error)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if !hasHeading {
                    Text(i18n.resolve("deviceGrant.title"))
                        .font(.title2)
                        .bold()
                        .accessibilityAddTraits(.isHeader)
                }
                if let error = state.error {
                    FlowErrorBanner(message: error)
                        .accessibilityIdentifier("thunderid-device-grant-error")
                }
                if state.components.isEmpty {
                    flatStep
                } else {
                    ForEach(Array(state.components.enumerated()), id: \.offset) { _, component in
                        componentView(component)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("thunderid-device-grant")
        }
    }

    private var hasHeading: Bool {
        state.components.contains { $0.type == "TEXT" && $0.headingFont != nil }
    }

    @ViewBuilder
    private var flatStep: some View {
        if state.isLoading && state.inputs.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text(i18n.resolve("deviceGrant.loading")).foregroundColor(.secondary)
            }
        } else {
            if !state.inputs.isEmpty {
                Text(i18n.resolve("deviceGrant.description"))
                    .foregroundColor(.secondary)
            }
            ForEach(state.inputs) { input in
                let label = input.name == "user_code" ? i18n.resolve("deviceGrant.userCode") : input.name
                FlowInputField(
                    name: input.name,
                    type: input.type,
                    label: label,
                    placeholder: label,
                    binding: state.value(for: input.name),
                    options: input.options
                )
            }
            if state.actions.isEmpty {
                if !state.inputs.isEmpty {
                    DeviceGrantActionButton(label: i18n.resolve("deviceGrant.submit"), tag: "submit", state: state) {
                        state.submit(nil)
                    }
                }
            } else {
                ForEach(state.actions, id: \.id) { action in actionButton(action) }
            }
        }
    }

    private func actionButton(_ action: FlowAction) -> some View {
        let label = action.label.map { state.resolve($0) } ?? i18n.resolve("deviceGrant.submit")
        return DeviceGrantActionButton(
            label: label,
            tag: action.ref ?? action.id,
            isOutlined: FlowComponentMerging.isOutlinedVariant(action.variant),
            state: state
        ) {
            state.submit(action.id)
        }
    }

    /// `AnyView`-erased because it recurses into itself for a `BLOCK`.
    private func componentView(_ component: FlowComponent) -> AnyView {
        let type = component.type ?? ""
        switch type {
        case "TEXT":
            return AnyView(
                Text(state.resolve(component.label))
                    .font(component.headingFont ?? .body)
                    .bold(component.headingFont != nil)
                    .accessibilityAddTraits(component.headingFont != nil ? .isHeader : [])
            )
        case "BLOCK":
            return AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array((component.components ?? []).enumerated()), id: \.offset) { _, child in
                        componentView(child)
                    }
                }
            )
        case "ACTION":
            let action = state.actions.first { matches($0, component) }
            return AnyView(action.map { actionButton($0) })
        case "DIVIDER":
            return AnyView(Divider())
        case "RICH_TEXT":
            return AnyView(
                RichTextLinks(html: state.resolve(component.label)) { ref in
                    state.actions.first { $0.ref == ref || $0.id == ref }.map { state.submit($0.id) }
                }
            )
        case "KEY_VALUE_LIST":
            let raw = component.source.flatMap { state.additionalData[$0]?.value }
            let pairs = KeyValuePair.list(from: raw).map {
                KeyValuePair(label: state.resolve($0.label), value: $0.value)
            }
            guard !pairs.isEmpty else { return AnyView(EmptyView()) }
            return AnyView(KeyValueList(label: state.resolve(component.label), pairs: pairs))
        default:
            guard type.hasSuffix("_INPUT") || FlowInputField.isSelection(type) else { return AnyView(EmptyView()) }
            return AnyView(inputView(component))
        }
    }

    private func inputView(_ component: FlowComponent) -> some View {
        let name = component.ref ?? component.id ?? ""
        let fallback = name == "user_code" ? i18n.resolve("deviceGrant.userCode") : name
        let label = component.label.map { state.resolve($0) }.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        let placeholder = component.placeholder.map { state.resolve($0) }.flatMap { $0.isEmpty ? nil : $0 } ?? label
        return FlowInputField(
            name: name,
            type: component.type,
            label: label,
            placeholder: placeholder,
            binding: state.value(for: name),
            options: state.inputs.first { $0.name == name }?.options
        )
    }

    private func matches(_ action: FlowAction, _ component: FlowComponent) -> Bool {
        (component.ref != nil && component.ref == action.ref) || (component.id != nil && component.id == action.id)
    }
}

/// A flow action of the device grant, tagged `thunderid-action-<ref>`.
private struct DeviceGrantActionButton: View {
    let label: String
    let tag: String
    var isOutlined = false
    let state: DeviceGrantState
    let onTap: () -> Void

    var body: some View {
        Group {
            if isOutlined {
                Button(action: onTap) {
                    Text(label).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: onTap) {
                    Group {
                        if state.isLoading {
                            ProgressView()
                        } else {
                            Text(label)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
        .disabled(state.isLoading)
        .accessibilityLabel(label)
        .accessibilityIdentifier("thunderid-action-\(tag)")
    }
}

/// The outcome of a device authorization.
struct DeviceGrantResultCard: View {
    let i18n: ThunderIDI18n
    let result: DeviceGrantResult
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(i18n.resolve("deviceGrant.messages.\(titleKey)"), systemImage: icon)
                .font(.title3.weight(.semibold))
                .foregroundColor(result == .approved ? .green : .red)
                .accessibilityAddTraits(.isHeader)
            Text(message ?? i18n.resolve("deviceGrant.messages.\(titleKey)Description"))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("thunderid-device-grant-result")
    }

    private var titleKey: String {
        switch result {
        case .approved: return "complete"
        case .denied: return "denied"
        case .expired: return "expired"
        case .failed: return "failed"
        }
    }

    private var icon: String {
        result == .approved ? "checkmark.circle.fill" : "xmark.octagon.fill"
    }
}
