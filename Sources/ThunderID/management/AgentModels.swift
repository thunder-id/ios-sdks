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

    public init(validityPeriod: Int? = nil) {
        self.validityPeriod = validityPeriod
    }
}

/// An agent registered in ThunderID.
public struct Agent: Codable {
    public let id: String
    public let ouId: String
    public let ouHandle: String?
    public let type: String
    public let name: String
    public let description: String?
    public let logoUrl: String?
    public let owner: String?
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
}

/// The summary of an agent returned in list responses.
public struct BasicAgent: Codable {
    public let id: String
    public let ouId: String
    public let ouHandle: String?
    public let type: String
    public let name: String
    public let description: String?
    public let logoUrl: String?
    public let clientId: String?
    public let isReadOnly: Bool?
}

/// A page of agents.
public struct AgentListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let agents: [BasicAgent]
}

/// The payload used to create an agent.
public struct CreateAgentRequest: Codable {
    public var ouId: String
    public var type: String
    public var name: String
    public var description: String?
    public var logoUrl: String?
    public var owner: String?
    public var attributes: [String: AnyCodable]?
    public var inboundAuthConfig: [AgentInboundAuthConfig]?

    public init(ouId: String, type: String, name: String) {
        self.ouId = ouId
        self.type = type
        self.name = name
    }
}

/// The payload used to update an agent.
public struct UpdateAgentRequest: Codable {
    public var ouId: String?
    public var type: String?
    public var name: String?
    public var description: String?
    public var logoUrl: String?
    public var owner: String?
    public var attributes: [String: AnyCodable]?
    public var allowedUserTypes: [String]?
    public var allowedAgentTypes: [String]?
    public var inboundAuthConfig: [AgentInboundAuthConfig]?
    public var authFlowId: String?
    public var registrationFlowId: String?
    public var isRegistrationFlowEnabled: Bool?

    public init() {}
}
