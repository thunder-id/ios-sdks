// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Drives the ThunderID Flow Execution API for app-native sign-in, sign-up, and recovery (spec §6.1–6.3).
final class FlowExecutionClient {
    private let httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func initiate(
        applicationId: String,
        flowType: FlowType,
        attestationToken: String? = nil
    ) async throws -> EmbeddedFlowResponse {
        let body: [String: Any] = [
            "applicationId": applicationId,
            "flowType": flowType.rawValue,
            "verbose": true
        ]
        return try await httpClient.post(
            path: "/flow/execute",
            body: body,
            requiresAuth: false,
            headers: attestationTokenHeaders(attestationToken)
        )
    }

    func submit(
        flowId: String,
        actionId: String?,
        inputs: [String: String],
        challengeToken: String?
    ) async throws -> EmbeddedFlowResponse {
        var body = submitBody(flowId: flowId, actionId: actionId, challengeToken: challengeToken)
        body["verbose"] = true
        if !inputs.isEmpty {
            body["inputs"] = inputs
        }
        return try await httpClient.post(path: "/flow/execute", body: body, requiresAuth: false)
    }

    private func attestationTokenHeaders(_ token: String?) -> [String: String] {
        guard let token else { return [:] }
        return ["Attestation-Token": token]
    }

    func submitBody(flowId: String, actionId: String?, challengeToken: String?) -> [String: Any] {
        var body: [String: Any] = ["executionId": flowId]
        if let actionId {
            body["action"] = actionId
        }
        if let token = challengeToken {
            body["challengeToken"] = token
        }
        return body
    }
}
