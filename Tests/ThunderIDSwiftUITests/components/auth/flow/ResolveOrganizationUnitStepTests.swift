// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// The Resolve OU step of a sign-in flow, rendered from the server's description: before sign-in the user
/// types the unit (`OU_SELECT`, nothing listed); after sign-in the eligible units arrive as a `SELECT`'s
/// options and the user picks one.
@MainActor
final class ResolveOrganizationUnitStepTests: XCTestCase {
    private let afterSignIn = #"""
    {"executionId":"f-1","flowStatus":"INCOMPLETE","stepId":"resolve_ou","type":"VIEW",
     "data":{"inputs":[{"ref":"ou_selection_input","identifier":"ouId","type":"SELECT","required":true,
                        "options":["acme/east","acme/west"]}],
             "actions":[{"ref":"action_ou_selection","nextNode":"ou_selection"}],
             "meta":{"components":[{"type":"BLOCK","id":"block","components":[
                 {"type":"OU_SELECT","id":"ou_selection_input","ref":"ouId","label":"Organization"},
                 {"type":"ACTION","id":"action_ou_selection","label":"Continue","eventType":"SUBMIT"}]}]}}}
    """#

    func testTheStepsOptionsAreDecoded() throws {
        let response = try JSONDecoder().decode(EmbeddedFlowResponse.self, from: Data(afterSignIn.utf8))
        let input = try XCTUnwrap(response.data?.inputs?.first)
        XCTAssertEqual(input.name, "ouId")
        XCTAssertEqual(input.type, "SELECT")
        XCTAssertEqual(input.options, ["acme/east", "acme/west"])
    }

    func testOptionsSentAsObjectsAreReadByValue() throws {
        let json = #"{"identifier":"ouId","type":"SELECT","options":[{"value":"a","label":"A"},{"label":"b"}]}"#
        let input = try JSONDecoder().decode(FlowInput.self, from: Data(json.utf8))
        XCTAssertEqual(input.options, ["a", "b"])
        let typed = try JSONDecoder().decode(FlowInput.self, from: Data(#"{"identifier":"ouHandle"}"#.utf8))
        XCTAssertNil(typed.options)
    }

    func testSelectionComponentsAreRenderedAndSeededAsInputs() throws {
        XCTAssertTrue(FlowInputField.isSelection("OU_SELECT"))
        XCTAssertTrue(FlowInputField.isSelection("SELECT"))
        XCTAssertFalse(FlowInputField.isSelection("TEXT_INPUT"))
        let response = try JSONDecoder().decode(EmbeddedFlowResponse.self, from: Data(afterSignIn.utf8))
        let names = FlowComponentMerging.inputNames(in: response.data?.meta?.components ?? [])
        XCTAssertEqual(names, ["ouId"])
    }

    func testThePickerAndTheTypedFieldRender() {
        let value = Binding.constant("")
        for options in [["acme/east", "acme/west"], nil] {
            let field = FlowInputField(
                name: "ouId",
                type: "OU_SELECT",
                label: "Organization",
                placeholder: "Organization",
                binding: value,
                options: options
            )
            XCTAssertNotNil(ImageRenderer(content: field.frame(width: 320)).cgImage)
        }
    }

    func testSignInTakesTheUnitToBoundItsFlowTo() {
        XCTAssertEqual(SignIn(applicationId: "app", organizationUnitId: "ou-2").organizationUnitId, "ou-2")
        XCTAssertNil(SignIn(applicationId: "app").organizationUnitId)
        XCTAssertEqual(BaseSignIn(applicationId: "app", organizationUnitId: "ou-2") { _ in EmptyView() }.organizationUnitId, "ou-2")
    }
}
