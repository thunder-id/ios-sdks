// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Covers the expiry of an app-native flow execution: the step's `expiresIn`, and a step the server refuses since
/// its execution expired.
final class FlowExpiryTests: OAuthTestCase {
    private let expiredBody = #"{"code":"FES-1004","message":"Invalid request","description":"Invalid flow execution ID"}"#

    func testStepCarriesItsExpiry() throws {
        let json = #"{"executionId":"f-1","flowStatus":"INCOMPLETE","expiresIn":3540}"#
        let step = try JSONDecoder().decode(EmbeddedFlowResponse.self, from: Data(json.utf8))
        XCTAssertEqual(step.expiresIn, 3540)
    }

    func testStepWithoutAnExpiryHasNone() throws {
        let json = #"{"executionId":"f-1","flowStatus":"COMPLETE"}"#
        let step = try JSONDecoder().decode(EmbeddedFlowResponse.self, from: Data(json.utf8))
        XCTAssertNil(step.expiresIn)
    }

    func testSignInStepForAnExpiredExecutionFailsAsFlowExpired() async throws {
        try await makeClient(clientId: nil, applicationId: "app-1")
        StubBackend.reply("/flow/execute", status: 400, expiredBody)
        do {
            _ = try await client.signIn(
                payload: EmbeddedSignInPayload(flowId: "f-1", actionId: "submit"),
                request: EmbeddedFlowRequestConfig(applicationId: "app-1")
            )
            XCTFail("Expected the step to fail")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .flowExpired)
            XCTAssertEqual(error.serverError?.code, "FES-1004")
        }
    }

    func testSignUpStepForAnExpiredExecutionFailsAsFlowExpired() async throws {
        try await makeClient(clientId: nil, applicationId: "app-1")
        StubBackend.reply("/flow/execute", status: 400, expiredBody)
        do {
            _ = try await client.signUp(payload: EmbeddedSignInPayload(flowId: "f-1", actionId: "submit"))
            XCTFail("Expected the step to fail")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .flowExpired)
        }
    }

    func testOtherRefusedStepsKeepTheirCode() async throws {
        try await makeClient(clientId: nil, applicationId: "app-1")
        StubBackend.reply("/flow/execute", status: 400, #"{"code":"FES-1006","message":"Invalid request"}"#)
        do {
            _ = try await client.signIn(
                payload: EmbeddedSignInPayload(flowId: "f-1", actionId: "submit"),
                request: EmbeddedFlowRequestConfig(applicationId: "app-1")
            )
            XCTFail("Expected the step to fail")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .invalidInput)
            XCTAssertEqual(error.serverError?.code, "FES-1006")
        }
    }
}
