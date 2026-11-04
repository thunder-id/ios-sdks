// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A resource that references another one, such as an application that uses a theme, and what
/// happens to it when the referenced resource is deleted.
public struct ResourceUsage: Codable, Equatable {
    /// The kind of resource, such as `application`, `agent` or `flow`.
    public let resourceType: String
    public let id: String
    public let displayName: String
    /// `fallback`, `cascade` or `restrict`.
    public let behaviorOnDelete: String
}

/// The resources that reference a flow, a theme, a layout or a connection.
public struct ResourceUsagesResponse: Codable {
    public let totalResults: Int?
    public let count: Int?
    /// The number of usages of each resource type.
    public let summary: [String: Int]?
    public let usages: [ResourceUsage]?
}

/// The result of an account lifecycle operation, such as suspending a user.
public struct AccountLifecycleResult: Equatable {
    /// Whether the flow's notification email went out: `false` when a best-effort email step sent
    /// nothing, and `nil` when the flow has no email step.
    public let emailSent: Bool?

    public init(emailSent: Bool?) {
        self.emailSent = emailSent
    }
}

/// A JSON key for a field the SDK does not name, used to keep the fields of open objects.
struct DynamicCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ name: String) { stringValue = name }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Decoder {
    /// Every field of the JSON object except `known`, so a model can keep what it does not name.
    func remainingFields(excluding known: Set<String>) throws -> [String: AnyCodable] {
        let container = try self.container(keyedBy: DynamicCodingKey.self)
        var fields: [String: AnyCodable] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            fields[key.stringValue] = try container.decode(AnyCodable.self, forKey: key)
        }
        return fields
    }
}

extension Encoder {
    /// Writes `fields` beside the named ones, leaving out any whose name is in `known`.
    func encodeFields(_ fields: [String: AnyCodable], excluding known: Set<String>) throws {
        var container = self.container(keyedBy: DynamicCodingKey.self)
        for (name, value) in fields where !known.contains(name) {
            try container.encode(value, forKey: DynamicCodingKey(name))
        }
    }
}

extension ManagementTransport {
    /// Runs a flow-only account lifecycle operation, such as suspending a user. There is no management
    /// API for these, so when no flow is configured it throws
    /// ``ThunderIDErrorCode/administrationFlowNotConfigured`` instead of doing nothing.
    func runLifecycleFlow(
        _ configKey: AdministrationFlowConfigKey,
        subject: String,
        operatorNote: String?,
        action: String,
        fetcher: ThunderIDFetcher?
    ) async throws -> AccountLifecycleResult {
        guard !subject.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ThunderIDError(code: .invalidInput, message: "A resource identifier is required")
        }
        var inputs = [AdministrationFlowInput.subject: subject]
        if let operatorNote, !operatorNote.isEmpty {
            inputs[AdministrationFlowInput.operatorNote] = operatorNote
        }
        guard let produced = try await administrationFlows.run(
            configKey,
            inputs: inputs,
            action: action,
            fetcher: fetcher
        ) else {
            throw ThunderIDError(
                code: .administrationFlowNotConfigured,
                message: "No \(action) flow is configured, and there is no management API for it, so the "
                    + "action was not performed. Set the \(configKey.rawValue) handle in the server configuration."
            )
        }
        let emailSent: Bool?
        switch produced[AdministrationFlowData.emailSent] {
        case "true": emailSent = true
        case "false": emailSent = false
        default: emailSent = nil
        }
        return AccountLifecycleResult(emailSent: emailSent)
    }
}
