// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The value of a flow variable: a string, a number or a boolean.
public enum FlowVariableValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)

    /// Reads a value the server sent as JSON. Returns `nil` for anything but a string, a number or a boolean.
    public init?(_ value: AnyCodable) {
        switch value.value {
        case let text as String: self = .string(text)
        case let flag as Bool: self = .bool(flag)
        case let number as Int: self = .number(Double(number))
        case let number as Double: self = .number(number)
        default: return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
        } else {
            self = .number(try container.decode(Double.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let text): try container.encode(text)
        case .bool(let flag): try container.encode(flag)
        case .number(let number): try container.encode(number)
        }
    }

    /// The value as text: a whole number without a fraction, a boolean as `true` or `false`.
    public var text: String {
        switch self {
        case .string(let text): return text
        case .bool(let flag): return flag ? "true" : "false"
        case .number(let number):
            if number.rounded() == number, abs(number) < 1e15 { return String(Int(number)) }
            return String(number)
        }
    }

    var isBool: Bool {
        if case .bool = self { return true }
        return false
    }

    var isString: Bool {
        if case .string = self { return true }
        return false
    }

    /// The value as JSON, a whole number as an integer.
    public var anyCodable: AnyCodable {
        switch self {
        case .string(let text): return AnyCodable(text)
        case .bool(let flag): return AnyCodable(flag)
        case .number(let number):
            if number.rounded() == number, abs(number) < 1e15 { return AnyCodable(Int(number)) }
            return AnyCodable(number)
        }
    }
}

/// The values an organization unit has set for a flow's variables, keyed by identifier. A variable it has
/// not set is absent.
public typealias FlowVariableValues = [String: FlowVariableValue]

/// The input a flow variable is edited with. A type the SDK does not know is kept as the server sent it.
public struct FlowVariableType: RawRepresentable, Codable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let textInput = FlowVariableType(rawValue: "TEXT_INPUT")
    public static let emailInput = FlowVariableType(rawValue: "EMAIL_INPUT")
    public static let phoneInput = FlowVariableType(rawValue: "PHONE_INPUT")
    public static let numberInput = FlowVariableType(rawValue: "NUMBER_INPUT")
    public static let dateInput = FlowVariableType(rawValue: "DATE_INPUT")
    public static let booleanInput = FlowVariableType(rawValue: "BOOLEAN_INPUT")
    public static let select = FlowVariableType(rawValue: "SELECT")
    public static let connectionSelect = FlowVariableType(rawValue: "CONNECTION_SELECT")
}

/// A rule a text value has to meet.
public struct FlowVariableValidationRule: Codable, Equatable {
    /// `regex`, `minLength` or `maxLength`.
    public let type: String
    public let value: FlowVariableValue
    /// The message shown when the rule fails, as the flow declares it.
    public let message: String?

    public init(type: String, value: FlowVariableValue, message: String? = nil) {
        self.type = type
        self.value = value
        self.message = message
    }
}

/// A variable a flow declares on its `VARIABLES` node.
public struct FlowVariableDefinition: Codable, Equatable {
    /// Name of the variable, which a `{{var(name)}}` placeholder uses.
    public let identifier: String
    public let type: FlowVariableType
    public let label: String?
    public let description: String?
    /// The value the variable has until another is set.
    public let defaultValue: FlowVariableValue?
    /// For a `SELECT`: the values it can take.
    public let options: [FlowVariableValue]?
    /// For a `NUMBER_INPUT`: the lowest value.
    public let min: Double?
    /// For a `NUMBER_INPUT`: the highest value.
    public let max: Double?
    /// For a `CONNECTION_SELECT`: the kind of connection it takes, such as `IDENTITY_PROVIDER`.
    public let category: String?
    /// For a `CONNECTION_SELECT`: limits it to these vendors, such as `google`.
    public let connectionTypes: [String]?
    public let validation: [FlowVariableValidationRule]?

    public init(
        identifier: String,
        type: FlowVariableType,
        label: String? = nil,
        description: String? = nil,
        defaultValue: FlowVariableValue? = nil,
        options: [FlowVariableValue]? = nil,
        min: Double? = nil,
        max: Double? = nil,
        category: String? = nil,
        connectionTypes: [String]? = nil,
        validation: [FlowVariableValidationRule]? = nil
    ) {
        self.identifier = identifier
        self.type = type
        self.label = label
        self.description = description
        self.defaultValue = defaultValue
        self.options = options
        self.min = min
        self.max = max
        self.category = category
        self.connectionTypes = connectionTypes
        self.validation = validation
    }
}

/// Why a value does not fit its variable. `message` is set when the variable's own rule supplies the text.
public struct FlowVariableValidationError: Equatable {
    public enum Code: String {
        case invalid
        case max
        case maxLength = "max_length"
        case min
        case minLength = "min_length"
        case notOption = "not_option"
        case pattern
        case required
    }

    public let code: Code
    public let message: String?

    public init(code: Code, message: String? = nil) {
        self.code = code
        self.message = message
    }
}

/// A choice of a `SELECT` or `CONNECTION_SELECT` variable.
public struct FlowVariableOption: Hashable {
    public let label: String
    /// The value to store: the option itself, or the connection's identifier.
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// Narrows what a unit may choose from, as a sharing policy decides.
public struct FlowVariableOptionRestriction: Equatable {
    /// The only values the unit may choose. `nil` means any.
    public let allowedValues: [String]?
    /// Values taken out of what the unit may choose.
    public let excludedValues: [String]?

    public init(allowedValues: [String]? = nil, excludedValues: [String]? = nil) {
        self.allowedValues = allowedValues
        self.excludedValues = excludedValues
    }
}

/// What an organization unit may do with one variable, after the sharing policies that reach it are applied.
public struct ResolvedFlowVariableRule: Equatable {
    /// The values the unit may choose from. `nil` means anything the variable accepts.
    public let allowedValues: [String]?
    /// The value the variable has until the unit sets its own, or the value it is pinned to when it cannot set one.
    public let defaultValue: FlowVariableValue?
    /// Whether the unit may set its own value.
    public let editable: Bool
    /// Values taken out of what the unit may choose.
    public let excludedValues: [String]?

    public init(
        allowedValues: [String]? = nil,
        defaultValue: FlowVariableValue? = nil,
        editable: Bool,
        excludedValues: [String]? = nil
    ) {
        self.allowedValues = allowedValues
        self.defaultValue = defaultValue
        self.editable = editable
        self.excludedValues = excludedValues
    }
}

public extension FlowVariablesResponse {
    /// ``values`` as typed values. An entry that is not a string, a number or a boolean is left out.
    var variableValues: FlowVariableValues {
        values.compactMapValues(FlowVariableValue.init)
    }
}

public extension FlowVariablesRequest {
    /// Sets `variables` for `ouId`, each a string, a number or a boolean.
    init(ouId: String, variables: FlowVariableValues) {
        self.init(ouId: ouId, values: variables.mapValues(\.anyCodable))
    }
}
