// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// What ``BaseFlowVariables`` and ``FlowVariablesForm`` hand their `content` closure, so the form can be
/// built with any UI.
public struct FlowVariablesFormState {
    public let variables: [FlowVariableDefinition]
    /// The current value of each variable, keyed by identifier.
    public let values: FlowVariableValues
    /// The translated message to show under each variable that is not valid, keyed by identifier.
    public let errors: [String: String]
    /// Whether the values can be submitted.
    public let isValid: Bool
    public let isSubmitting: Bool
    public let error: String?
    let ruleFor: (FlowVariableDefinition) -> ResolvedFlowVariableRule
    let optionsFor: (FlowVariableDefinition) -> [FlowVariableOption]
    let change: (String, FlowVariableValue) -> Void
    /// Submits the current values. Does nothing while they are not valid. `nil` when the form cannot be saved.
    public let submit: (() -> Void)?
    /// Returns every variable to its default.
    public let resetToDefaults: () -> Void
    public let onCancel: (() -> Void)?

    /// What the unit may do with a variable: whether it can set its own value, and the default it starts from.
    public func rule(for definition: FlowVariableDefinition) -> ResolvedFlowVariableRule { ruleFor(definition) }

    /// The choices of a select variable, narrowed to what the unit may pick.
    public func options(for definition: FlowVariableDefinition) -> [FlowVariableOption] { optionsFor(definition) }

    /// Sets the value of one variable.
    public func setValue(_ value: FlowVariableValue, for identifier: String) { change(identifier, value) }
}

/// The rules of the form, apart from its presentation.
struct FlowVariablesFormLogic {
    let variables: [FlowVariableDefinition]
    let overlay: ResolvedOverlay?
    let connections: [ConnectionInstance]

    func rule(_ definition: FlowVariableDefinition) -> ResolvedFlowVariableRule {
        resolveFlowVariableRule(definition, overlay: overlay)
    }

    /// A variable the unit cannot set shows its pinned value, which a restriction might hide from the choices.
    func options(_ definition: FlowVariableDefinition) -> [FlowVariableOption] {
        let rule = rule(definition)
        let restriction = rule.editable
            ? FlowVariableOptionRestriction(allowedValues: rule.allowedValues, excludedValues: rule.excludedValues)
            : FlowVariableOptionRestriction()
        return getFlowVariableOptions(definition, connections: connections, restriction: restriction)
    }

    /// The values the form starts with: the given value of each variable the unit may set, otherwise its default.
    func startingValues(_ initialValues: FlowVariableValues?) -> FlowVariableValues {
        variables.reduce(into: [:]) { values, definition in
            let rule = rule(definition)
            let chosen = rule.editable ? initialValues?[definition.identifier] ?? rule.defaultValue : rule.defaultValue
            if let chosen { values[definition.identifier] = chosen }
        }
    }

    /// Every variable at its default.
    func defaults() -> FlowVariableValues {
        variables.reduce(into: [:]) { values, definition in
            if let value = rule(definition).defaultValue { values[definition.identifier] = value }
        }
    }

    /// What is wrong with each variable the unit may set.
    func problems(_ values: FlowVariableValues) -> [String: FlowVariableValidationError] {
        variables.reduce(into: [:]) { problems, definition in
            guard rule(definition).editable,
                  let problem = validateFlowVariableValue(definition, values[definition.identifier]) else { return }
            problems[definition.identifier] = problem
        }
    }

    /// The values of the variables the unit may set that differ from their default. A number typed as text
    /// is sent as a number.
    func overrides(_ values: FlowVariableValues) -> FlowVariableValues {
        variables.reduce(into: [:]) { overrides, definition in
            let rule = rule(definition)
            guard rule.editable, var value = values[definition.identifier], value != rule.defaultValue else { return }
            if definition.type == .numberInput, case .string(let text) = value, let number = Double(text) {
                value = .number(number)
            }
            overrides[definition.identifier] = value
        }
    }

    /// The message for a problem: the variable's own, as the flow declares it, or the translated one.
    static func message(_ problem: FlowVariableValidationError, i18n: ThunderIDI18n) -> String {
        problem.message ?? i18n.resolve("admin.flowVariables.errors.\(problem.code.rawValue)")
    }
}

/// A form for the variables a flow declares, each in a card with its label, its description, whether it is
/// customized or follows the default, and the input its type calls for. It holds no data of its own: pass
/// the variables and handle the submission. Without `onSubmit` the form has no save button, which suits a
/// preview, and without `overlay` every variable is editable.
public struct BaseFlowVariables<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let variables: [FlowVariableDefinition]
    let connections: [ConnectionInstance]
    let initialValues: FlowVariableValues?
    let overlay: ResolvedOverlay?
    let isSubmitting: Bool
    let error: String?
    let title: String?
    let description: String?
    let ouName: String?
    let ownerName: String?
    let showScopeNotice: Bool
    let readOnly: Bool
    let onSubmit: ((FlowVariableValues, FlowVariableValues) -> Void)?
    let onChange: ((FlowVariableValues) -> Void)?
    let onCancel: (() -> Void)?
    let onCreateConnection: (() -> Void)?
    let content: ((FlowVariablesFormState) -> Content)?

    @State private var values: FlowVariableValues
    @State private var touched: Set<String> = []
    @State private var submitted = false

    init(
        variables: [FlowVariableDefinition],
        connections: [ConnectionInstance] = [],
        initialValues: FlowVariableValues? = nil,
        overlay: ResolvedOverlay? = nil,
        isSubmitting: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        ouName: String? = nil,
        ownerName: String? = nil,
        showScopeNotice: Bool = false,
        readOnly: Bool = false,
        onSubmit: ((FlowVariableValues, FlowVariableValues) -> Void)? = nil,
        onChange: ((FlowVariableValues) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onCreateConnection: (() -> Void)? = nil,
        renderContent: ((FlowVariablesFormState) -> Content)?
    ) {
        self.variables = variables
        self.connections = connections
        self.initialValues = initialValues
        self.overlay = overlay
        self.isSubmitting = isSubmitting
        self.error = error
        self.title = title
        self.description = description
        self.ouName = ouName
        self.ownerName = ownerName
        self.showScopeNotice = showScopeNotice
        self.readOnly = readOnly
        self.onSubmit = onSubmit
        self.onChange = onChange
        self.onCancel = onCancel
        self.onCreateConnection = onCreateConnection
        self.content = renderContent
        let logic = FlowVariablesFormLogic(variables: variables, overlay: overlay, connections: connections)
        _values = State(initialValue: logic.startingValues(initialValues))
    }

    /// - Parameters:
    ///   - variables: The variables to render, as the flow declares them.
    ///   - connections: The connections a `CONNECTION_SELECT` variable can take.
    ///   - initialValues: The values the form starts with, over each variable's default.
    ///   - overlay: What the unit may do with each variable. Without it every variable is editable.
    ///   - ouName: The organization unit the values are set for, named in the notice and the connection hint.
    ///   - ownerName: Whoever owns the flow, named on a variable the unit may not set.
    ///   - showScopeNotice: Shows that the settings apply to the organization unit only.
    ///   - readOnly: Shows the variables without letting them be changed.
    ///   - onSubmit: Called when the form is submitted and valid, with every value and the overrides: the
    ///     values of the variables the unit may set that differ from their default.
    ///   - onChange: Called with every value after one changes.
    ///   - onCreateConnection: Offered under a connection variable when set.
    ///   - content: Renders custom UI in place of the default form, from the variables, their values and
    ///     setters, the validation messages and the submit handler.
    public init(
        variables: [FlowVariableDefinition],
        connections: [ConnectionInstance] = [],
        initialValues: FlowVariableValues? = nil,
        overlay: ResolvedOverlay? = nil,
        isSubmitting: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        ouName: String? = nil,
        ownerName: String? = nil,
        showScopeNotice: Bool = false,
        readOnly: Bool = false,
        onSubmit: ((FlowVariableValues, FlowVariableValues) -> Void)? = nil,
        onChange: ((FlowVariableValues) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onCreateConnection: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (FlowVariablesFormState) -> Content
    ) {
        self.init(
            variables: variables,
            connections: connections,
            initialValues: initialValues,
            overlay: overlay,
            isSubmitting: isSubmitting,
            error: error,
            title: title,
            description: description,
            ouName: ouName,
            ownerName: ownerName,
            showScopeNotice: showScopeNotice,
            readOnly: readOnly,
            onSubmit: onSubmit,
            onChange: onChange,
            onCancel: onCancel,
            onCreateConnection: onCreateConnection,
            renderContent: content
        )
    }

    private var logic: FlowVariablesFormLogic {
        FlowVariablesFormLogic(variables: variables, overlay: overlay, connections: connections)
    }

    private var startingValues: FlowVariableValues { logic.startingValues(initialValues) }

    public var body: some View {
        Group {
            if let content {
                content(renderState)
            } else {
                defaultBody
            }
        }
        // Only a change to the starting values replaces what was typed.
        .onChange(of: startingValues) { starting in
            values = starting
            touched = []
            submitted = false
        }
    }

    private var problems: [String: FlowVariableValidationError] { logic.problems(values) }

    private var errors: [String: String] {
        let i18n = i18n
        return problems
            .filter { submitted || touched.contains($0.key) }
            .mapValues { FlowVariablesFormLogic.message($0, i18n: i18n) }
    }

    private var renderState: FlowVariablesFormState {
        let logic = logic
        return FlowVariablesFormState(
            variables: variables,
            values: values,
            errors: errors,
            isValid: problems.isEmpty,
            isSubmitting: isSubmitting,
            error: error,
            ruleFor: logic.rule,
            optionsFor: logic.options,
            change: change,
            submit: onSubmit == nil || readOnly ? nil : submit,
            resetToDefaults: resetToDefaults,
            onCancel: onCancel
        )
    }

    private func change(_ identifier: String, _ value: FlowVariableValue) {
        values[identifier] = value
        touched.insert(identifier)
        onChange?(values)
    }

    private func resetToDefaults() {
        values = logic.defaults()
        touched = []
        submitted = false
        onChange?(values)
    }

    private func submit() {
        submitted = true
        guard problems.isEmpty, !isSubmitting else { return }
        onSubmit?(values, logic.overrides(values))
    }

    private var defaultBody: some View {
        let unitName = ouName ?? i18n.resolve("admin.flowVariables.ou_fallback")
        let errors = errors
        return AdminSection(identifier: "admin-flow-variables", title: title, description: description) {
            VStack(alignment: .leading, spacing: 12) {
                if showScopeNotice {
                    AdminPanel(title: i18n.resolve("admin.flowVariables.notice_title", ["ou": unitName])) {
                        Text(i18n.resolve("admin.flowVariables.notice_body", ["ou": unitName]))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("admin-flow-variables-notice")
                }
                if let error {
                    AdminErrorBanner(message: error)
                }
                if variables.isEmpty {
                    Text(i18n.resolve("admin.flowVariables.empty"))
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("admin-flow-variables-empty")
                }
                ForEach(Array(variables.enumerated()), id: \.offset) { _, definition in
                    field(definition, unitName: unitName, error: errors[definition.identifier])
                }
                if onSubmit != nil, !readOnly, !variables.isEmpty {
                    actions
                }
            }
        }
    }

    private func field(_ definition: FlowVariableDefinition, unitName: String, error: String?) -> some View {
        FlowVariableField(
            i18n: i18n,
            definition: definition,
            rule: logic.rule(definition),
            options: logic.options(definition),
            value: values[definition.identifier],
            error: error,
            disabled: readOnly || isSubmitting,
            ouName: unitName,
            ownerName: ownerName,
            onCreateConnection: onCreateConnection
        ) { change(definition.identifier, $0) }
    }

    private var actions: some View {
        HStack {
            Button(i18n.resolve("admin.flowVariables.reset_defaults"), action: resetToDefaults)
                .disabled(isSubmitting)
                .accessibilityIdentifier("admin-flow-variables-reset")
            AdminFormActions(
                i18n: i18n,
                submitLabel: i18n.resolve("admin.flowVariables.submit"),
                isSubmitting: isSubmitting,
                canSubmit: true,
                onCancel: onCancel,
                onSubmit: submit
            )
        }
    }
}

public extension BaseFlowVariables where Content == EmptyView {
    init(
        variables: [FlowVariableDefinition],
        connections: [ConnectionInstance] = [],
        initialValues: FlowVariableValues? = nil,
        overlay: ResolvedOverlay? = nil,
        isSubmitting: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        ouName: String? = nil,
        ownerName: String? = nil,
        showScopeNotice: Bool = false,
        readOnly: Bool = false,
        onSubmit: ((FlowVariableValues, FlowVariableValues) -> Void)? = nil,
        onChange: ((FlowVariableValues) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onCreateConnection: (() -> Void)? = nil
    ) {
        self.init(
            variables: variables,
            connections: connections,
            initialValues: initialValues,
            overlay: overlay,
            isSubmitting: isSubmitting,
            error: error,
            title: title,
            description: description,
            ouName: ouName,
            ownerName: ownerName,
            showScopeNotice: showScopeNotice,
            readOnly: readOnly,
            onSubmit: onSubmit,
            onChange: onChange,
            onCancel: onCancel,
            onCreateConnection: onCreateConnection,
            renderContent: nil
        )
    }
}
