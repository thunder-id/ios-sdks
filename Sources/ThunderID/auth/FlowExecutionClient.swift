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
        actionId: String,
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

    func submitBody(flowId: String, actionId: String, challengeToken: String?) -> [String: Any] {
        var body: [String: Any] = [
            "executionId": flowId,
            "action": actionId
        ]
        if let token = challengeToken {
            body["challengeToken"] = token
        }
        return body
    }
}
