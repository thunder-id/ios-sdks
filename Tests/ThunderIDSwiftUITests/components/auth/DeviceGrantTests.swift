// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers the user side of device authorization: the built-in UI, a custom render, and how the flow's
/// answers become a step or an outcome.
@MainActor
final class DeviceGrantTests: XCTestCase {
    private let i18n = ThunderIDI18n(language: "en-US", storageKey: "device_grant_tests_locale")

    private final class Captured<Value> {
        var value: Value?
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func render(_ view: some View) {
        let state = ThunderIDState(client: ThunderIDClient(), i18n: i18n)
        let renderer = ImageRenderer(
            content: view
                .environmentObject(i18n)
                .environmentObject(state)
                .frame(width: 400)
        )
        XCTAssertNotNil(renderer.cgImage)
    }

    private func step(error: String = "") throws -> EmbeddedFlowResponse {
        try decode(
            #"{"executionId":"exec-1","flowStatus":"INCOMPLETE","challengeToken":"ct","# +
            #""data":{"inputs":[{"identifier":"user_code","type":"TEXT_INPUT","required":true}],"# +
            #""actions":[{"ref":"submit","nextNode":"verify"}],"# +
            #""meta":{"components":[{"type":"TEXT","variant":"HEADING_1","label":"Connect your TV"},"# +
            #"{"type":"BLOCK","components":[{"type":"TEXT_INPUT","ref":"user_code","label":"Code"},"# +
            #"{"type":"ACTION","ref":"submit","label":"Continue","eventType":"SUBMIT"}]}]}}\#(error)}"#
        )
    }

    private func context(
        onComplete: @escaping (DeviceGrantResult) -> Void = { _ in },
        onError: @escaping (String) -> Void = { _ in }
    ) -> DeviceGrantModel.Context {
        DeviceGrantModel.Context(client: ThunderIDClient(), i18n: i18n, onComplete: onComplete, onError: onError)
    }

    func testDefaultStringsCarryTheDeviceGrantKeys() {
        for key in [
            "title", "description", "userCode", "submit", "loading", "errors.start", "errors.continue",
            "errors.invalidCode", "messages.complete", "messages.completeDescription", "messages.denied",
            "messages.deniedDescription", "messages.expired", "messages.expiredDescription", "messages.failed",
            "messages.failedDescription"
        ] {
            XCTAssertNotNil(DefaultStrings.all["deviceGrant.\(key)"], "Missing deviceGrant.\(key)")
        }
        XCTAssertEqual(DefaultStrings.strings(for: "fr-FR")?["deviceGrant.messages.complete"], "Appareil autorisé")
    }

    // MARK: - Built-in UI

    func testBuiltInUIRendersEveryState() throws {
        let flow = try step()
        let data = try XCTUnwrap(flow.data)
        render(BaseDeviceGrant(inputs: [], isLoading: true) { _, _ in })
        render(BaseDeviceGrant(inputs: data.inputs ?? [], initialValues: ["user_code": "ABCD-EFGH"]) { _, _ in })
        render(
            BaseDeviceGrant(
                components: data.meta?.components ?? [],
                inputs: data.inputs ?? [],
                actions: data.actions ?? [],
                error: "This code is invalid or no longer available. Try again."
            ) { _, _ in }
        )
        for result in [DeviceGrantResult.approved, .denied, .expired, .failed] {
            render(BaseDeviceGrant(result: result) { _, _ in })
        }
        render(DeviceGrant(userCode: "ABCD-EFGH"))
    }

    // MARK: - Custom render

    func testContentGetsTheStepThePrefilledCodeAndSubmit() throws {
        let flow = try step()
        let data = try XCTUnwrap(flow.data)
        let captured = Captured<DeviceGrantState>()
        var submissions: [(String?, [String: String])] = []

        render(
            BaseDeviceGrant(
                components: data.meta?.components ?? [],
                inputs: data.inputs ?? [],
                actions: data.actions ?? [],
                initialValues: ["user_code": "ABCD-EFGH", "unrelated": "x"],
                onSubmit: { submissions.append(($0, $1)) },
                content: { grant in
                    let _ = (captured.value = grant)
                    TextField("Code", text: grant.value(for: "user_code"))
                }
            )
        )

        let grant = try XCTUnwrap(captured.value)
        XCTAssertEqual(grant.values, ["user_code": "ABCD-EFGH"])
        XCTAssertEqual(grant.actions.first?.label, "Continue", "Actions take their label from the component tree")
        XCTAssertNil(grant.result)
        grant.submit(nil)
        XCTAssertEqual(submissions.first?.0, "submit")
        XCTAssertEqual(submissions.first?.1, ["user_code": "ABCD-EFGH"])
    }

    func testContentDoesNotSubmitWhileLoading() throws {
        let captured = Captured<DeviceGrantState>()
        var submissions = 0

        render(
            BaseDeviceGrant(inputs: [FlowInput(name: "user_code")], isLoading: true, onSubmit: { _, _ in submissions += 1 }) { grant in
                let _ = (captured.value = grant)
                Text("")
            }
        )

        try XCTUnwrap(captured.value).submit(nil)
        XCTAssertEqual(submissions, 0)
    }

    // MARK: - Flow answers

    func testAnInvalidCodeKeepsTheStepWithATranslatedMessage() throws {
        let model = DeviceGrantModel()
        let invalid = #","error":{"code":"FET-1131","message":{"key":"x","defaultValue":"Server text"}}"#

        model.apply(try step(error: invalid), context: context())

        XCTAssertEqual(model.flow?.flowId, "exec-1")
        XCTAssertNil(model.result)
        XCTAssertEqual(model.error, "This code is invalid or no longer available. Try again.")
    }

    func testTheFlowsEndBecomesTheOutcome() throws {
        var outcomes: [DeviceGrantResult] = []
        let approved = DeviceGrantModel()
        let denied = DeviceGrantModel()

        approved.apply(try decode(#"{"flowStatus":"COMPLETE"}"#), context: context { outcomes.append($0) })
        denied.apply(
            try decode(#"{"flowStatus":"ERROR","error":{"message":{"defaultValue":"Server text"}}}"#),
            context: context { outcomes.append($0) }
        )

        XCTAssertEqual(outcomes, [.approved, .denied])
        XCTAssertNil(approved.flow)
        XCTAssertNil(denied.error, "The server's own text is never shown")
    }

    func testAnExpiredStepEndsTheFlow() async throws {
        let model = DeviceGrantModel()
        var outcomes: [DeviceGrantResult] = []
        let past = Int(Date().timeIntervalSince1970 * 1000) - 1000
        let expiring: EmbeddedFlowResponse = try decode(
            #"{"executionId":"exec-2","flowStatus":"INCOMPLETE","data":{"additionalData":{"stepTimeout":\#(past)}}}"#
        )

        model.apply(expiring, context: context { outcomes.append($0) })
        for _ in 0..<100 where model.result == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(model.result, .expired)
        XCTAssertEqual(outcomes, [.expired])
        XCTAssertNotNil(DeviceGrantModel.deadline("1700000000000"))
        XCTAssertNil(DeviceGrantModel.deadline(nil))
    }

    func testAFlowThatCannotStartReportsATranslatedError() async {
        let model = DeviceGrantModel()
        var errors: [String] = []

        await model.start(userCode: nil, applicationId: nil, context: context(onError: { errors.append($0) }))

        XCTAssertEqual(model.result, .failed)
        XCTAssertEqual(errors, ["Could not start device verification. Please try again."])
    }
}
