/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import Foundation

public struct User: Codable {
    public let sub: String
    public let username: String?
    public let email: String?
    public let displayName: String?
    public let profilePicture: String?
    public let isNewUser: Bool?
    public let claims: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sub, username, email, isNewUser, claims
        case displayName = "displayName"
        case profilePicture = "picture"
    }

    public init(
        sub: String,
        username: String? = nil,
        email: String? = nil,
        displayName: String? = nil,
        profilePicture: String? = nil,
        isNewUser: Bool? = nil,
        claims: [String: AnyCodable]? = nil
    ) {
        self.sub = sub
        self.username = username
        self.email = email
        self.displayName = displayName
        self.profilePicture = profilePicture
        self.isNewUser = isNewUser
        self.claims = claims
    }
}

public struct UserProfile: Codable {
    public let id: String
    public let claims: [String: AnyCodable]

    public init(id: String, claims: [String: AnyCodable]) {
        self.id = id
        self.claims = claims
    }
}

public struct TokenResponse: Codable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int?
    public let refreshToken: String?
    public let idToken: String?
    public let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case scope
    }

    public init(
        accessToken: String,
        tokenType: String,
        expiresIn: Int? = nil,
        refreshToken: String? = nil,
        idToken: String? = nil,
        scope: String? = nil
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.scope = scope
    }
}

public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let val = try? container.decode(String.self) {
            value = val
        } else if let val = try? container.decode(Bool.self) {
            value = val
        } else if let val = try? container.decode(Int.self) {
            value = val
        } else if let val = try? container.decode(Double.self) {
            value = val
        } else if let val = try? container.decode([String: AnyCodable].self) {
            value = val
        } else if let val = try? container.decode([AnyCodable].self) {
            value = val
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let val as String: try container.encode(val)
        case let val as Bool: try container.encode(val)
        case let val as Int: try container.encode(val)
        case let val as Double: try container.encode(val)
        case let val as [String: AnyCodable]: try container.encode(val)
        case let val as [AnyCodable]: try container.encode(val)
        default: try container.encodeNil()
        }
    }
}

public struct SignInOptions {
    public var prompt: String?
    public var loginHint: String?
    public var fidp: String?
    public var extra: [String: Any]

    public init(
        prompt: String? = nil,
        loginHint: String? = nil,
        fidp: String? = nil,
        extra: [String: Any] = [:]
    ) {
        self.prompt = prompt
        self.loginHint = loginHint
        self.fidp = fidp
        self.extra = extra
    }
}

public struct SignUpOptions {
    public var appId: String?
    public var extra: [String: Any]

    public init(appId: String? = nil, extra: [String: Any] = [:]) {
        self.appId = appId
        self.extra = extra
    }
}

public struct SignOutOptions {
    public var idTokenHint: String?
    public var extra: [String: Any]

    public init(idTokenHint: String? = nil, extra: [String: Any] = [:]) {
        self.idTokenHint = idTokenHint
        self.extra = extra
    }
}

public struct TokenExchangeRequestConfig {
    public var subjectToken: String
    public var subjectTokenType: String
    public var requestedTokenType: String?
    public var audience: String?

    public init(
        subjectToken: String,
        subjectTokenType: String,
        requestedTokenType: String? = nil,
        audience: String? = nil
    ) {
        self.subjectToken = subjectToken
        self.subjectTokenType = subjectTokenType
        self.requestedTokenType = requestedTokenType
        self.audience = audience
    }
}

/// Payload for app-native (embedded) sign-in via the Flow Execution API.
public struct EmbeddedSignInPayload {
    public var flowId: String?
    public var actionId: String
    public var inputs: [String: String]
    public var challengeToken: String?

    public init(
        flowId: String? = nil,
        actionId: String,
        inputs: [String: String] = [:],
        challengeToken: String? = nil
    ) {
        self.flowId = flowId
        self.actionId = actionId
        self.inputs = inputs
        self.challengeToken = challengeToken
    }
}

public struct EmbeddedFlowRequestConfig {
    public var applicationId: String
    public var flowType: FlowType

    public init(applicationId: String, flowType: FlowType = .authentication) {
        self.applicationId = applicationId
        self.flowType = flowType
    }
}

public enum FlowType: String {
    case authentication = "AUTHENTICATION"
    case registration = "REGISTRATION"
    case passwordRecovery = "PASSWORD_RECOVERY"
    case invitedUserRegistration = "INVITED_USER_REGISTRATION"
}

public struct EmbeddedFlowResponse: Decodable {
    public let flowId: String?
    public let flowStatus: FlowStatus
    public let stepId: String?
    public let type: String?
    public let data: FlowStepData?
    public let assertion: String?
    public let failureReason: String?
    public let challengeToken: String?

    enum CodingKeys: String, CodingKey {
        case flowId = "executionId"
        case flowStatus, stepId, type, data, assertion, failureReason, challengeToken
    }
}

public enum FlowStatus: Codable {
    case promptOnly
    case complete
    case error

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.uppercased() ?? ""
        switch raw {
        case "COMPLETE":
            self = .complete
        case "ERROR":
            self = .error
        case "PROMPT_ONLY", "INCOMPLETE", "PENDING", "VIEW":
            self = .promptOnly
        default:
            self = .promptOnly
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .promptOnly:
            try container.encode("PROMPT_ONLY")
        case .complete:
            try container.encode("COMPLETE")
        case .error:
            try container.encode("ERROR")
        }
    }
}

public struct FlowStepData: Decodable {
    public let actions: [FlowAction]?
    public let inputs: [FlowInput]?
    public let meta: FlowMeta?
    public let redirectURL: String?
    public let additionalData: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case actions, inputs, meta, additionalData, redirectURL
    }
}

/// A single node in the recursive component tree returned under `data.meta.components`.
/// Carries the presentation metadata (label, placeholder, variant, icon, ...) that the flat
/// `actions`/`inputs` arrays omit.
public struct FlowComponent: Decodable {
    public let id: String?
    public let ref: String?
    public let type: String?
    public let category: String?
    public let label: String?
    public let placeholder: String?
    public let variant: String?
    public let eventType: String?
    public let align: String?
    public let icon: String?
    public let components: [FlowComponent]?

    enum CodingKeys: String, CodingKey {
        case id, ref, type, category, label, placeholder, variant, eventType, align, components
        case icon = "image"
        case startIcon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try? container.decode(String.self, forKey: .id)
        self.ref = try? container.decode(String.self, forKey: .ref)
        self.type = try? container.decode(String.self, forKey: .type)
        self.category = try? container.decode(String.self, forKey: .category)
        self.label = try? container.decode(String.self, forKey: .label)
        self.placeholder = try? container.decode(String.self, forKey: .placeholder)
        self.variant = try? container.decode(String.self, forKey: .variant)
        self.eventType = try? container.decode(String.self, forKey: .eventType)
        self.align = try? container.decode(String.self, forKey: .align)
        self.icon =
            (try? container.decode(String.self, forKey: .icon)) ??
            (try? container.decode(String.self, forKey: .startIcon))
        self.components = try? container.decode([FlowComponent].self, forKey: .components)
    }
}

/// The parsed `data.meta` payload of a Flow Execution API step response.
public struct FlowMeta: Decodable {
    public let components: [FlowComponent]?
}

public struct FlowAction: Decodable {
    public let id: String
    public let ref: String?
    public let nextNode: String?
    public let type: String?
    public let label: String?
    public let eventType: String?
    public let variant: String?
    public let icon: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case label
        case ref
        case nextNode
        case eventType
        case variant
        case icon = "image"
        case startIcon
    }

    public init(
        id: String,
        ref: String? = nil,
        nextNode: String? = nil,
        type: String? = nil,
        label: String? = nil,
        eventType: String? = nil,
        variant: String? = nil,
        icon: String? = nil
    ) {
        self.id = id
        self.ref = ref
        self.nextNode = nextNode
        self.type = type
        self.label = label
        self.eventType = eventType
        self.variant = variant
        self.icon = icon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id =
            (try? container.decode(String.self, forKey: .id)) ??
            (try? container.decode(String.self, forKey: .ref)) ??
            (try? container.decode(String.self, forKey: .nextNode)) ??
            "submit"
        self.ref = try? container.decode(String.self, forKey: .ref)
        self.nextNode = try? container.decode(String.self, forKey: .nextNode)
        self.type = try? container.decode(String.self, forKey: .type)
        self.label = try? container.decode(String.self, forKey: .label)
        self.eventType = try? container.decode(String.self, forKey: .eventType)
        self.variant = try? container.decode(String.self, forKey: .variant)
        self.icon =
            (try? container.decode(String.self, forKey: .icon)) ??
            (try? container.decode(String.self, forKey: .startIcon))
    }

    /// Returns a copy with any `nil` presentation fields filled in from `component`.
    /// Explicit flat-array values always win over the component tree's values.
    public func merging(component: FlowComponent) -> FlowAction {
        FlowAction(
            id: id,
            ref: ref,
            nextNode: nextNode,
            type: type,
            label: label ?? component.label,
            eventType: eventType ?? component.eventType,
            variant: variant ?? component.variant,
            icon: icon ?? component.icon
        )
    }
}

public struct FlowInput: Decodable, Identifiable {
    public var id: String { name }
    public let name: String
    public let type: String?
    public let required: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case identifier
        case ref
        case type
        case required
    }

    public init(name: String, type: String? = nil, required: Bool? = nil) {
        self.name = name
        self.type = type
        self.required = required
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name =
            (try? container.decode(String.self, forKey: .name)) ??
            (try? container.decode(String.self, forKey: .identifier)) ??
            (try? container.decode(String.self, forKey: .ref)) ??
            "input"
        self.type = try? container.decode(String.self, forKey: .type)
        self.required = try? container.decode(Bool.self, forKey: .required)
    }
}
