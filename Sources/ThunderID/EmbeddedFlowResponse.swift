// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct EmbeddedFlowResponse: Decodable {
    public let flowId: String?
    public let flowStatus: FlowStatus
    public let stepId: String?
    public let type: String?
    public let data: FlowStepData?
    public let assertion: String?
    public let failureReason: String?
    public let challengeToken: String?
    /// The server's structured error. Its default text is also copied into `failureReason`.
    public let error: FlowError?
    /// The SSO sessions this step started. The client keeps them to present on later flows.
    public let sessionData: [EmbeddedFlowSessionData]?
    /// The flow identifiers of the SSO sessions this step ended.
    public let clearedSessions: [String]?

    enum CodingKeys: String, CodingKey {
        case flowId = "executionId"
        case flowStatus, stepId, type, data, assertion, failureReason, challengeToken, error
        case sessionData, clearedSessions
    }
}

/// An SSO session an app-native flow step started. Presented on a later flow, it lets the server sign the
/// user in silently. The handle is a credential: it is never logged.
public struct EmbeddedFlowSessionData: Codable, Equatable {
    /// Identifies the flow the session belongs to.
    public let flowIdentifier: String
    public let sessionHandle: String
    /// Seconds until the session ends, when the server says.
    public let expiresIn: Int?

    public init(flowIdentifier: String, sessionHandle: String, expiresIn: Int? = nil) {
        self.flowIdentifier = flowIdentifier
        self.sessionHandle = sessionHandle
        self.expiresIn = expiresIn
    }
}

/// The flow execution `error` object, which replaced `failureReason`.
/// Administration flows report a refused step with the same object (``ThunderIDError/flowError``).
public struct FlowError: Decodable, Equatable {
    public let code: String?
    public let message: FlowErrorText?
    public let description: FlowErrorText?

    public init(code: String? = nil, message: FlowErrorText? = nil, description: FlowErrorText? = nil) {
        self.code = code
        self.message = message
        self.description = description
    }
}

public struct FlowErrorText: Decodable, Equatable {
    public let key: String?
    /// The untranslated text, with `params` already substituted.
    public let defaultValue: String?
    /// Values for the `{{param(name)}}` placeholders a translation of `key` keeps.
    public let params: [String: String]?

    public init(key: String? = nil, defaultValue: String? = nil, params: [String: String]? = nil) {
        self.key = key
        self.defaultValue = defaultValue
        self.params = params
    }
}

extension EmbeddedFlowResponse {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        flowId = try container.decodeIfPresent(String.self, forKey: .flowId)
        flowStatus = try container.decode(FlowStatus.self, forKey: .flowStatus)
        stepId = try container.decodeIfPresent(String.self, forKey: .stepId)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        data = try container.decodeIfPresent(FlowStepData.self, forKey: .data)
        assertion = try container.decodeIfPresent(String.self, forKey: .assertion)
        challengeToken = try container.decodeIfPresent(String.self, forKey: .challengeToken)
        error = try? container.decodeIfPresent(FlowError.self, forKey: .error)
        sessionData = try? container.decodeIfPresent([EmbeddedFlowSessionData].self, forKey: .sessionData)
        clearedSessions = try? container.decodeIfPresent([String].self, forKey: .clearedSessions)
        failureReason = try error?.message?.defaultValue ?? error?.description?.defaultValue
            ?? container.decodeIfPresent(String.self, forKey: .failureReason)
    }
}
