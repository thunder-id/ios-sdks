// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A step of the server's `DEVICE_GRANT` flow, as ``ThunderIDClient/verifyDeviceCode(userCode:applicationId:)``
/// returns it.
public struct DeviceCodeVerificationResponse {
    /// The flow step: drive an incomplete one like any app-native flow, with
    /// ``ThunderIDClient/verifyDeviceCode(payload:)``.
    public let flow: EmbeddedFlowResponse
    /// Where the server's OAuth callback points once the flow has ended, approved or denied.
    public let redirectUrl: String?
}

/// Device authorization (RFC 8628), the user side: a signed-in user approves a device from the app by
/// entering the code the device shows. It runs the server's `DEVICE_GRANT` flow in app-native mode.
public extension ThunderIDClient {
    /// Starts the application's `DEVICE_GRANT` flow, submitting `userCode` when the user already typed it.
    /// When the flow ends, the SDK hands its result to the server's OAuth callback, which releases or
    /// denies the waiting device.
    func verifyDeviceCode(userCode: String? = nil, applicationId: String? = nil) async throws
        -> DeviceCodeVerificationResponse {
        let config = try requireConfig()
        try refuseInBackendMode("verifyDeviceCode")
        guard let appId = applicationId ?? config.applicationId, !appId.isEmpty else {
            throw ThunderIDError(code: .invalidConfiguration, message: "applicationId is required for verifyDeviceCode")
        }
        var inputs: [String: String] = [:]
        if let userCode, !userCode.isEmpty { inputs["user_code"] = userCode }
        return try await executeDeviceGrant([
            "applicationId": appId,
            "flowType": "DEVICE_GRANT",
            "inputs": inputs,
            "verbose": true
        ])
    }

    /// Continues a `DEVICE_GRANT` flow with the user's input for its current step.
    func verifyDeviceCode(payload: EmbeddedSignInPayload) async throws -> DeviceCodeVerificationResponse {
        try requireConfig()
        try refuseInBackendMode("verifyDeviceCode")
        guard let flowId = payload.flowId, !flowId.isEmpty else {
            throw ThunderIDError(
                code: .invalidInput,
                message: "A DEVICE_GRANT continuation needs the flow's executionId"
            )
        }
        var body: [String: Any] = ["executionId": flowId, "verbose": true]
        if let action = payload.actionId { body["action"] = action }
        if let token = payload.challengeToken { body["challengeToken"] = token }
        if !payload.inputs.isEmpty { body["inputs"] = payload.inputs }
        return try await executeDeviceGrant(body)
    }
}

/// The parts of a `DEVICE_GRANT` flow answer the OAuth callback needs.
private struct DeviceGrantCallbackData {
    let assertion: String?
    let authId: String?
    let callbackType: String?

    init(_ json: [String: Any]?, complete: Bool) {
        let additional = (json?["data"] as? [String: Any])?["additionalData"] as? [String: Any]
        assertion = (complete ? json?["assertion"] : json?["errorAssertion"]) as? String
        authId = additional?["authId"] as? String
        callbackType = additional?["callbackType"] as? String
    }
}

extension ThunderIDClient {
    private func executeDeviceGrant(_ body: [String: Any]) async throws -> DeviceCodeVerificationResponse {
        let (data, status) = try await sendJSON("/flow/execute", body: body)
        var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200...299).contains(status) else {
            // A refused device answers with an error assertion, which the callback still has to receive.
            let callback = DeviceGrantCallbackData(json, complete: false)
            guard json != nil, callback.assertion != nil, callback.authId != nil, callback.callbackType != nil else {
                throw ThunderIDError(
                    code: status == 403 ? .forbidden : .authenticationFailed,
                    message: "The device grant flow failed with status \(status)",
                    serverError: ServerError.parse(data)
                )
            }
            json?["flowStatus"] = "ERROR"
            let redirect = try await postDeviceCallback(callback, allowAccessDenied: true)
            return DeviceCodeVerificationResponse(flow: try Self.decodeFlow(json), redirectUrl: redirect)
        }
        let flow = try Self.decodeFlow(json)
        guard flow.flowStatus != .promptOnly else {
            return DeviceCodeVerificationResponse(flow: flow, redirectUrl: nil)
        }
        let callback = DeviceGrantCallbackData(json, complete: flow.flowStatus == .complete)
        guard callback.assertion != nil, callback.authId != nil, callback.callbackType != nil else {
            throw ThunderIDError(
                code: .authenticationFailed,
                message: "The device grant flow ended without its callback data"
            )
        }
        let redirect = try await postDeviceCallback(callback, allowAccessDenied: flow.flowStatus == .error)
        return DeviceCodeVerificationResponse(flow: flow, redirectUrl: redirect)
    }

    private static func decodeFlow(_ json: [String: Any]?) throws -> EmbeddedFlowResponse {
        guard let json, let data = try? JSONSerialization.data(withJSONObject: json) else {
            throw ThunderIDError(code: .unknownError, message: "Failed to decode the device grant flow response")
        }
        do {
            return try JSONDecoder().decode(EmbeddedFlowResponse.self, from: data)
        } catch {
            throw ThunderIDError(code: .unknownError, message: "Failed to decode response", underlyingError: error)
        }
    }

    /// Hands the flow's assertion to `/oauth2/auth/callback`, which releases or denies the device. A denied
    /// flow's callback answers `access_denied`, which is the expected outcome rather than a failure.
    private func postDeviceCallback(
        _ callback: DeviceGrantCallbackData,
        allowAccessDenied: Bool
    ) async throws -> String? {
        let body: [String: Any] = [
            "assertion": callback.assertion ?? "",
            "authId": callback.authId ?? "",
            "type": callback.callbackType ?? ""
        ]
        let (data, status) = try await sendJSON("/oauth2/auth/callback", body: body)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if (200...299).contains(status) { return json?["redirect_uri"] as? String }
        if allowAccessDenied, status == 400, json?["error"] as? String == "access_denied" { return nil }
        throw ThunderIDError(
            code: .authenticationFailed,
            message: "The device grant callback failed with status \(status)",
            serverError: ServerError.parse(data)
        )
    }

    /// Posts JSON to a path under `baseUrl` without a token and returns the body whatever the status. Logs
    /// nothing: the bodies carry assertions.
    private func sendJSON(_ path: String, body: [String: Any]) async throws -> (Data, Int) {
        guard let httpClient, let url = httpClient.url(forPath: path), url.scheme == "https" else {
            throw ThunderIDError(code: .invalidConfiguration, message: "baseUrl must use HTTPS")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await httpClient.rawData(for: request)
        return (data, response.statusCode)
    }
}
