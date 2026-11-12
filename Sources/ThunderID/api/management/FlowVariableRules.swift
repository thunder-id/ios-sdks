// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

private let variablesNodeType = "VARIABLES"
private let emailPattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
private let phonePattern = #"^\+?[0-9\s\-()]{6,20}$"#
private let datePattern = #"^\d{4}-\d{2}-\d{2}$"#

/// Reads the variables a flow declares. A flow shared with an organization unit lists them in
/// ``FlowDefinition/variables``; a flow the unit owns declares them on its `VARIABLES` node. An input of that
/// node without a string `identifier` and `type` is left out.
/// - Parameter flow: The flow, as ``FlowsAPI/get(id:ouId:fetcher:)`` returns it.
/// - Returns: The declared variables, empty when the flow declares none.
public func getFlowVariableDefinitions(_ flow: FlowDefinition?) -> [FlowVariableDefinition] {
    guard let flow else { return [] }
    if let variables = flow.variables { return variables }
    guard let node = flow.nodes.first(where: { $0.type == variablesNodeType }),
          let inputs = node.fields["inputs"]?.value as? [AnyCodable] else { return [] }
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    return inputs.compactMap { input in
        guard let fields = input.value as? [String: AnyCodable],
              fields["identifier"]?.value is String,
              fields["type"]?.value is String,
              let data = try? encoder.encode(input) else { return nil }
        return try? decoder.decode(FlowVariableDefinition.self, from: data)
    }
}

/// Lists what a select variable can take. A `SELECT` takes the values it declares; a `CONNECTION_SELECT`
/// takes the connections of its `category` and `connectionTypes`. Any other variable has no options.
/// - Parameters:
///   - definition: The variable.
///   - connections: The connections available to the organization unit.
///   - restriction: The values a sharing policy lets the unit choose from, or takes away.
/// - Returns: The choices, each with the value to store.
public func getFlowVariableOptions(
    _ definition: FlowVariableDefinition,
    connections: [ConnectionInstance] = [],
    restriction: FlowVariableOptionRestriction = FlowVariableOptionRestriction()
) -> [FlowVariableOption] {
    let permitted: (FlowVariableOption) -> Bool = { option in
        (restriction.allowedValues?.contains(option.value) ?? true)
            && !(restriction.excludedValues ?? []).contains(option.value)
    }
    if definition.type == .select {
        return (definition.options ?? [])
            .map { FlowVariableOption(label: $0.text, value: $0.text) }
            .filter(permitted)
    }
    guard definition.type == .connectionSelect else { return [] }
    let normalize: (String) -> String = { $0.lowercased().replacingOccurrences(of: "_", with: "-") }
    let category = definition.category.map(normalize)
    let vendors = (definition.connectionTypes ?? []).map(normalize)
    return connections
        .filter { connection in
            (category.map { connection.categories.map(normalize).contains($0) } ?? true)
                && (vendors.isEmpty || vendors.contains(normalize(connection.type)))
        }
        .map { FlowVariableOption(label: $0.name, value: $0.id) }
        .filter(permitted)
}

/// Works out what an organization unit may do with a variable. A unit that owns the flow may set everything.
/// For a flow shared with it, a variable no policy names cannot be edited and keeps the owner's default, and a
/// policy may pin it to a value. Without an overlay, such as in a preview, every variable is editable.
/// - Parameters:
///   - definition: The variable.
///   - overlay: What the unit may do with the flow, as ``FlowsAPI/overlayRules(id:ouId:fetcher:)`` returns it.
/// - Returns: The rule that applies to the variable.
public func resolveFlowVariableRule(
    _ definition: FlowVariableDefinition,
    overlay: ResolvedOverlay? = nil
) -> ResolvedFlowVariableRule {
    guard let overlay else {
        return ResolvedFlowVariableRule(defaultValue: definition.defaultValue, editable: true)
    }
    if overlay.isOwnedByOU == true {
        return ResolvedFlowVariableRule(defaultValue: definition.defaultValue, editable: true)
    }
    let rule = overlay.rules?["variables.\(definition.identifier)"]
    return ResolvedFlowVariableRule(
        allowedValues: rule?.allowedValues,
        defaultValue: rule?.value?.first.map { flowVariableValue(definition, from: $0) } ?? definition.defaultValue,
        editable: rule?.editable == true,
        excludedValues: rule?.excludedValues
    )
}

/// Reads a value a rule carries, always written as a string, in the variable's own type.
private func flowVariableValue(_ definition: FlowVariableDefinition, from raw: String) -> FlowVariableValue {
    switch definition.type {
    case .booleanInput:
        return .bool(raw == "true")
    case .numberInput:
        return Double(raw).map(FlowVariableValue.number) ?? .string(raw)
    case .select:
        return definition.options?.first { $0.text == raw } ?? .string(raw)
    default:
        return .string(raw)
    }
}

/// Checks a value against a variable's type, options and rules, so a form can report what is wrong before
/// the server does. The server validates again on save.
/// - Parameters:
///   - definition: The variable the value is for.
///   - value: The value to check.
/// - Returns: What is wrong with the value, or `nil` when it is valid.
public func validateFlowVariableValue(
    _ definition: FlowVariableDefinition,
    _ value: FlowVariableValue?
) -> FlowVariableValidationError? {
    if definition.type == .booleanInput {
        return value == nil || value?.isBool == true ? nil : FlowVariableValidationError(code: .invalid)
    }
    guard let value, value != .string("") else { return FlowVariableValidationError(code: .required) }
    switch definition.type {
    case .numberInput:
        return validateNumber(definition, value)
    case .select:
        return (definition.options ?? []).contains { $0.text == value.text } ? nil : FlowVariableValidationError(code: .notOption)
    case .emailInput, .phoneInput, .dateInput:
        return validateFormat(definition.type, value.text)
    case .connectionSelect:
        return value.isString ? nil : FlowVariableValidationError(code: .invalid)
    default:
        return validateText(definition.validation ?? [], value.text)
    }
}

private func validateFormat(_ type: FlowVariableType, _ text: String) -> FlowVariableValidationError? {
    let pattern: String
    switch type {
    case .emailInput: pattern = emailPattern
    case .phoneInput: pattern = phonePattern
    default: pattern = datePattern
    }
    return text.range(of: pattern, options: .regularExpression) == nil
        ? FlowVariableValidationError(code: .invalid)
        : nil
}

private func validateNumber(
    _ definition: FlowVariableDefinition,
    _ value: FlowVariableValue
) -> FlowVariableValidationError? {
    let numeric: Double?
    switch value {
    case .number(let number): numeric = number
    case .string(let text): numeric = Double(text.trimmingCharacters(in: .whitespaces))
    case .bool: numeric = nil
    }
    guard let numeric, !numeric.isNaN else { return FlowVariableValidationError(code: .invalid) }
    if let min = definition.min, numeric < min { return FlowVariableValidationError(code: .min) }
    if let max = definition.max, numeric > max { return FlowVariableValidationError(code: .max) }
    return nil
}

private func validateText(_ rules: [FlowVariableValidationRule], _ text: String) -> FlowVariableValidationError? {
    for rule in rules {
        let limit = Double(rule.value.text) ?? .nan
        if rule.type == "minLength", Double(text.count) < limit {
            return FlowVariableValidationError(code: .minLength, message: rule.message)
        }
        if rule.type == "maxLength", Double(text.count) > limit {
            return FlowVariableValidationError(code: .maxLength, message: rule.message)
        }
        if rule.type == "regex", !matchesDeclared(rule.value.text, text) {
            return FlowVariableValidationError(code: .pattern, message: rule.message)
        }
    }
    return nil
}

/// A pattern the flow declares. One that cannot be compiled is the server's to judge, so it passes here.
private func matchesDeclared(_ pattern: String, _ text: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return true }
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}
