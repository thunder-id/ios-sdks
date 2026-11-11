// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ThunderID

final class FlowErrorTests: XCTestCase {
    private func failureReason(_ json: String) throws -> String? {
        try JSONDecoder().decode(EmbeddedFlowResponse.self, from: Data(json.utf8)).failureReason
    }

    func testReadsTheErrorMessageThenItsDescription() throws {
        XCTAssertEqual(try failureReason("""
        {"flowStatus": "ERROR", "error": {"code": "FET-1007",
         "message": {"key": "k", "defaultValue": "The user already exists"},
         "description": {"key": "d", "defaultValue": "A user with these attributes exists"}}}
        """), "The user already exists")
        XCTAssertEqual(try failureReason("""
        {"flowStatus": "ERROR", "error": {"code": "FET-1007", "description": {"defaultValue": "Details"}}}
        """), "Details")
    }

    func testFallsBackToTheLegacyFailureReason() throws {
        XCTAssertEqual(try failureReason(#"{"flowStatus": "ERROR", "failureReason": "Old"}"#), "Old")
        XCTAssertNil(try failureReason(#"{"flowStatus": "ERROR"}"#))
    }

    /// `EmbeddedFlowResponse` is decoded by hand, so a field added to it later would be silently skipped.
    /// Every field is set here, and every stored property must come back non-nil: a new field fails this
    /// test until both the decoder and this payload carry it.
    func testDecodesEveryField() throws {
        let response = try JSONDecoder().decode(EmbeddedFlowResponse.self, from: Data("""
        {"executionId": "f1", "flowStatus": "ERROR", "stepId": "s1", "type": "VIEW", "data": {},
         "assertion": "jwt", "challengeToken": "ct1", "failureReason": "Old",
         "error": {"code": "FET-1007",
                   "message": {"key": "errors.user.exists", "defaultValue": "Exists", "params": {"name": "alice"}},
                   "description": {"key": "d", "defaultValue": "Details"}},
         "sessionData": [{"flowIdentifier": "app-1", "sessionHandle": "h1", "expiresIn": 600}],
         "clearedSessions": ["app-2"], "expiresIn": 3540}
        """.utf8))

        for child in Mirror(reflecting: response).children {
            let value = Mirror(reflecting: child.value)
            let isNil = value.displayStyle == .optional && value.children.isEmpty
            XCTAssertFalse(isNil, "\(child.label ?? "?") was not decoded")
        }
        XCTAssertEqual(response.flowId, "f1")
        XCTAssertEqual(response.stepId, "s1")
        XCTAssertEqual(response.type, "VIEW")
        XCTAssertEqual(response.assertion, "jwt")
        XCTAssertEqual(response.challengeToken, "ct1")
        XCTAssertEqual(response.failureReason, "Exists")
        XCTAssertEqual(response.error?.code, "FET-1007")
        XCTAssertEqual(response.error?.message?.key, "errors.user.exists")
        XCTAssertEqual(response.error?.message?.params, ["name": "alice"])
        XCTAssertEqual(response.error?.description?.defaultValue, "Details")
        XCTAssertEqual(
            response.sessionData,
            [EmbeddedFlowSessionData(flowIdentifier: "app-1", sessionHandle: "h1", expiresIn: 600)]
        )
        XCTAssertEqual(response.clearedSessions, ["app-2"])
    }
}
