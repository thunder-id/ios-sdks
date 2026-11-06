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
}
