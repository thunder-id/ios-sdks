// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// How an operation that changes state is carried out.
public enum AdministrationMode: String, Codable, CaseIterable {
    /// Run the administration flow the server configures for the operation, which handles the runtime
    /// side first (for example revoking tokens and ending sessions) and then changes the record. When no
    /// flow is configured for the operation, the management API is called directly. Reading that
    /// configuration needs a token that may read server configuration.
    case flow
    /// Call the management API directly, with no flow. The default.
    case native
}

/// Keys of the `flow` server-config section that name the administration flow for each operation. An
/// unset key is the opt-out: the operation calls the management API directly.
public enum AdministrationFlowConfigKey: String, Codable, CaseIterable {
    case actionDeletion = "actionDeletionFlow"
    case agentSuspend = "agentSuspendFlow"
    case agentUnlock = "agentUnlockFlow"
    case agentUnsuspend = "agentUnsuspendFlow"
    case applicationDeletion = "applicationDeletionFlow"
    case applicationSuspend = "applicationSuspendFlow"
    case applicationUnsuspend = "applicationUnsuspendFlow"
    case groupDeletion = "groupDeletionFlow"
    case groupMembershipRemoval = "groupMembershipRemovalFlow"
    case roleAssignmentRemoval = "roleAssignmentRemovalFlow"
    case roleDeletion = "roleDeletionFlow"
    case rolePermissionRemoval = "rolePermissionRemovalFlow"
    case secretRegeneration = "secretRegenerationFlow"
    case userDeletion = "userDeletionFlow"
    case userSuspend = "userSuspendFlow"
    case userUnlock = "userUnlockFlow"
    case userUnsuspend = "userUnsuspendFlow"
}

/// Names of the inputs an administration flow reads. They avoid the execution request's top-level names
/// so a value cannot land in the wrong place.
public enum AdministrationFlowInput {
    public static let action = "targetActionId"
    public static let application = "targetApplicationId"
    public static let assignee = "targetAssigneeId"
    public static let group = "targetGroupId"
    public static let member = "targetMemberId"
    public static let operatorNote = "operatorNote"
    public static let permissions = "targetPermissions"
    public static let resource = "targetResourceId"
    public static let resourceServer = "targetResourceServerId"
    public static let role = "targetRoleId"
    public static let subject = "subject"
}

/// Keys of the values an administration flow returns. A regenerated client secret is readable only
/// here. `emailSent` is `"false"` when a best-effort email step sent nothing.
public enum AdministrationFlowData {
    public static let clientSecret = "clientSecret"
    public static let emailSent = "emailSent"
}

/// Fixed values of the administration flows.
public enum AdministrationFlowConstants {
    /// Flow type of every administration flow.
    public static let flowType = "ADMINISTRATION"
    /// Page size used when walking the flow listing to find a handle. It matches the server's maximum
    /// page size, so the usual handful of administration flows resolves in one request.
    public static let pageSize = 100
}

/// One entry of the `flow` server-config section, naming the administration flow for an operation.
public struct AdministrationFlowConfig: Codable, Equatable {
    public let defaultHandle: String?
    public let expirySeconds: Int?

    public init(defaultHandle: String? = nil, expirySeconds: Int? = nil) {
        self.defaultHandle = defaultHandle
        self.expirySeconds = expirySeconds
    }

    private enum CodingKeys: String, CodingKey {
        case defaultHandle, expirySeconds
    }

    /// Reads leniently, so an entry of the section that is not a flow entry reads as an unset handle
    /// instead of failing the whole section.
    public init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        defaultHandle = try? container?.decodeIfPresent(String.self, forKey: .defaultHandle)
        expirySeconds = try? container?.decodeIfPresent(Int.self, forKey: .expirySeconds)
    }
}

/// A flow registered on the server, as the flow listing returns it.
public struct ManagedFlow: Codable, Equatable {
    public let id: String
    public let handle: String
    public let flowType: String
    public let name: String?
    public let activeVersion: Int?
    public let isReadOnly: Bool?
    public let createdAt: String?
    public let updatedAt: String?
}

/// A page of flows.
public struct ManagedFlowListResponse: Codable {
    public let totalResults: Int?
    public let startIndex: Int?
    public let count: Int?
    public let flows: [ManagedFlow]
    public let links: [ApiPaginationLink]?
}

/// The server-config read of the `flow` section. The server returns the declarative, writable and
/// merged layers; only the merged one is applied.
struct AdministrationFlowConfigLayers: Decodable {
    let merged: [String: AdministrationFlowConfig]?
}

/// The `POST /flow/execute` response, narrowed to what an administration operation inspects.
struct AdministrationFlowExecutionResponse: Decodable {
    let executionId: String?
    let flowStatus: String?
    let error: FlowError?
    let data: AdministrationFlowExecutionData?

    private enum CodingKeys: String, CodingKey {
        case executionId, flowStatus, error, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        executionId = try? container.decodeIfPresent(String.self, forKey: .executionId)
        flowStatus = try? container.decodeIfPresent(String.self, forKey: .flowStatus)
        error = try? container.decodeIfPresent(FlowError.self, forKey: .error)
        data = try? container.decodeIfPresent(AdministrationFlowExecutionData.self, forKey: .data)
    }
}

/// The `data` of an administration flow execution response.
struct AdministrationFlowExecutionData: Decodable {
    let additionalData: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case additionalData
    }

    /// Keeps the string values and the scalars that read as strings, dropping anything else.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .additionalData)
        additionalData = raw?.compactMapValues { value in
            switch value.value {
            case let text as String: return text
            case let flag as Bool: return String(flag)
            case let number as Int: return String(number)
            case let number as Double: return String(number)
            default: return nil
            }
        }
    }
}

/// The body of `POST /flow/execute` for an administration flow.
struct AdministrationFlowExecutionRequest: Encodable {
    let flowId: String
    let inputs: [String: String]
}
