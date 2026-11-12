// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID
import ThunderIDSwiftUI

/// Renders the shared flow list and flow variables form stories. Both need an organization unit when live.
struct SharedFlowsPreview: View {
    let id: String
    let values: PropValues
    let onEvent: (String) -> Void

    var body: some View {
        if values.isLive && values.text("ouId").isEmpty {
            PreviewHint(text: "Set ouId to load it from the server.")
        } else if id == "sharedFlowList" {
            list
        } else {
            form
        }
    }

    private var ownership: SharedFlowOwnership { SharedFlowOwnership(rawValue: values.text("ownership")) ?? .shared }

    @ViewBuilder private var list: some View {
        let onSelect: (ManagedFlow) -> Void = { onEvent("onSelect \($0.handle)") }
        switch (values.isLive, values.isCustom) {
        case (true, true):
            SharedFlowList(ouId: values.text("ouId"), ownership: ownership, onSelect: onSelect) {
                CustomFlowRows(list: $0)
            }
        case (true, false):
            SharedFlowList(ouId: values.text("ouId"), ownership: ownership, onSelect: onSelect)
        case (false, true):
            BaseSharedFlowList(flows: SharedFlowSamples.flows, onSelect: onSelect) { CustomFlowRows(list: $0) }
        case (false, false):
            BaseSharedFlowList(flows: SharedFlowSamples.flows, onSelect: onSelect)
        }
    }

    @ViewBuilder private var form: some View {
        let onSaved: (FlowVariableValues) -> Void = { onEvent("onSaved \($0.keys.sorted())") }
        let readOnly = values.flag("readOnly")
        let onSubmit: (FlowVariableValues, FlowVariableValues) -> Void = { _, overrides in
            onEvent("onSubmit \(overrides.keys.sorted())")
        }
        switch (values.isLive, values.isCustom) {
        case (true, true):
            FlowVariablesForm(flowId: values.text("flowId"), ouId: values.text("ouId"), onSaved: onSaved) {
                CustomVariableForm(form: $0)
            }
        case (true, false):
            FlowVariablesForm(
                flowId: values.text("flowId"),
                ouId: values.text("ouId"),
                showScopeNotice: true,
                readOnly: readOnly,
                onSaved: onSaved
            )
        case (false, true):
            BaseFlowVariables(
                variables: SharedFlowSamples.variables,
                connections: SharedFlowSamples.connections,
                overlay: SharedFlowSamples.overlay,
                onSubmit: onSubmit
            ) { CustomVariableForm(form: $0) }
        case (false, false):
            BaseFlowVariables(
                variables: SharedFlowSamples.variables,
                connections: SharedFlowSamples.connections,
                initialValues: ["otp": .number(90)],
                overlay: SharedFlowSamples.overlay,
                title: "Flow variables",
                ouName: "Acme",
                ownerName: "Root",
                showScopeNotice: true,
                readOnly: readOnly,
                onSubmit: onSubmit,
                onCreateConnection: { onEvent("onCreateConnection") }
            )
        }
    }
}

/// Sample flows, variables and rules, decoded from JSON shaped like the API's.
private enum SharedFlowSamples {
    static let flows: [ManagedFlow] = decode("""
    [
      {"id": "flw-login", "handle": "partner-login", "name": "Partner login", "flowType": "AUTHENTICATION",
       "isOwnedByOU": false},
      {"id": "flw-signup", "handle": "partner-signup", "name": "Partner sign-up", "flowType": "REGISTRATION",
       "isOwnedByOU": false}
    ]
    """)

    static let variables: [FlowVariableDefinition] = decode("""
    [
      {"identifier": "brandName", "type": "TEXT_INPUT", "label": "Brand name", "defaultValue": "Acme",
       "description": "Shown on the sign-in page"},
      {"identifier": "otp", "type": "NUMBER_INPUT", "label": "Code lifetime (seconds)", "defaultValue": 60,
       "min": 30, "max": 300},
      {"identifier": "mfa", "type": "BOOLEAN_INPUT", "label": "Require MFA", "defaultValue": false},
      {"identifier": "idp", "type": "CONNECTION_SELECT", "label": "Identity provider",
       "category": "identity-provider"}
    ]
    """)

    static let connections: [ConnectionInstance] = decode("""
    [{"id": "con-google", "name": "Google", "type": "google", "categories": ["identity-provider"]}]
    """)

    static let overlay: ResolvedOverlay = decode("""
    {"ouId": "ou-acme", "isOwnedByOU": false, "rules": {"variables.otp": {"editable": true},
     "variables.idp": {"editable": true}, "variables.brandName": {"editable": true},
     "variables.mfa": {"value": ["true"]}}}
    """)

    private static func decode<Value: Decodable>(_ json: String) -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: Data(json.utf8))
        } catch {
            fatalError("Invalid shared flow sample for \(Value.self): \(error)")
        }
    }
}

/// Custom flow rows: a card per flow with its type.
private struct CustomFlowRows: View {
    let list: AdminListState<ManagedFlow>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(list.rows, id: \.id) { flow in
                Button { list.onSelect?(flow) } label: {
                    HStack {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                        Text(flow.name ?? flow.handle)
                        Spacer()
                        Text(flow.flowType).font(.caption.monospaced())
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A custom variable form: a text field per variable, saved with one button.
private struct CustomVariableForm: View {
    let form: FlowVariablesFormState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(form.variables, id: \.identifier) { variable in
                TextField(
                    variable.label ?? variable.identifier,
                    text: Binding(
                        get: { form.values[variable.identifier]?.text ?? "" },
                        set: { form.setValue(.string($0), for: variable.identifier) }
                    )
                )
                .disabled(!form.rule(for: variable).editable)
                if let error = form.errors[variable.identifier] {
                    Text(error).foregroundColor(.red)
                }
            }
            if let submit = form.submit {
                Button("Save", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(form.isSubmitting)
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}
