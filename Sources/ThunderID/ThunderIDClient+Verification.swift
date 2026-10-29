// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - Self user attribute verification

public extension ThunderIDClient {
    /// Starts verifying one of the signed-in user's attributes, such as `email`, by running a `SELF_SERVICE`
    /// flow. The flow sends a code or a link to the attribute's stored value and returns the step to render;
    /// continue it with ``verifyAttribute(payload:)``. `COMPLETE` means the server recorded the
    /// verification, so read the profile again to see it.
    ///
    /// The request goes to `{baseUrl}/flow/execute` with the access token, which is how the server knows the
    /// user. It sends no user or application ID.
    ///
    /// - Parameters:
    ///   - attribute: The attribute to verify, such as `email` or `mobile_number`.
    ///   - handle: Handle of the `SELF_SERVICE` flow to run.
    /// - Throws: `invalidInput` before any request when `attribute` or `handle` is empty;
    ///   `verificationFailed` when the server refuses it (an `ERROR` step or an HTTP 4xx), without the
    ///   response body.
    func verifyAttribute(
        _ attribute: String,
        handle: String = AttributeVerification.defaultFlowHandle
    ) async throws -> EmbeddedFlowResponse {
        _ = try requireConfig()
        guard !handle.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ThunderIDError(code: .invalidInput, message: "A new self-service flow needs a flow handle")
        }
        guard !attribute.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ThunderIDError(code: .invalidInput, message: "The attribute to verify is required")
        }
        let (flowClient, url) = try selfServiceTransport()
        let body = flowClient.selfServiceStartBody(
            handle: handle,
            inputs: [AttributeVerification.attributeInput: attribute]
        )
        return try await flowClient.executeSelfService(url: url, body: body)
    }

    /// Continues a verification started with ``verifyAttribute(_:handle:)``: submits the step's action and
    /// inputs, such as the code the user received, under the execution's `flowId` and challenge token. A
    /// resend submits its action with no inputs.
    ///
    /// - Throws: `invalidInput` before any request when `payload` has no `flowId`, since a new flow must
    ///   be started by its handle; `verificationFailed` when the server refuses it, as for the start.
    func verifyAttribute(payload: EmbeddedSignInPayload) async throws -> EmbeddedFlowResponse {
        _ = try requireConfig()
        guard let flowId = payload.flowId, !flowId.isEmpty else {
            throw ThunderIDError(
                code: .invalidInput,
                message: "A new self-service flow needs a flow handle; start it with verifyAttribute(_:)"
            )
        }
        let (flowClient, url) = try selfServiceTransport()
        var body = flowClient.submitBody(
            flowId: flowId,
            actionId: payload.actionId,
            challengeToken: payload.challengeToken
        )
        body["verbose"] = true
        if !payload.inputs.isEmpty {
            body["inputs"] = payload.inputs
        }
        return try await flowClient.executeSelfService(url: url, body: body)
    }
}

extension ThunderIDClient {
    /// The flow client and `{baseUrl}/flow/execute`, where every embedded flow goes.
    private func selfServiceTransport() throws -> (FlowExecutionClient, URL) {
        guard let flowClient, let httpClient else {
            throw ThunderIDError(code: .sdkNotInitialized, message: "Call initialize() before using the SDK")
        }
        guard let url = httpClient.url(forPath: "/flow/execute") else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Invalid flow execution URL")
        }
        return (flowClient, url)
    }
}
