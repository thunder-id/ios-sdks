// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Verification status and the verify action in the user profile.
final class UserProfileVerificationTests: XCTestCase {
    private let schema: [String: AttributeSchema] = [
        "email": AttributeSchema(type: "email"),
        "mobile": AttributeSchema(type: "mobile"),
        "given_name": AttributeSchema(type: "string"),
        "emails": AttributeSchema(type: "array")
    ]

    private func field(
        _ name: String,
        _ attributes: [String: AnyCodable] = [
            "email": AnyCodable("a@example.com"),
            "mobile": AnyCodable("+94771234567"),
            "given_name": AnyCodable("Ada"),
            "emails": AnyCodable([AnyCodable("a@example.com")])
        ]
    ) -> ProfileField {
        let profile = ThunderID.UserProfile(id: "u1", attributes: attributes)
        return buildProfileFields(schema: schema, profile: profile).first { $0.name == name }!
    }

    // MARK: - Status

    func testNoStatusWhenTheServerDoesNotReportVerification() {
        XCTAssertNil(verificationStatus(of: field("email"), in: nil, isEditing: false))
        XCTAssertNil(verificationStatus(of: field("mobile"), in: nil, isEditing: false))
    }

    func testVerifiedOrUnverifiedForStoredEmailAndMobile() {
        let verified = ["email": VerifiedAttribute(verifiedAt: "2026-10-25T10:00:00Z")]

        XCTAssertEqual(
            verificationStatus(of: field("email"), in: verified, isEditing: false),
            .verified(verifiedAt: "2026-10-25T10:00:00Z")
        )
        XCTAssertEqual(verificationStatus(of: field("mobile"), in: verified, isEditing: false), .unverified)
        XCTAssertEqual(verificationStatus(of: field("email"), in: [:], isEditing: false), .unverified)
    }

    func testNoStatusForOtherAttributesEmptyValuesOrAFieldBeingEdited() {
        XCTAssertNil(verificationStatus(of: field("given_name"), in: [:], isEditing: false))
        XCTAssertNil(verificationStatus(of: field("emails"), in: [:], isEditing: false))
        XCTAssertNil(verificationStatus(of: field("email", ["email": AnyCodable(" ")]), in: [:], isEditing: false))
        XCTAssertNil(verificationStatus(of: field("email", [:]), in: [:], isEditing: false))
        XCTAssertNil(verificationStatus(of: field("email"), in: [:], isEditing: true))
    }

    // MARK: - After a save

    private func saved(_ email: String, verified: [String: VerifiedAttribute]?) -> ThunderID.UserProfile {
        ThunderID.UserProfile(id: "u1", attributes: ["email": AnyCodable(email)], verifiedAttributes: verified)
    }

    func testAChangedUnverifiedEmailOpensVerification() {
        XCTAssertTrue(opensVerificationAfterSave(
            field("email"),
            previousValue: "a@example.com",
            savedValue: "b@example.com",
            savedProfile: saved("b@example.com", verified: [:])
        ))
    }

    func testNothingOpensForAnUnchangedOrVerifiedEmailOrAnUnknownStatus() {
        let email = field("email")
        XCTAssertFalse(opensVerificationAfterSave(
            email, previousValue: "a@example.com", savedValue: "a@example.com",
            savedProfile: saved("a@example.com", verified: [:])
        ))
        XCTAssertFalse(opensVerificationAfterSave(
            email, previousValue: "a@example.com", savedValue: "b@example.com",
            savedProfile: saved("b@example.com", verified: ["email": VerifiedAttribute()])
        ))
        XCTAssertFalse(opensVerificationAfterSave(
            email, previousValue: "a@example.com", savedValue: "b@example.com",
            savedProfile: saved("b@example.com", verified: nil)
        ))
        XCTAssertFalse(opensVerificationAfterSave(
            email, previousValue: "a@example.com", savedValue: "b@example.com",
            savedProfile: saved("a@example.com", verified: [:])
        ))
    }

    func testSaveCannotOpenVerificationForReadOnlyProfileOrField() {
        let email = field("email")
        let readonly = ProfileField(
            name: email.name, schema: email.schema, rawValue: email.rawValue, isReadonly: true, isMultiValued: false
        )
        XCTAssertFalse(opensVerificationAfterSave(
            readonly, previousValue: "a@example.com", savedValue: "b@example.com",
            savedProfile: saved("b@example.com", verified: [:])
        ))
        XCTAssertFalse(opensVerificationAfterSave(
            email, previousValue: "a@example.com", savedValue: "b@example.com",
            savedProfile: ThunderID.UserProfile(
                id: "u1", attributes: ["email": AnyCodable("b@example.com")], isReadOnly: true, verifiedAttributes: [:]
            )
        ))
    }

    func testAChangedMobileDoesNotOpenVerification() {
        let profile = ThunderID.UserProfile(id: "u1", attributes: ["mobile": AnyCodable("+2")], verifiedAttributes: [:])
        XCTAssertFalse(opensVerificationAfterSave(
            field("mobile"), previousValue: "+1", savedValue: "+2", savedProfile: profile
        ))
    }
}
