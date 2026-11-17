// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Lets a delegated admin override the variables a flow declares for their organization unit. It loads the
/// variables the flow shares with the unit, the values the unit has set and what it may change, shows them
/// as a form, and saves the values that differ from their defaults.
/// ``ThunderIDState/flowVariablesModel(flowId:ouId:fetcher:)`` gives the same data for a form built entirely by
/// the app.
public struct FlowVariablesForm<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let flowId: String
    let ouId: String
    let title: String?
    let description: String?
    let ouName: String?
    let ownerName: String?
    let showScopeNotice: Bool
    let readOnly: Bool
    let onSaved: ((FlowVariableValues) -> Void)?
    let onCancel: (() -> Void)?
    let onCreateConnection: (() -> Void)?
    let content: ((FlowVariablesFormState) -> Content)?

    init(
        flowId: String,
        ouId: String,
        title: String? = nil,
        description: String? = nil,
        ouName: String? = nil,
        ownerName: String? = nil,
        showScopeNotice: Bool = false,
        readOnly: Bool = false,
        onSaved: ((FlowVariableValues) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onCreateConnection: (() -> Void)? = nil,
        renderContent: ((FlowVariablesFormState) -> Content)?
    ) {
        self.flowId = flowId
        self.ouId = ouId
        self.title = title
        self.description = description
        self.ouName = ouName
        self.ownerName = ownerName
        self.showScopeNotice = showScopeNotice
        self.readOnly = readOnly
        self.onSaved = onSaved
        self.onCancel = onCancel
        self.onCreateConnection = onCreateConnection
        self.content = renderContent
    }

    /// - Parameters:
    ///   - flowId: The flow whose variables are configured.
    ///   - ouId: The organization unit the overrides belong to.
    ///   - onSaved: Called with the saved overrides.
    ///   - content: Renders custom UI in place of the default form. See ``BaseFlowVariables``.
    public init(
        flowId: String,
        ouId: String,
        title: String? = nil,
        description: String? = nil,
        ouName: String? = nil,
        ownerName: String? = nil,
        showScopeNotice: Bool = false,
        readOnly: Bool = false,
        onSaved: ((FlowVariableValues) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onCreateConnection: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (FlowVariablesFormState) -> Content
    ) {
        self.init(
            flowId: flowId,
            ouId: ouId,
            title: title,
            description: description,
            ouName: ouName,
            ownerName: ownerName,
            showScopeNotice: showScopeNotice,
            readOnly: readOnly,
            onSaved: onSaved,
            onCancel: onCancel,
            onCreateConnection: onCreateConnection,
            renderContent: content
        )
    }

    public var body: some View {
        FlowVariablesFormHost(
            model: thunderState.flowVariablesModel(flowId: flowId, ouId: ouId),
            props: self
        )
        .id("\(flowId)|\(ouId)")
    }
}

public extension FlowVariablesForm where Content == EmptyView {
    init(
        flowId: String,
        ouId: String,
        title: String? = nil,
        description: String? = nil,
        ouName: String? = nil,
        ownerName: String? = nil,
        showScopeNotice: Bool = false,
        readOnly: Bool = false,
        onSaved: ((FlowVariableValues) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onCreateConnection: (() -> Void)? = nil
    ) {
        self.init(
            flowId: flowId,
            ouId: ouId,
            title: title,
            description: description,
            ouName: ouName,
            ownerName: ownerName,
            showScopeNotice: showScopeNotice,
            readOnly: readOnly,
            onSaved: onSaved,
            onCancel: onCancel,
            onCreateConnection: onCreateConnection,
            renderContent: nil
        )
    }
}

struct FlowVariablesFormHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var model: FlowVariablesModel
    let props: FlowVariablesForm<Content>

    init(model: @autoclosure @escaping () -> FlowVariablesModel, props: FlowVariablesForm<Content>) {
        _model = StateObject(wrappedValue: model())
        self.props = props
    }

    var body: some View {
        Group {
            if !model.isLoaded && model.error == nil {
                AdminLoadingRow(label: i18n.resolve("admin.common.loading"))
            } else {
                BaseFlowVariables(
                    variables: model.definitions,
                    connections: model.connections,
                    initialValues: model.overrides,
                    overlay: model.overlay,
                    isSubmitting: model.isSaving,
                    error: errorMessage,
                    title: props.title ?? i18n.resolve("admin.flowVariables.title"),
                    description: props.description,
                    ouName: props.ouName,
                    ownerName: props.ownerName,
                    showScopeNotice: props.showScopeNotice,
                    readOnly: props.readOnly,
                    onSubmit: { _, overrides in save(overrides) },
                    onCancel: props.onCancel,
                    onCreateConnection: props.onCreateConnection,
                    renderContent: props.content
                )
            }
        }
        .task { await model.load() }
    }

    private var errorMessage: String? {
        i18n.managementErrorMessage(model.error, fallbackKey: "admin.flowVariables.load_error")
            ?? i18n.managementErrorMessage(model.saveError, fallbackKey: "admin.flowVariables.error")
    }

    /// Only what differs from the default is an override; the rest keeps following the default.
    private func save(_ overrides: FlowVariableValues) {
        Task {
            if let saved = await model.save(overrides) {
                props.onSaved?(saved)
            }
        }
    }
}
