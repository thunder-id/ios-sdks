// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Drives the ThunderID Flow Execution API for app-native sign-in, sign-up, recovery, and the self-service
/// flows (spec §6.1–6.3).
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

    /// Body of a request that starts a self-service flow. It names the flow by its handle and carries no
    /// user or application ID: the server takes the user from the access token.
    func selfServiceStartBody(handle: String, inputs: [String: String]) -> [String: Any] {
        var body: [String: Any] = [
            "flowType": FlowType.selfService.rawValue,
            "handle": handle,
            "verbose": true
        ]
        if !inputs.isEmpty {
            body["inputs"] = inputs
        }
        return body
    }

    /// Sends one self-service flow step through the authenticated transport, without logging it, since a
    /// step carries the code. An `ERROR` step or a `4xx` is a refusal, raised as `verificationFailed` with a
    /// fixed message and without the response body.
    func executeSelfService(url: URL, body: [String: Any]) async throws -> EmbeddedFlowResponse {
        let (data, response) = try await httpClient.exchange(
            method: "POST",
            url: url,
            body: try JSONSerialization.data(withJSONObject: body)
        )
        guard (200...299).contains(response.statusCode) else {
            throw Self.refusal(status: response.statusCode)
        }
        let step: EmbeddedFlowResponse
        do {
            step = try JSONDecoder().decode(EmbeddedFlowResponse.self, from: data)
        } catch {
            throw ThunderIDError(code: .unknownError, message: "Failed to decode the flow step", underlyingError: error)
        }
        if case .error = step.flowStatus {
            throw Self.verificationRefused
        }
        return step
    }

    static let verificationRefused = ThunderIDError(
        code: .verificationFailed,
        message: "The server refused the verification"
    )

    static func refusal(status: Int) -> ThunderIDError {
        switch status {
        case 400...499:
            return verificationRefused
        case 500...599:
            return ThunderIDError(code: .serverError, message: "Server error: \(status)")
        default:
            return ThunderIDError(code: .unknownError, message: "Unexpected status: \(status)")
        }
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
