// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// How a device authorization ended.
public enum DeviceGrantResult: String, Equatable {
    /// The user approved the device, which now receives its tokens.
    case approved
    /// The flow refused the device, for example because the user declined.
    case denied
    /// The step's time ran out before the user finished.
    case expired
    /// The flow could not be started or continued.
    case failed
}

/// What ``BaseDeviceGrant`` and ``DeviceGrant`` hand their `content` closure: the flow step the server
/// returned, the values entered so far, and the outcome once there is one.
public struct DeviceGrantState {
    /// The step's component tree, when the server describes one.
    public let components: [FlowComponent]
    /// The step's inputs, such as `user_code`.
    public let inputs: [FlowInput]
    /// The step's actions, with their presentation filled in from the component tree.
    public let actions: [FlowAction]
    public let additionalData: [String: AnyCodable]
    public let isLoading: Bool
    /// A translated message, or `nil` when there is nothing to report.
    public let error: String?
    /// The outcome, once the flow has ended.
    public let result: DeviceGrantResult?
    /// The values entered so far, keyed by input name.
    public let values: [String: String]
    let bindingFor: (String) -> Binding<String>
    /// Submits the entered values with the given action, or with the step's only action when `nil`.
    public let submit: (String?) -> Void
    let resolver: FlowTemplateResolver?

    /// A binding to one input's value.
    public func value(for name: String) -> Binding<String> { bindingFor(name) }

    /// Resolves the `{{ t(...) }}` and `{{ meta(...) }}` templates in a server-described label.
    public func resolve(_ text: String?) -> String {
        guard let text else { return "" }
        return resolver?.resolve(text) ?? text
    }
}

/// The user side of device authorization, rendered from the flow step it is given: the code the device
/// shows (prefilled from `initialValues`, e.g. a scanned verification URI's `user_code`) and any further
/// step the server returns, tagged `thunderid-field-<name>` and `thunderid-action-<ref>`, then the
/// approved, denied, expired or failed outcome. Pair it with
/// ``ThunderIDClient/verifyDeviceCode(userCode:applicationId:)``; ``DeviceGrant`` does that for you.
public struct BaseDeviceGrant<Content: View>: View {
    let components: [FlowComponent]
    let inputs: [FlowInput]
    let actions: [FlowAction]
    let additionalData: [String: AnyCodable]
    let initialValues: [String: String]
    let isLoading: Bool
    let error: String?
    let result: DeviceGrantResult?
    let resolver: FlowTemplateResolver?
    let onSubmit: (String?, [String: String]) -> Void
    let content: ((DeviceGrantState) -> Content)?

    init(
        components: [FlowComponent] = [],
        inputs: [FlowInput] = [],
        actions: [FlowAction] = [],
        additionalData: [String: AnyCodable] = [:],
        initialValues: [String: String] = [:],
        isLoading: Bool = false,
        error: String? = nil,
        result: DeviceGrantResult? = nil,
        resolver: FlowTemplateResolver? = nil,
        onSubmit: @escaping (String?, [String: String]) -> Void,
        renderContent: ((DeviceGrantState) -> Content)?
    ) {
        self.components = components
        self.inputs = inputs
        self.actions = FlowComponentMerging.enrichActions(actions, with: components)
        self.additionalData = additionalData
        self.initialValues = initialValues
        self.isLoading = isLoading
        self.error = error
        self.result = result
        self.resolver = resolver
        self.onSubmit = onSubmit
        self.content = renderContent
    }

    /// - Parameters:
    ///   - onSubmit: Called with the chosen action (or `nil` for the step's only one) and the entered values.
    ///   - content: Renders custom UI in place of the default view, from the step, the entered values, the
    ///     submit action, and the loading, error and outcome state.
    public init(
        components: [FlowComponent] = [],
        inputs: [FlowInput] = [],
        actions: [FlowAction] = [],
        additionalData: [String: AnyCodable] = [:],
        initialValues: [String: String] = [:],
        isLoading: Bool = false,
        error: String? = nil,
        result: DeviceGrantResult? = nil,
        onSubmit: @escaping (String?, [String: String]) -> Void,
        @ViewBuilder content: @escaping (DeviceGrantState) -> Content
    ) {
        self.init(
            components: components,
            inputs: inputs,
            actions: actions,
            additionalData: additionalData,
            initialValues: initialValues,
            isLoading: isLoading,
            error: error,
            result: result,
            onSubmit: onSubmit,
            renderContent: content
        )
    }

    public var body: some View {
        DeviceGrantStepHost(props: self).id(stepKey)
    }

    /// Identifies the step, so the entered values start over when the server moves to another one.
    private var stepKey: String {
        (inputs.map(\.name) + FlowComponentMerging.inputNames(in: components) + actions.map(\.id))
            .joined(separator: "|")
    }

    /// The names of the inputs the step asks for, from the flat list and the component tree.
    var inputNames: [String] {
        Array(Set(inputs.map(\.name)).union(FlowComponentMerging.inputNames(in: components)))
    }
}

public extension BaseDeviceGrant where Content == EmptyView {
    init(
        components: [FlowComponent] = [],
        inputs: [FlowInput] = [],
        actions: [FlowAction] = [],
        additionalData: [String: AnyCodable] = [:],
        initialValues: [String: String] = [:],
        isLoading: Bool = false,
        error: String? = nil,
        result: DeviceGrantResult? = nil,
        onSubmit: @escaping (String?, [String: String]) -> Void
    ) {
        self.init(
            components: components,
            inputs: inputs,
            actions: actions,
            additionalData: additionalData,
            initialValues: initialValues,
            isLoading: isLoading,
            error: error,
            result: result,
            onSubmit: onSubmit,
            renderContent: nil
        )
    }
}

/// Holds the values entered on one step of ``BaseDeviceGrant``.
private struct DeviceGrantStepHost<Content: View>: View {
    @State private var values: [String: String]
    let props: BaseDeviceGrant<Content>

    init(props: BaseDeviceGrant<Content>) {
        self.props = props
        let names = props.inputNames
        _values = State(
            initialValue: Dictionary(uniqueKeysWithValues: names.map { ($0, props.initialValues[$0] ?? "") })
        )
    }

    var body: some View {
        let state = renderState
        if let content = props.content {
            content(state)
        } else {
            DeviceGrantDefaultView(state: state)
        }
    }

    private var renderState: DeviceGrantState {
        let onSubmit = props.onSubmit
        let actions = props.actions
        let current = values
        return DeviceGrantState(
            components: props.components,
            inputs: props.inputs,
            actions: actions,
            additionalData: props.additionalData,
            isLoading: props.isLoading,
            error: props.error,
            result: props.result,
            values: current,
            bindingFor: { name in
                Binding(get: { values[name] ?? "" }, set: { values[name] = $0 })
            },
            submit: { actionId in
                guard !props.isLoading else { return }
                onSubmit(actionId ?? (actions.count == 1 ? actions.first?.id : nil), values)
            },
            resolver: props.resolver
        )
    }
}

/// Runs the application's `DEVICE_GRANT` flow so the signed-in user can approve a device: it submits
/// `userCode` (e.g. the `user_code` of a scanned verification URI) when given, otherwise asks for the
/// code the device shows, renders every further step the server returns, and shows whether the device
/// was approved or denied, or the step expired. `applicationId` defaults to the configured one.
public struct DeviceGrant<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var model = DeviceGrantModel()
    let applicationId: String?
    let userCode: String?
    let onComplete: ((DeviceGrantResult) -> Void)?
    let onError: ((String) -> Void)?
    let content: ((DeviceGrantState) -> Content)?

    init(
        applicationId: String? = nil,
        userCode: String? = nil,
        onComplete: ((DeviceGrantResult) -> Void)? = nil,
        onError: ((String) -> Void)? = nil,
        renderContent: ((DeviceGrantState) -> Content)?
    ) {
        self.applicationId = applicationId
        self.userCode = userCode
        self.onComplete = onComplete
        self.onError = onError
        self.content = renderContent
    }

    /// - Parameters:
    ///   - applicationId: The application whose `DEVICE_GRANT` flow runs. Defaults to the configured one.
    ///   - userCode: The code the device shows, when the app already has it.
    ///   - onComplete: Called with the outcome once the flow has ended.
    ///   - onError: Called with a translated message when the flow cannot be started or continued.
    ///   - content: Renders custom UI in place of the default view. See ``BaseDeviceGrant``.
    public init(
        applicationId: String? = nil,
        userCode: String? = nil,
        onComplete: ((DeviceGrantResult) -> Void)? = nil,
        onError: ((String) -> Void)? = nil,
        @ViewBuilder content: @escaping (DeviceGrantState) -> Content
    ) {
        self.init(
            applicationId: applicationId,
            userCode: userCode,
            onComplete: onComplete,
            onError: onError,
            renderContent: content
        )
    }

    public var body: some View {
        BaseDeviceGrant(
            components: model.flow?.data?.meta?.components ?? [],
            inputs: model.flow?.data?.inputs ?? [],
            actions: model.flow?.data?.actions ?? [],
            additionalData: model.flow?.data?.additionalData ?? [:],
            initialValues: userCode.map { ["user_code": $0] } ?? [:],
            isLoading: model.isLoading,
            error: model.error,
            result: model.result,
            resolver: model.resolver,
            onSubmit: { actionId, values in
                Task { await model.submit(actionId: actionId, inputs: values, context: context) }
            },
            renderContent: content
        )
        .task { await model.start(userCode: userCode, applicationId: applicationId, context: context) }
    }

    private var context: DeviceGrantModel.Context {
        DeviceGrantModel.Context(client: thunderState.client, i18n: i18n, onComplete: onComplete, onError: onError)
    }
}

public extension DeviceGrant where Content == EmptyView {
    init(
        applicationId: String? = nil,
        userCode: String? = nil,
        onComplete: ((DeviceGrantResult) -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        self.init(
            applicationId: applicationId,
            userCode: userCode,
            onComplete: onComplete,
            onError: onError,
            renderContent: nil
        )
    }
}
