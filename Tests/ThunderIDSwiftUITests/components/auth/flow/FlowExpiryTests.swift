// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

@MainActor
final class FlowExpiryTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 0)
    private var restarts = 0

    private func step(_ status: String, expiresIn: Int?) throws -> EmbeddedFlowResponse {
        let expiry = expiresIn.map { #","expiresIn":\#($0)"# } ?? ""
        let json = #"{"executionId":"f-1","flowStatus":"\#(status)"\#(expiry)}"#
        return try JSONDecoder().decode(EmbeddedFlowResponse.self, from: Data(json.utf8))
    }

    private func makeExpiry() -> FlowExpiry {
        let expiry = FlowExpiry { [unowned self] in clock }
        expiry.restart = { [unowned self] in restarts += 1 }
        return expiry
    }

    func testStartsAgainOnceTheStepExpires() async throws {
        let expiry = FlowExpiry()
        let restarted = expectation(description: "restarted")
        expiry.restart = { restarted.fulfill() }

        expiry.track(try step("INCOMPLETE", expiresIn: 0))

        await fulfillment(of: [restarted], timeout: 2)
    }

    func testStartsAgainWhenTheServerRefusesTheStepAsExpired() {
        let expiry = makeExpiry()
        expiry.expire()
        XCTAssertEqual(restarts, 1)
    }

    func testWaitsForTheAppToBeActiveBeforeStartingAgain() {
        let expiry = makeExpiry()
        expiry.setActive(false)
        expiry.expire()
        XCTAssertEqual(restarts, 0)

        expiry.setActive(true)
        XCTAssertEqual(restarts, 1)
        expiry.setActive(true)
        XCTAssertEqual(restarts, 1, "starts again only once")
    }

    func testChecksTheDeadlineWhenTheAppIsActiveAgain() throws {
        let expiry = makeExpiry()
        expiry.track(try step("INCOMPLETE", expiresIn: 60))
        expiry.setActive(false)

        // The clock moves past the deadline without the timer firing, as in the background.
        clock = clock.addingTimeInterval(61)
        expiry.setActive(true)

        XCTAssertEqual(restarts, 1)
    }

    func testDoesNotStartAgainBeforeTheDeadline() throws {
        let expiry = makeExpiry()
        expiry.track(try step("INCOMPLETE", expiresIn: 60))
        clock = clock.addingTimeInterval(59)
        expiry.setActive(true)
        XCTAssertEqual(restarts, 0)
    }

    func testStopsTrackingAFlowThatEnded() throws {
        let expiry = makeExpiry()
        expiry.track(try step("INCOMPLETE", expiresIn: 60))
        expiry.track(try step("COMPLETE", expiresIn: nil))
        clock = clock.addingTimeInterval(61)
        expiry.setActive(true)
        XCTAssertEqual(restarts, 0)
    }

    func testSignInStateNotesTheRestartUntilTheUserActs() {
        var submitted: String?
        let state = SignInState { actionId, _, flowId, _ in
            submitted = actionId
            XCTAssertNil(flowId, "the expired execution is not sent again")
        }
        state.prepareRestart()
        XCTAssertTrue(state.isFlowRestarted)
        XCTAssertTrue(state.components.isEmpty)

        state.submit(actionId: "submit")
        XCTAssertFalse(state.isFlowRestarted)
        XCTAssertEqual(submitted, "submit")
    }

    func testSignUpStateNotesTheRestartUntilTheUserActs() {
        let state = SignUpState { _, _, _, _ in }
        state.prepareRestart()
        XCTAssertTrue(state.isFlowRestarted)

        state.submit(actionId: "submit")
        XCTAssertFalse(state.isFlowRestarted)
    }
}
