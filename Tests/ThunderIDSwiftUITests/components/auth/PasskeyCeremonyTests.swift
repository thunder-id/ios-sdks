// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

@MainActor
final class PasskeyCeremonyTests: XCTestCase {
    func testReportsAFailedPromptWithItsErrorCode() async {
        let inputs = await PasskeyCeremony.inputs {
            throw ThunderIDError(code: .passkeyCancelled, message: "Passkey ceremony was cancelled by the user")
        }
        XCTAssertEqual(inputs, ["passkeyError": "PASSKEY_CANCELLED"])
    }

    func testReportsAnErrorWithoutACodeAsAFailedPasskey() async {
        let inputs = await PasskeyCeremony.inputs { throw URLError(.badURL) }
        XCTAssertEqual(inputs, ["passkeyError": "PASSKEY_FAILED"])
    }

    func testDoesNotReportACancelledTask() async {
        let inputs = await PasskeyCeremony.inputs { throw CancellationError() }
        XCTAssertNil(inputs)
    }

    /// The step the flow returns for the reported failure is rendered, not hidden behind an error.
    func testRendersTheStepReturnedForTheFailedPrompt() throws {
        let response = try JSONDecoder().decode(EmbeddedFlowResponse.self, from: Data("""
        {"executionId": "f1", "flowStatus": "INCOMPLETE", "type": "VIEW", "challengeToken": "ct2",
         "error": {"code": "FET-1019", "message": {"key": "passkey_auth_failed", "defaultValue": "Failed"}},
         "data": {"meta": {"components": [
           {"id": "action_passkey", "type": "ACTION", "eventType": "TRIGGER", "label": "Sign in with passkey"}]}}}
        """.utf8))

        let state = SignInState { _, _, _, _ in }
        state.update(from: response)

        XCTAssertEqual(state.components.map(\.id), ["action_passkey"])
        XCTAssertNil(state.error)
    }
}
