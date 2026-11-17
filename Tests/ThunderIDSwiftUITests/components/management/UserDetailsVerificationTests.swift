// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers the email verification status and the send-link action of the user details components.
@MainActor
final class UserDetailsVerificationTests: XCTestCase {
    private let i18n = ThunderIDI18n(language: "en-US", storageKey: "user_details_verification_tests_locale")

    private let schema: EntityTypeSchema = ["workEmail": .init(type: "email"), "mobile_number": .init(type: "mobile")]

    private final class Captured<Value> {
        var value: Value?
    }

    private func user(verified: String? = "{}", readOnly: Bool = false) throws -> ManagedUser {
        let verifiedJSON = verified.map { #","verifiedAttributes":\#($0)"# } ?? ""
        let json = #"{"id":"u-1","ouId":"ou","type":"customer","display":"Aiko Tanaka","isReadOnly":\#(readOnly),"#
            + #""attributes":{"workEmail":"aiko@example.com","mobile_number":"+94770000001","given_name":"Aiko","password":"x"}\#(verifiedJSON)}"#
        return try JSONDecoder().decode(ManagedUser.self, from: Data(json.utf8))
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

    private func capture(_ details: (@escaping (UserDetailsState) -> Text) -> BaseUserDetails<Text>) throws
        -> UserDetailsState {
        let captured = Captured<UserDetailsState>()
        render(details { state in
            captured.value = state
            return Text(state.displayName)
        })
        return try XCTUnwrap(captured.value)
    }

    // MARK: - Strings

    func testEveryVerificationStringIsInTheBundle() {
        XCTAssertEqual(
            i18n.resolve("admin.users.details.verification.load_error"),
            "The verification settings could not be loaded."
        )
        XCTAssertEqual(i18n.resolve("admin.users.details.verification.verify"), "Verify")
        XCTAssertEqual(
            i18n.resolve("admin.users.details.verification.error"),
            "Could not send the verification link. Please try again."
        )
    }

    func testNamesTheMaskedDestinationOfASentLink() {
        XCTAssertEqual(
            i18n.verificationSentMessage(UserAttributeVerificationResult(channel: "email", maskedDestination: "a•••@x.io")),
            "Verification link sent to a•••@x.io."
        )
        XCTAssertEqual(
            i18n.verificationSentMessage(UserAttributeVerificationResult(channel: "email")),
            "Verification link sent."
        )
    }

    // MARK: - Offering the action

    func testOffersTheActionOnlyWhenEnabledAndTheServerNamesAFlow() {
        let configured: [AdministrationFlowConfigKey: String] = [.adminAttributeVerification: "admin-verification"]

        XCTAssertEqual(adminVerificationFlowHandle(enabled: true, configuredFlows: configured), "admin-verification")
        XCTAssertNil(adminVerificationFlowHandle(enabled: false, configuredFlows: configured))
        XCTAssertNil(adminVerificationFlowHandle(enabled: true, configuredFlows: [:]))
        XCTAssertNil(adminVerificationFlowHandle(enabled: true, configuredFlows: nil))
        XCTAssertNil(adminVerificationFlowHandle(enabled: true, configuredFlows: [.adminAttributeVerification: ""]))
        XCTAssertNil(adminVerificationFlowHandle(enabled: true, configuredFlows: [.userSuspend: "s"]))
    }

    func testReadsTheUserTypeOnlyWhileVerificationIsOn() throws {
        XCTAssertEqual(verificationUserTypeHandle(user: try user(), attributeVerification: true), "customer")
        XCTAssertNil(verificationUserTypeHandle(user: try user(), attributeVerification: false))
        XCTAssertNil(verificationUserTypeHandle(user: try user(verified: nil), attributeVerification: true))
        XCTAssertNil(verificationUserTypeHandle(user: nil, attributeVerification: true))
    }

    // MARK: - Built-in view

    func testRendersTheStatusTheActionAndTheSentMessage() throws {
        render(BaseUserDetails(user: try user(), userSchema: schema, onSendVerification: { _ in }))
        render(BaseUserDetails(user: try user(), userSchema: schema, isSendingVerification: true, onSendVerification: { _ in }))
        render(
            BaseUserDetails(
                user: try user(verified: #"{"workEmail":{"verifiedAt":"2026-11-03T10:00:00Z"}}"#),
                sentVerification: UserAttributeVerificationResult(channel: "email", maskedDestination: "a•••@x.io")
            )
        )
    }

    // MARK: - Custom render

    func testHandsCustomContentTheVerificationStateAndAction() throws {
        var sent: [String] = []
        let result = UserAttributeVerificationResult(channel: "email", emailSent: true, maskedDestination: "a•••@x.io")

        let state = try capture { content in
            BaseUserDetails(
                user: try? self.user(),
                userSchema: self.schema,
                sentVerification: result,
                onSendVerification: { sent.append($0) },
                content: content
            )
        }

        XCTAssertEqual(state.verifiableAttributes, ["mobile_number", "workEmail"])
        XCTAssertEqual(state.verifiedAttributes, [:])
        XCTAssertEqual(state.sendableAttributes, ["workEmail"])
        XCTAssertEqual(state.sentVerification, result)
        state.onSendVerification?("mobile_number")
        state.onSendVerification?("given_name")
        state.onSendVerification?("workEmail")
        XCTAssertEqual(sent, ["workEmail"])
    }

    func testListsAVerifiedEmailWithItsRecord() throws {
        let state = try capture { content in
            BaseUserDetails(
                user: try? self.user(verified: #"{"workEmail":{"verifiedAt":"2026-11-03T10:00:00Z"}}"#),
                content: content
            )
        }

        XCTAssertEqual(state.verifiableAttributes, ["workEmail"])
        XCTAssertEqual(state.verifiedAttributes?["workEmail"]?.verifiedAt, "2026-11-03T10:00:00Z")
        XCTAssertNil(state.onSendVerification, "Sending stays off unless the app turns it on")
    }

    func testListsNothingWhenTheServerDoesNotReportVerification() throws {
        let state = try capture { content in
            BaseUserDetails(user: try? self.user(verified: nil), onSendVerification: { _ in }, content: content)
        }

        XCTAssertEqual(state.verifiableAttributes, [])
        XCTAssertNil(state.verifiedAttributes)
    }

    func testListsNoHiddenAttribute() throws {
        let state = try capture { content in
            BaseUserDetails(user: try? self.user(), userSchema: self.schema, hiddenAttributes: ["workEmail"], content: content)
        }

        XCTAssertEqual(state.verifiableAttributes, ["mobile_number"])
    }

    func testOffersNoSendActionForAReadOnlyUser() throws {
        let state = try capture { content in
            BaseUserDetails(
                user: try? self.user(readOnly: true),
                userSchema: self.schema,
                onSendVerification: { _ in },
                content: content
            )
        }

        XCTAssertEqual(state.verifiableAttributes, ["mobile_number", "workEmail"])
        XCTAssertNil(state.onSendVerification)
    }
    func testSuppressesCustomSendWhileSavingOrSending() throws {
        for (saving, sending) in [(true, false), (false, true)] {
            let state = try capture { content in
                BaseUserDetails(
                    user: try? self.user(),
                    userSchema: self.schema,
                    isUpdating: saving,
                    isSendingVerification: sending,
                    onSendVerification: { _ in XCTFail("A pending operation must prevent sending") },
                    content: content
                )
            }
            XCTAssertNil(state.onSendVerification)
        }
    }
}
