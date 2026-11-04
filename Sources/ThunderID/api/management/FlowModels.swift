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

/// A flow with its graph.
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
