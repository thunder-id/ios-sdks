// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Inbound authentication configuration of an agent.
public struct AgentInboundAuthConfig: Codable {
    /// Currently always `oauth2`.
    public var type: String
    public var config: OAuth2Config?

    public init(type: String = "oauth2", config: OAuth2Config? = nil) {
        self.type = type
        self.config = config
    }
}

/// Login consent configuration of an agent.
public struct AgentLoginConsentConfig: Codable {
    public var validityPeriod: Int?
    /// Asks for consent on every authorization, even when an earlier consent covers it. The server defaults
    /// it to `true` for a personal agent and to `false` otherwise.
    public var alwaysPrompt: Bool?

    public init(validityPeriod: Int? = nil, alwaysPrompt: Bool? = nil) {
        self.validityPeriod = validityPeriod
        self.alwaysPrompt = alwaysPrompt
    }
}

/// The kind of an agent: a category set when the agent is created and never changed, which can add rules
/// of its own to the agent. `nil` on an agent means an ordinary agent. A kind this SDK does not know keeps
/// its raw value.
public struct AgentKind: RawRepresentable, Codable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// A personal agent: one that acts only for its owner, a user.
    public static let personal = AgentKind(rawValue: "personal-assistant")
}

/// What an agent owner's `id` holds. A type this SDK does not know keeps its raw value.
public struct AgentOwnerIdType: RawRepresentable, Codable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let uuid = AgentOwnerIdType(rawValue: "uuid")
    public static let email = AgentOwnerIdType(rawValue: "email")
    public static let mobile = AgentOwnerIdType(rawValue: "mobile")
}

/// The person accountable for an agent. A local owner is an entity of the same deployment and is named by
/// its entity ID. An owner managed in another identity system is not looked up.
public struct AgentOwner: Codable, Equatable {
    public var id: String
    /// What ``id`` holds. `nil` reads as ``AgentOwnerIdType/uuid``, and a local owner must be one.
    public var idType: AgentOwnerIdType?
    /// Whether the owner is an entity of this deployment. `nil` reads as `true`.
    public var isLocal: Bool?

    public init(id: String, idType: AgentOwnerIdType? = nil, isLocal: Bool? = nil) {
        self.id = id
        self.idType = idType
        self.isLocal = isLocal
    }
}

/// An agent registered in ThunderID.
public struct Agent: Codable {
    public let id: String
    public let ouId: String
    public let ouHandle: String?
    public let type: String
    /// The name the server resolved from the agent type's display attribute. Returned only by reads
    /// made with `include=display`. ``resolvedName`` falls back to the `name` attribute.
    public let display: String?
    public let description: String?
    public let logoUrl: String?
    public let owner: AgentOwner?
    public let clientId: String?
    public let attributes: [String: AnyCodable]?
    public let allowedUserTypes: [String]?
    public let allowedAgentTypes: [String]?
    public let inboundAuthConfig: [AgentInboundAuthConfig]?
    /// Populated only when the agent has an inbound client.
    public let authFlowId: String?
    public let registrationFlowId: String?
    public let isRegistrationFlowEnabled: Bool?
    public let assertion: TokenConfig?
    public let loginConsent: AgentLoginConsentConfig?
    public let isReadOnly: Bool?
    /// The effective access status, set by the server on a read.
    public let status: AccessStatus?
    /// The agent's kind, set when the agent is created and never changed. `nil` for an ordinary agent.
    public let kind: AgentKind?
}

/// The summary of an agent returned in list responses.
public struct BasicAgent: Codable {
    public let id: String
    public let ouId: String
    public let ouHandle: String?
    public let type: String
    /// The name the server resolved from the agent type's display attribute. Returned only by reads
    /// made with `include=display`. ``resolvedName`` falls back to the `name` attribute.
    public let display: String?
    public let description: String?
    public let logoUrl: String?
    public let clientId: String?
    public let attributes: [String: AnyCodable]?
    public let isReadOnly: Bool?
    /// The effective access status, set by the server on a read.
    public let status: AccessStatus?
    /// The agent's kind, set when the agent is created and never changed. `nil` for an ordinary agent.
    public let kind: AgentKind?
}

/// A page of agents.
public struct AgentListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let agents: [BasicAgent]
}

/// The payload used to create an agent. The agent's name is an attribute of its type, so it goes in
/// `attributes["name"]`. Give `ouId`, `projectId` or both: with only `projectId` the agent is created in
/// the project's root organization unit, and with both, `ouId` must be in the project.
public struct CreateAgentRequest: Codable {
    public var ouId: String?
    /// The project the agent belongs to.
    public var projectId: String?
    public var type: String
    public var description: String?
    public var logoUrl: String?
    public var owner: AgentOwner?
    public var attributes: [String: AnyCodable]?
    public var inboundAuthConfig: [AgentInboundAuthConfig]?
    /// The agent's kind, fixed once the agent is created. Leave it `nil` for an ordinary agent. A kind can
    /// add requirements of its own: ``AgentKind/personal`` requires `owner` to name a local user.
    public var kind: AgentKind?

    public init(ouId: String?, type: String, attributes: [String: AnyCodable]? = nil, projectId: String? = nil) {
        self.ouId = ouId
        self.projectId = projectId
        self.type = type
        self.attributes = attributes
    }
}

/// The payload used to update an agent. The agent's name is an attribute of its type, so it goes in
/// `attributes["name"]`.
public struct UpdateAgentRequest: Codable {
    public var ouId: String?
    public var type: String?
    public var description: String?
    public var logoUrl: String?
    public var owner: AgentOwner?
    public var attributes: [String: AnyCodable]?
    public var allowedUserTypes: [String]?
    public var allowedAgentTypes: [String]?
    public var inboundAuthConfig: [AgentInboundAuthConfig]?
    public var authFlowId: String?
    public var registrationFlowId: String?
    public var isRegistrationFlowEnabled: Bool?
    public var assertion: TokenConfig?
    public var loginConsent: AgentLoginConsentConfig?
    /// Whether the agent acts on behalf of a signed-in user. The server does not store it, so a full
    /// update sends it for the agent to be held to the delegated grant rules.
    /// ``DelegationGrantTypes/isDelegated(_:)`` derives it from the agent's grant types.
    public var delegated: Bool?

    public init() {}
}

/// The result of ``AgentsAPI/regenerateSecret(id:fetcher:)``.
public struct RegenerateAgentSecretResult {
    /// The agent after the change.
    public let agent: Agent
    /// The new client secret. This is the only time it can be read.
    public let clientSecret: String
}

/// A page of the roles assigned to an agent, by name.
public struct AgentRoleListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let roles: [String]
}

/// A type an agent can be registered as.
public struct AgentType: Codable {
    public let id: String
    public let handle: String
    public let displayName: String
    public let ouId: String
    public let ouHandle: String?
    public let allowSelfRegistration: Bool?
}

/// A page of agent types.
public struct AgentTypeListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let types: [AgentType]
}

/// The part of a personal agent its owner may change, sent whole: an update replaces `attributes`,
/// `grantTypes` and `redirectUris`, and clears a `description` left out.
/// ``PersonalAgentFormValues/updateRequest(for:)`` builds one from an edit form.
public struct UpdateMeAgentRequest: Codable {
    /// The agent's attributes, as its agent type defines them, including `name`.
    public var attributes: [String: AnyCodable]
    public var description: String?
    /// A subset of ``PersonalAgentGrantTypes/all``. An empty list removes every grant.
    public var grantTypes: [String]
    /// At least one when `grantTypes` holds the authorization code grant.
    public var redirectUris: [String]

    public init(
        attributes: [String: AnyCodable],
        description: String? = nil,
        grantTypes: [String],
        redirectUris: [String]
    ) {
        self.attributes = attributes
        self.description = description
        self.grantTypes = grantTypes
        self.redirectUris = redirectUris
    }

    /// Always sends the three lists, even empty: the server requires them.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(attributes, forKey: .attributes)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(grantTypes, forKey: .grantTypes)
        try container.encode(redirectUris, forKey: .redirectUris)
    }
}

/// The result of ``ThunderIDClient/suspendAllMeAgents()``.
public struct SuspendAllMeAgentsResponse: Codable, Equatable {
    /// How many agents the request suspended. Agents the owner had already suspended are not counted.
    public let suspendedCount: Int

    public init(suspendedCount: Int) {
        self.suspendedCount = suspendedCount
    }
}
