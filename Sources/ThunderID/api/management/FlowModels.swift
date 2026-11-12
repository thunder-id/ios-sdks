// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One node of a flow graph. `id` and `type` (`START`, `PROMPT`, `TASK_EXECUTION`, `CALL` or `END`) are
/// named; the rest of the node (`layout`, `meta`, `prompts`, `executor`, `onSuccess`, `next` and so on)
/// is kept as JSON in ``fields``, so a flow read and saved back loses nothing the server stored.
public struct FlowNode: Codable {
    public var id: String
    public var type: String
    /// The node's other fields, keyed by name.
    public var fields: [String: AnyCodable]

    public init(id: String, type: String, fields: [String: AnyCodable] = [:]) {
        self.id = id
        self.type = type
        self.fields = fields
    }

    private enum CodingKeys: String, CodingKey {
        case id, type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        fields = try decoder.remainingFields(excluding: ["id", "type"])
    }

    public func encode(to encoder: Encoder) throws {
        try encoder.encodeFields(fields, excluding: ["id", "type"])
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
    }
}

/// The payload used to create or update a flow.
public struct FlowDefinitionRequest: Codable {
    public var name: String
    public var handle: String
    /// `AUTHENTICATION` or `REGISTRATION`.
    public var flowType: String
    public var nodes: [FlowNode]

    public init(name: String, handle: String, flowType: String, nodes: [FlowNode]) {
        self.name = name
        self.handle = handle
        self.flowType = flowType
        self.nodes = nodes
    }
}

/// A flow with its graph. Requested for an organization unit the flow is shared with, it comes back as its
/// ``variables`` only, and ``nodes`` is empty.
public struct FlowDefinition: Codable {
    public let id: String
    public let name: String
    public let handle: String
    public let flowType: String
    public let activeVersion: Int?
    public let isReadOnly: Bool?
    public let nodes: [FlowNode]
    public let createdAt: String?
    public let updatedAt: String?
    /// The organization unit the flow was requested for.
    public let ouId: String?
    /// Whether the organization unit the flow was requested for owns it.
    public let isOwnedByOU: Bool?
    /// Set on a flow shared with the requested organization unit. A flow the unit owns declares its
    /// variables on its `VARIABLES` node instead; ``getFlowVariableDefinitions(_:)`` reads either.
    public let variables: [FlowVariableDefinition]?
}

extension FlowDefinition {
    private enum CodingKeys: String, CodingKey {
        case id, name, handle, flowType, activeVersion, isReadOnly, nodes, createdAt, updatedAt
        case ouId, isOwnedByOU, variables
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        handle = try container.decode(String.self, forKey: .handle)
        flowType = try container.decode(String.self, forKey: .flowType)
        activeVersion = try container.decodeIfPresent(Int.self, forKey: .activeVersion)
        isReadOnly = try container.decodeIfPresent(Bool.self, forKey: .isReadOnly)
        nodes = try container.decodeIfPresent([FlowNode].self, forKey: .nodes) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        ouId = try container.decodeIfPresent(String.self, forKey: .ouId)
        isOwnedByOU = try container.decodeIfPresent(Bool.self, forKey: .isOwnedByOU)
        variables = try container.decodeIfPresent([FlowVariableDefinition].self, forKey: .variables)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(handle, forKey: .handle)
        try container.encode(flowType, forKey: .flowType)
        try container.encodeIfPresent(activeVersion, forKey: .activeVersion)
        try container.encodeIfPresent(isReadOnly, forKey: .isReadOnly)
        try container.encode(nodes, forKey: .nodes)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(ouId, forKey: .ouId)
        try container.encodeIfPresent(isOwnedByOU, forKey: .isOwnedByOU)
        try container.encodeIfPresent(variables, forKey: .variables)
    }
}

/// One saved version of a flow.
public struct FlowVersionInfo: Codable, Equatable {
    public let version: Int
    public let createdAt: String
    public let isActive: Bool
}

/// The saved versions of a flow.
public struct FlowVersionListResponse: Codable {
    public let totalVersions: Int?
    public let versions: [FlowVersionInfo]
}

/// One saved version of a flow, with its graph.
public struct FlowVersion: Codable {
    public let id: String
    public let name: String
    public let handle: String
    public let flowType: String
    public let version: Int
    public let isActive: Bool
    public let nodes: [FlowNode]
    public let createdAt: String?
}
