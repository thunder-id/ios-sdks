// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// How a resource server's permissions are decided.
public struct AuthorizationEngineConfig: Codable, Equatable {
    /// `rbac` or `authzen_pdp`.
    public var type: String?
    /// For `authzen_pdp`, the `pdpConnectionId` of the AuthZEN PDP connection.
    public var properties: [String: String]?

    public init(type: String? = nil, properties: [String: String]? = nil) {
        self.type = type
        self.properties = properties
    }
}

/// A resource server: an API, an MCP server or a custom server whose resources and actions define
/// permissions.
public struct ResourceServer: Codable {
    public let id: String
    public let name: String
    public let description: String?
    public let identifier: String
    /// `API`, `MCP` or `CUSTOM`.
    public let type: String
    public let ouId: String
    /// The character joining the parts of a permission, such as `:`.
    public let delimiter: String
    public let authorizationEngine: AuthorizationEngineConfig?
    public let isReadOnly: Bool?
}

/// A page of resource servers.
public struct ResourceServerListResponse: Codable {
    public let totalResults: Int?
    public let startIndex: Int?
    public let count: Int?
    public let resourceServers: [ResourceServer]
    public let links: [ApiPaginationLink]?
}

/// The payload used to create a resource server.
public struct CreateResourceServerRequest: Codable {
    public var name: String
    public var description: String?
    public var identifier: String
    /// `API`, `MCP` or `CUSTOM`.
    public var type: String?
    public var ouId: String
    public var delimiter: String?

    public init(
        name: String,
        identifier: String,
        ouId: String,
        description: String? = nil,
        type: String? = nil,
        delimiter: String? = nil
    ) {
        self.name = name
        self.identifier = identifier
        self.ouId = ouId
        self.description = description
        self.type = type
        self.delimiter = delimiter
    }
}

/// The payload used to update a resource server.
public struct UpdateResourceServerRequest: Codable {
    public var name: String
    public var description: String?
    public var identifier: String?
    public var ouId: String
    public var authorizationEngine: AuthorizationEngineConfig?

    public init(
        name: String,
        ouId: String,
        description: String? = nil,
        identifier: String? = nil,
        authorizationEngine: AuthorizationEngineConfig? = nil
    ) {
        self.name = name
        self.ouId = ouId
        self.description = description
        self.identifier = identifier
        self.authorizationEngine = authorizationEngine
    }
}

/// A resource of a resource server.
public struct ServerResource: Codable {
    public let id: String
    public let name: String
    public let handle: String
    public let description: String?
    /// The parent resource's identifier, or `nil` at the top level.
    public let parent: String?
    /// The permission the resource defines.
    public let permission: String
}

/// A page of resources.
public struct ServerResourceListResponse: Codable {
    public let totalResults: Int?
    public let startIndex: Int?
    public let count: Int?
    public let resources: [ServerResource]
    public let links: [ApiPaginationLink]?
}

/// The payload used to create a resource.
public struct CreateServerResourceRequest: Codable {
    public var name: String
    public var handle: String
    public var description: String?
    public var parent: String?

    public init(name: String, handle: String, description: String? = nil, parent: String? = nil) {
        self.name = name
        self.handle = handle
        self.description = description
        self.parent = parent
    }
}

/// The payload used to update a resource or an action.
public struct UpdateNamedItemRequest: Codable {
    public var name: String?
    public var description: String?

    public init(name: String? = nil, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

/// An action on a resource server or on one of its resources.
public struct ResourceAction: Codable {
    public let id: String
    public let name: String
    public let handle: String
    public let description: String?
    /// The permission the action defines.
    public let permission: String
    /// `tool` or `resource`.
    public let kind: String?
}

/// A page of actions.
public struct ResourceActionListResponse: Codable {
    public let totalResults: Int?
    public let startIndex: Int?
    public let count: Int?
    public let actions: [ResourceAction]
    public let links: [ApiPaginationLink]?
}

/// The payload used to create an action.
public struct CreateResourceActionRequest: Codable {
    public var name: String
    public var handle: String
    public var description: String?
    /// `tool` or `resource`.
    public var kind: String?

    public init(name: String, handle: String, description: String? = nil, kind: String? = nil) {
        self.name = name
        self.handle = handle
        self.description = description
        self.kind = kind
    }
}
