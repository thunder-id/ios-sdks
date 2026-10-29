// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Records what a verification asks of the server, answers from queued replies, and collects callbacks.
private final class FakeVerification {
    var schema: [String: AttributeSchema] = ["email": AttributeSchema(displayName: "Email address", type: "email")]
    var startReplies: [Result<EmbeddedFlowResponse, Error>] = []
    var submitReplies: [Result<EmbeddedFlowResponse, Error>] = []
    var profile = ThunderID.UserProfile(id: "u1", verifiedAttributes: ["email": VerifiedAttribute(verifiedAt: "t")])
    private(set) var calls: [String] = []
    private(set) var payloads: [EmbeddedSignInPayload] = []
    var errors: [Error] = []
    var completions = 0
    var dones = 0
    var profileReads: [ThunderID.UserProfile?] = []

    /// An unexpected request fails rather than crashing, so the test's own assertions report it.
    private func next(_ replies: inout [Result<EmbeddedFlowResponse, Error>]) throws -> EmbeddedFlowResponse {
        guard !replies.isEmpty else { throw ThunderIDError(code: .unknownError, message: "Unexpected request") }
        return try replies.removeFirst().get()
    }

    var engine: VerifyAttributeEngine {
        VerifyAttributeEngine(
            loadSchema: { [self] in
                calls.append("schema")
                return schema
            },
            start: { [self] in
                calls.append("start")
                return try next(&startReplies)
            },
            submit: { [self] payload in
                calls.append("submit")
                payloads.append(payload)
                return try next(&submitReplies)
            },
            readProfile: { [self] in
                calls.append("profile")
                return profile
            }
        )
    }
}

private func step(_ json: String) -> EmbeddedFlowResponse {
    // swiftlint:disable:next force_try
    try! JSONDecoder().decode(EmbeddedFlowResponse.self, from: Data(json.utf8))
}

private let codeStep = step("""
{"executionId":"exec-1","flowStatus":"INCOMPLETE","challengeToken":"ct-1",
 "data":{"inputs":[{"identifier":"otp","type":"OTP_INPUT","required":true}],
  "additionalData":{"maskedDestination":"a***@example.com","otpLength":"6"},
  "meta":{"components":[
   {"type":"TEXT","id":"h1","label":"Check your email","variant":"HEADING_1"},
   {"type":"TEXT","id":"h2","label":"Enter the code","variant":"HEADING_6"},
   {"type":"BLOCK","id":"b","components":[
    {"type":"OTP_INPUT","id":"input_email_otp","ref":"otp","label":"Code"},
    {"type":"ACTION","id":"action_email_verify","label":"Verify"},
    {"type":"RESEND","id":"action_email_resend","label":"Resend"}]}]}}}
""")

private let rejectedCode = step("""
{"executionId":"exec-1","flowStatus":"INCOMPLETE","challengeToken":"ct-2",
 "error":{"code":"FET-1010","message":{"defaultValue":"The code is not valid"}},
 "data":{"inputs":[{"identifier":"otp","type":"OTP_INPUT","required":true}],
  "meta":{"components":[{"type":"BLOCK","id":"b","components":[
   {"type":"OTP_INPUT","id":"input_email_otp","ref":"otp"},
   {"type":"ACTION","id":"action_email_verify"},{"type":"RESEND","id":"action_email_resend"}]}]}}}
""")

private let linkStep = step("""
{"executionId":"exec-1","flowStatus":"INCOMPLETE",
 "data":{"additionalData":{"maskedDestination":"a***@example.com"},
  "meta":{"components":[{"type":"TEXT","id":"h1","label":"Check your email","variant":"HEADING_1"}]}}}
""")

private let complete = step(#"{"executionId":"exec-1","flowStatus":"COMPLETE"}"#)

@MainActor
final class VerifyAttributeStateTests: XCTestCase {
    private let fake = FakeVerification()
    private var errors: [Error] { fake.errors }

    private func makeState(
        attribute: String = "email",
        displayName: String? = nil,
        callbacks: Bool = true
    ) -> VerifyAttributeState {
        let state = VerifyAttributeState(attribute: attribute, attributeDisplayName: displayName)
        state.engine = fake.engine
        state.resolve = ThunderIDI18n().resolve
        guard callbacks else { return state }
        state.onError = { [fake] in fake.errors.append($0) }
        state.onComplete = { [fake] in fake.completions += 1 }
        state.onDone = { [fake] in fake.dones += 1 }
        state.onProfileRead = { [fake] in fake.profileReads.append($0) }
        return state
    }

    // MARK: - Starting

    func testStartsOnceAfterTheSchemaLoads() async {
        fake.startReplies = [.success(codeStep)]
        let state = makeState()

        await state.start()
        await state.start()

        XCTAssertEqual(fake.calls, ["schema", "start"])
        XCTAssertEqual(state.phase, .active)
        XCTAssertEqual(state.attributeDisplayName, "Email address")
    }

    func testAFailedStartIsNotRetried() async {
        fake.startReplies = [.failure(ThunderIDError(code: .serverError, message: "boom"))]
        let state = makeState()

        await state.start()
        await state.start()

        XCTAssertEqual(fake.calls, ["schema", "start"])
        XCTAssertEqual(state.phase, .failed)
        XCTAssertEqual(errors.count, 1)
    }

    func testAnAttributeThatIsNotAVerifiableEmailOrMobileStartsNothing() async {
        fake.schema = ["given_name": AttributeSchema(type: "string"), "emails": AttributeSchema(type: "array")]
        for attribute in ["given_name", "emails", "email"] {
            fake.errors = []
            let state = makeState(attribute: attribute)

            await state.start()

            XCTAssertFalse(fake.calls.contains("start"), attribute)
            XCTAssertEqual(state.phase, .failed, attribute)
            XCTAssertEqual((errors.first as? ThunderIDError)?.code, .invalidInput, attribute)
        }
    }

    // MARK: - Steps

    func testKeepsTheFlowsPromptAndShowsTheDestinationBesideIt() async {
        fake.startReplies = [.success(codeStep)]
        let state = makeState()

        await state.start()

        XCTAssertEqual(state.title, "Check your email")
        XCTAssertEqual(state.subtitle, "Enter the code")
        XCTAssertEqual(state.destinationMessage, "Sent to a***@example.com.")
        XCTAssertEqual(state.codeLength, 6)
        XCTAssertFalse(state.isAwaitingLink)
        XCTAssertFalse(state.components.contains { $0.id == "h1" || $0.id == "h2" })
    }

    func testNamesTheDestinationInTheBundlePromptWhenTheFlowHasNone() async {
        fake.startReplies = [.success(step("""
        {"executionId":"e","flowStatus":"INCOMPLETE",
         "data":{"additionalData":{"maskedDestination":"+94*****567"},
          "meta":{"components":[{"type":"OTP_INPUT","id":"i","ref":"otp"},{"type":"ACTION","id":"a"}]}}}
        """))]
        let state = makeState()

        await state.start()

        XCTAssertEqual(state.subtitle, "Enter the code sent to +94*****567.")
        XCTAssertNil(state.destinationMessage)
    }

    func testARejectedCodeKeepsTheDestinationAndCodeLengthAndShowsTheError() async {
        fake.startReplies = [.success(codeStep)]
        fake.submitReplies = [.success(rejectedCode)]
        let state = makeState()
        await state.start()
        state.binding(for: "otp").wrappedValue = "000000"

        await state.performSubmit(actionId: "action_email_verify")

        XCTAssertEqual(state.phase, .active)
        XCTAssertEqual(state.destination, "a***@example.com")
        XCTAssertEqual(state.codeLength, 6)
        XCTAssertEqual(state.error, DefaultStrings.all["verifyAttribute.error"])
        XCTAssertEqual(state.binding(for: "otp").wrappedValue, "")
        XCTAssertTrue(errors.isEmpty)
    }

    func testOnlyTheDestinationChannelAndCodeLengthCarryToALaterStep() async {
        fake.startReplies = [.success(step("""
        {"executionId":"exec-1","flowStatus":"INCOMPLETE","challengeToken":"ct-1",
         "data":{"inputs":[{"identifier":"otp","type":"OTP_INPUT","required":true}],
          "additionalData":{"maskedDestination":"a***@example.com","channel":"EMAIL","otpLength":"6",
                            "emailSent":"true"},
          "meta":{"components":[{"type":"OTP_INPUT","id":"i","ref":"otp"},{"type":"ACTION","id":"a"}]}}}
        """))]
        fake.submitReplies = [.success(step("""
        {"executionId":"exec-1","flowStatus":"INCOMPLETE","challengeToken":"ct-2",
         "data":{"inputs":[{"identifier":"otp","type":"OTP_INPUT","required":true}],
          "additionalData":{"stepNote":"now"},
          "meta":{"components":[{"type":"OTP_INPUT","id":"i","ref":"otp"},{"type":"ACTION","id":"a"}]}}}
        """))]
        let state = makeState()
        await state.start()
        state.binding(for: "otp").wrappedValue = "000000"

        await state.performSubmit(actionId: "a")

        XCTAssertNil(state.additionalData["emailSent"])
        XCTAssertEqual(state.additionalData["stepNote"]?.value as? String, "now")
        XCTAssertEqual(state.additionalData["channel"]?.value as? String, "EMAIL")
        XCTAssertEqual(state.destination, "a***@example.com")
        XCTAssertEqual(state.codeLength, 6)
    }

    func testSubmitSendsTheCodeWithTheExecutionAndChallengeToken() async throws {
        fake.startReplies = [.success(codeStep)]
        fake.submitReplies = [.success(rejectedCode), .success(complete)]
        let state = makeState()
        await state.start()
        state.binding(for: "otp").wrappedValue = "000000"
        await state.performSubmit(actionId: "action_email_verify")
        state.binding(for: "otp").wrappedValue = "123456"

        await state.performSubmit(actionId: "action_email_verify")

        let payload = try XCTUnwrap(fake.payloads.last)
        XCTAssertEqual(payload.flowId, "exec-1")
        XCTAssertEqual(payload.challengeToken, "ct-2")
        XCTAssertEqual(payload.actionId, "action_email_verify")
        XCTAssertEqual(payload.inputs, ["otp": "123456"])
    }

    func testAnEmptyCodeIsCaughtBeforeAnyRequest() async {
        fake.startReplies = [.success(codeStep)]
        let state = makeState()
        await state.start()

        await state.performSubmit(actionId: "action_email_verify")

        XCTAssertFalse(fake.calls.contains("submit"))
        XCTAssertEqual(state.fieldErrors["otp"], DefaultStrings.all["verifyAttribute.required"])
    }

    func testResendSubmitsItsActionWithNoInputsAndNoValidation() async throws {
        fake.startReplies = [.success(codeStep)]
        fake.submitReplies = [.success(codeStep)]
        let state = makeState()
        await state.start()
        state.binding(for: "otp").wrappedValue = "12"

        await state.send(actionId: "action_email_resend", inputs: [:])

        let payload = try XCTUnwrap(fake.payloads.first)
        XCTAssertEqual(payload.actionId, "action_email_resend")
        XCTAssertEqual(payload.inputs, [:])
        XCTAssertEqual(payload.flowId, "exec-1")
        XCTAssertEqual(payload.challengeToken, "ct-1")
    }

    func testEmptyFieldsDoNotStopAResend() async {
        fake.startReplies = [.success(codeStep)]
        fake.submitReplies = [.success(codeStep)]
        let state = makeState()
        await state.start()

        state.resend(actionId: "action_email_resend")
        for _ in 0..<50 where fake.payloads.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(fake.payloads.first?.inputs, [:])
        XCTAssertTrue(state.fieldErrors.isEmpty)
    }

    // MARK: - Outcomes

    func testCompleteReadsTheProfileAgain() async {
        fake.startReplies = [.success(codeStep)]
        fake.submitReplies = [.success(complete)]
        let state = makeState()
        await state.start()
        state.binding(for: "otp").wrappedValue = "123456"

        await state.performSubmit(actionId: "action_email_verify")

        XCTAssertEqual(state.phase, .complete)
        XCTAssertEqual(fake.calls.filter { $0 == "profile" }.count, 1)
        XCTAssertEqual(fake.completions, 1)
        XCTAssertEqual(fake.profileReads.count, 1)
        XCTAssertEqual(fake.profileReads.first??.verifiedAttributes?["email"], VerifiedAttribute(verifiedAt: "t"))
        XCTAssertEqual(state.successMessage, "Email address verified.")
    }

    func testCompleteAndDoneReadTheProfileAgainWithNoCallbackSet() async {
        fake.startReplies = [.success(complete), .success(linkStep)]
        let completing = makeState(callbacks: false)
        await completing.start()

        XCTAssertEqual(completing.phase, .complete)
        XCTAssertEqual(fake.calls.filter { $0 == "profile" }.count, 1)

        let linking = makeState(callbacks: false)
        await linking.start()
        await linking.performDone()

        XCTAssertEqual(fake.calls.filter { $0 == "profile" }.count, 2)
    }

    func testAnErrorStepIsAVerificationFailedRefusalWithoutTheServerReason() async {
        fake.startReplies = [.success(step(
            #"{"executionId":"e","flowStatus":"ERROR","error":{"code":"FET-1112","message":{"defaultValue":"No"}}}"#
        ))]
        let state = makeState()

        await state.start()

        XCTAssertEqual(state.phase, .failed)
        XCTAssertEqual(state.error, DefaultStrings.all["verifyAttribute.error"])
        XCTAssertEqual((errors.first as? ThunderIDError)?.code, .verificationFailed)
        XCTAssertEqual((errors.first as? ThunderIDError)?.message, "The server refused the verification")
        XCTAssertFalse(fake.calls.contains("profile"))
    }

    func testAFailedRequestShowsAGenericMessageAndReportsTheError() async {
        fake.startReplies = [.success(codeStep)]
        fake.submitReplies = [.failure(ThunderIDError(code: .verificationFailed, message: "server detail"))]
        let state = makeState()
        await state.start()
        state.binding(for: "otp").wrappedValue = "123456"

        await state.performSubmit(actionId: "action_email_verify")

        XCTAssertEqual(state.phase, .failed)
        XCTAssertEqual(state.error, DefaultStrings.all["verifyAttribute.error"])
        XCTAssertEqual((errors.first as? ThunderIDError)?.message, "server detail")
        XCTAssertEqual(fake.calls.filter { $0 == "submit" }.count, 1)
    }

    func testALinkStepShowsWhereTheLinkWentAndDoneReadsTheProfileOnce() async {
        fake.startReplies = [.success(linkStep)]
        let state = makeState()

        await state.start()

        XCTAssertTrue(state.isAwaitingLink)
        XCTAssertEqual(
            state.subtitle,
            "We sent a verification link to a***@example.com. Open it, then select Done."
        )
        XCTAssertFalse(fake.calls.contains("profile"))

        await state.performDone()

        XCTAssertEqual(fake.calls.filter { $0 == "profile" }.count, 1)
        XCTAssertEqual(fake.dones, 1)
        XCTAssertNotNil(fake.profileReads.first ?? nil)
    }

    func testAStepWithAnActionIsNotALinkWait() {
        XCTAssertTrue(VerifyAttributeState.containsAction([codeStep.data!.meta!.components![2]]))
        XCTAssertFalse(VerifyAttributeState.containsAction(linkStep.data!.meta!.components!))
    }

    func testHeadingFallsBackToTheBundleWhenTheLabelIsAnUnresolvedTemplate() async {
        fake.startReplies = [.success(step("""
        {"executionId":"e","flowStatus":"INCOMPLETE","data":{"meta":{"components":[
         {"type":"TEXT","id":"h1","label":"{{ t(verification:self.email.title) }}","variant":"HEADING_1"},
         {"type":"ACTION","id":"a"}]}}}
        """))]
        let state = makeState(displayName: "Work email")

        await state.start()

        XCTAssertEqual(state.title, "Verify Work email")
        XCTAssertEqual(state.subtitle, "Enter the code sent to you.")
        XCTAssertNil(state.destinationMessage)
    }

    // MARK: - Custom render

    private final class Captured {
        var state: VerifyAttributeState?
    }

    private func render(_ view: some View) {
        let i18n = ThunderIDI18n()
        let renderer = ImageRenderer(
            content: view
                .environmentObject(i18n)
                .environmentObject(ThunderIDState(client: ThunderIDClient(), i18n: i18n))
                .frame(width: 400)
        )
        XCTAssertNotNil(renderer.cgImage)
    }

    func testBaseContentReceivesTheStateAndTheCancelAction() throws {
        let captured = Captured()
        var cancels = 0

        render(
            BaseVerifyAttribute(attribute: "email", attributeDisplayName: "Work email", onCancel: { cancels += 1 }) { state in
                let _ = (captured.state = state)
                Text(state.title)
            }
        )

        let state = try XCTUnwrap(captured.state)
        XCTAssertEqual(state.attribute, "email")
        XCTAssertEqual(state.attributeDisplayName, "Work email")
        XCTAssertEqual(state.phase, .loading)
        state.onCancel?()
        XCTAssertEqual(cancels, 1)
    }

    func testNoCancelActionUnlessTheAppGivesOne() throws {
        let base = Captured()
        let connected = Captured()

        render(BaseVerifyAttribute(attribute: "email") { state in
            let _ = (base.state = state)
            Text(state.title)
        })
        render(VerifyAttribute(attribute: "email") { state in
            let _ = (connected.state = state)
            Text(state.title)
        })

        XCTAssertNil(try XCTUnwrap(base.state).onCancel)
        XCTAssertNil(try XCTUnwrap(connected.state).onCancel)
    }

    func testBundleHasEveryVerificationString() {
        let keys = [
            "verifyAttribute.heading", "verifyAttribute.subheading", "verifyAttribute.subheading.generic",
            "verifyAttribute.subheading.link", "verifyAttribute.destination", "verifyAttribute.code.label", "verifyAttribute.submit",
            "verifyAttribute.resend", "verifyAttribute.required", "verifyAttribute.success", "verifyAttribute.error",
            "verifyAttribute.verify", "verifyAttribute.cancel", "verifyAttribute.close", "verifyAttribute.done",
            "verifyAttribute.status.verified", "verifyAttribute.status.unverified", "verifyAttribute.status.verifiedAt"
        ]
        for key in keys {
            XCTAssertNotNil(DefaultStrings.all[key], key)
        }
    }
}

@MainActor
extension VerifyAttributeStateTests {
    func testSubmittedCodeIsDiscardedAfterCompletionAndRequestFailure() async {
        for response: Result<EmbeddedFlowResponse, Error> in [
            .success(complete), .failure(ThunderIDError(code: .networkError, message: "Connection failed"))
        ] {
            fake.startReplies = [.success(codeStep)]
            fake.submitReplies = [response]
            let state = makeState()
            await state.start()
            state.binding(for: "otp").wrappedValue = "123456"
            await state.performSubmit(actionId: "verify")
            XCTAssertEqual(fake.payloads.last?.inputs, ["otp": "123456"])
            XCTAssertEqual(state.binding(for: "otp").wrappedValue, "")
        }
    }

    func testSchemaMustArriveBeforeStartingOrRefusing() async {
        let state = makeState()
        var schemaReply: CheckedContinuation<[String: AttributeSchema], Never>?
        state.engine?.loadSchema = {
            await withCheckedContinuation { schemaReply = $0 }
        }
        fake.startReplies = [.success(codeStep)]
        let start = Task { await state.start() }
        for _ in 0..<1000 where schemaReply == nil { await Task.yield() }
        guard let schemaReply else {
            XCTFail("Schema must be awaited")
            await start.value
            return
        }
        XCTAssertEqual(state.phase, .loading)
        XCTAssertFalse(fake.calls.contains("start"))
        XCTAssertTrue(errors.isEmpty)
        schemaReply.resume(returning: fake.schema)
        await start.value
        XCTAssertEqual(state.phase, .active)
        XCTAssertEqual(fake.calls, ["start"])
    }

    func testInFlightSubmitIgnoresSubmitAndResendAndKeepsLatestToken() async {
        fake.startReplies = [.success(codeStep)]
        let state = makeState()
        await state.start()
        state.binding(for: "otp").wrappedValue = "123456"
        var reply: CheckedContinuation<EmbeddedFlowResponse, Never>?
        var payloads: [EmbeddedSignInPayload] = []
        state.engine?.submit = { payload in
            payloads.append(payload)
            if payloads.count == 1 {
                return await withCheckedContinuation { reply = $0 }
            }
            return rejectedCode
        }
        let first = Task { await state.performSubmit(actionId: "verify") }
        while reply == nil { await Task.yield() }
        state.binding(for: "otp").wrappedValue = ""
        await state.performSubmit(actionId: "verify")
        await state.send(actionId: "resend", inputs: [:])
        XCTAssertTrue(state.fieldErrors.isEmpty, "Busy submit must not validate")
        XCTAssertEqual(payloads.count, 1)
        XCTAssertTrue(state.isLoading)
        reply?.resume(returning: rejectedCode)
        await first.value
        XCTAssertFalse(state.isLoading)
        await state.send(actionId: "resend", inputs: [:])
        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads.last?.challengeToken, "ct-2")
    }

    func testCorrectingRequiredValueClearsValidationAndPublishesChange() async {
        fake.startReplies = [.success(codeStep)]
        fake.submitReplies = [.success(complete)]
        let state = makeState()
        await state.start()
        await state.performSubmit(actionId: "verify")
        XCTAssertNotNil(state.fieldErrors["otp"])
        var changes = 0
        let observation = state.objectWillChange.sink { changes += 1 }
        state.binding(for: "otp").wrappedValue = "123456"
        XCTAssertNil(state.fieldErrors["otp"])
        let beforeEdit = changes
        state.binding(for: "otp").wrappedValue = "654321"
        XCTAssertGreaterThan(changes, beforeEdit)
        await state.performSubmit(actionId: "verify")
        XCTAssertEqual(state.phase, .complete)
        withExtendedLifetime(observation) {}
    }

}
