// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

final class UserProfileFieldsTests: XCTestCase {
    // MARK: - buildProfileFields

    func testBuildProfileFieldsFiltersCredentialAttributes() {
        let schema: [String: AttributeSchema] = [
            "password": AttributeSchema(credential: true, type: "STRING"),
            "email": AttributeSchema(credential: false, type: "STRING")
        ]
        let profile = ThunderID.UserProfile(id: "u1", attributes: ["email": AnyCodable("a@b.com")])
        let fields = buildProfileFields(schema: schema, profile: profile)
        XCTAssertEqual(fields.map(\.name), ["email"])
    }

    func testBuildProfileFieldsMarksReadonlyFromSchemaFlag() {
        let schema: [String: AttributeSchema] = ["email": AttributeSchema(readOnly: true, type: "STRING")]
        let profile = ThunderID.UserProfile(id: "u1", attributes: [:])
        let fields = buildProfileFields(schema: schema, profile: profile)
        XCTAssertEqual(fields.first?.isReadonly, true)
    }

    func testBuildProfileFieldsMarksReadonlyFromMutability() {
        let schema: [String: AttributeSchema] = ["email": AttributeSchema(mutability: "READ_ONLY", type: "STRING")]
        let profile = ThunderID.UserProfile(id: "u1", attributes: [:])
        let fields = buildProfileFields(schema: schema, profile: profile)
        XCTAssertEqual(fields.first?.isReadonly, true)
    }

    func testBuildProfileFieldsMarksReadonlyFromFixedList() {
        let schema: [String: AttributeSchema] = ["username": AttributeSchema(type: "STRING")]
        let profile = ThunderID.UserProfile(id: "u1", attributes: [:])
        let fields = buildProfileFields(schema: schema, profile: profile)
        XCTAssertEqual(fields.first?.isReadonly, true)
    }

    func testBuildProfileFieldsLeavesOrdinaryAttributesEditable() {
        let schema: [String: AttributeSchema] = ["nickname": AttributeSchema(type: "STRING")]
        let profile = ThunderID.UserProfile(id: "u1", attributes: [:])
        let fields = buildProfileFields(schema: schema, profile: profile)
        XCTAssertEqual(fields.first?.isReadonly, false)
    }

    // MARK: - formatClaim

    func testFormatClaimReturnsNilForEmptyString() {
        XCTAssertNil(formatClaim(""))
    }

    func testFormatClaimReturnsStringAsIs() {
        XCTAssertEqual(formatClaim("Alice"), "Alice")
    }

    func testFormatClaimFormatsBooleanAsYesNo() {
        XCTAssertEqual(formatClaim(true), "Yes")
        XCTAssertEqual(formatClaim(false), "No")
    }

    func testFormatClaimFormatsNumbers() {
        XCTAssertEqual(formatClaim(42), "42")
    }

    func testFormatClaimJoinsAList() {
        let list = [AnyCodable("a"), AnyCodable("b")]
        XCTAssertEqual(formatClaim(list), "a, b")
    }

    func testFormatClaimDropsNestedMap() {
        let nested = ["level": AnyCodable("AAL1")]
        XCTAssertNil(formatClaim(nested))
    }

    // MARK: - claimLabel

    func testClaimLabelHumanizesSnakeCase() {
        XCTAssertEqual(claimLabel("given_name"), "Given Name")
    }

    func testClaimLabelHumanizesCamelCase() {
        XCTAssertEqual(claimLabel("givenName"), "Given Name")
    }

    // MARK: - claimsDisplayName

    func testClaimsDisplayNameReturnsGuestForNilUser() {
        XCTAssertEqual(claimsDisplayName(nil), "Guest")
    }

    func testClaimsDisplayNamePrefersGivenAndFamilyName() {
        let user = User(claims: ["given_name": AnyCodable("Ada"), "family_name": AnyCodable("Lovelace")])
        XCTAssertEqual(claimsDisplayName(user), "Ada Lovelace")
    }

    func testClaimsDisplayNameFallsBackToUsername() {
        let user = User(claims: ["username": AnyCodable("ada")])
        XCTAssertEqual(claimsDisplayName(user), "ada")
    }

    func testClaimsDisplayNameFallsBackToGuestWhenNothingAvailable() {
        let user = User(claims: ["sub": AnyCodable("abc")])
        XCTAssertEqual(claimsDisplayName(user), "Guest")
    }

    // MARK: - buildProfileFieldsFromClaims

    func testBuildProfileFieldsFromClaimsDropsReservedClaims() {
        let user = User(claims: ["sub": AnyCodable("abc"), "given_name": AnyCodable("Ada")])
        let fields = buildProfileFieldsFromClaims(user)
        XCTAssertEqual(fields.map(\.name), ["given_name"])
        XCTAssertTrue(fields.allSatisfy(\.isReadonly))
    }

    func testBuildProfileFieldsFromClaimsDropsNestedObjectClaims() {
        let user = User(claims: [
            "given_name": AnyCodable("Ada"),
            "assurance": AnyCodable(["level": AnyCodable("AAL1")])
        ])
        let fields = buildProfileFieldsFromClaims(user)
        XCTAssertEqual(fields.map(\.name), ["given_name"])
    }

    // MARK: - validateField

    func testValidateFieldRejectsBlankRequiredValue() {
        let schema = AttributeSchema(required: true)
        XCTAssertEqual(validateField(schema, "  "), "userProfile.validation.required")
    }

    func testValidateFieldAcceptsNonBlankRequiredValue() {
        let schema = AttributeSchema(required: true)
        XCTAssertNil(validateField(schema, "value"))
    }

    func testValidateFieldRejectsValueNotMatchingRegex() {
        let schema = AttributeSchema(regex: "^[0-9]+$")
        XCTAssertEqual(validateField(schema, "abc"), "userProfile.validation.pattern")
    }

    func testValidateFieldAcceptsValueMatchingRegex() {
        let schema = AttributeSchema(regex: "^[0-9]+$")
        XCTAssertNil(validateField(schema, "123"))
    }

    func testValidateFieldIgnoresInvalidRegexPattern() {
        let schema = AttributeSchema(regex: "([")
        XCTAssertNil(validateField(schema, "anything"))
    }

    // MARK: - mapAttribute / computeDisplayName

    func testMapAttributeUsesDefaultMappingFallbackOrder() {
        let profile = ThunderID.UserProfile(id: "u1", attributes: ["given_name": AnyCodable("Ada")])
        XCTAssertEqual(mapAttribute("firstName", [:], profile), "Ada")
    }

    func testMapAttributeUsesCustomMappingOverDefault() {
        let profile = ThunderID.UserProfile(id: "u1", attributes: ["nick": AnyCodable("Ace")])
        XCTAssertEqual(mapAttribute("firstName", ["firstName": ["nick"]], profile), "Ace")
    }

    func testMapAttributeFallsBackToDirectAttributeWhenNoMappingExists() {
        let profile = ThunderID.UserProfile(id: "u1", attributes: ["department": AnyCodable("Eng")])
        XCTAssertEqual(mapAttribute("department", [:], profile), "Eng")
    }

    func testComputeDisplayNameCombinesFirstAndLastName() {
        let profile = ThunderID.UserProfile(
            id: "u1",
            attributes: ["given_name": AnyCodable("Ada"), "family_name": AnyCodable("Lovelace")]
        )
        XCTAssertEqual(computeDisplayName([:], profile), "Ada Lovelace")
    }

    func testComputeDisplayNameFallsBackToId() {
        let profile = ThunderID.UserProfile(id: "u1", attributes: [:])
        XCTAssertEqual(computeDisplayName([:], profile), "u1")
    }

    // MARK: - stringifyFieldValue

    func testStringifyFieldValueHandlesNil() {
        XCTAssertEqual(stringifyFieldValue(nil), "")
    }

    func testStringifyFieldValueJoinsList() {
        XCTAssertEqual(stringifyFieldValue([AnyCodable("a"), AnyCodable("b")]), "a, b")
    }

    func testStringifyFieldValueBlanksOutComplexMap() {
        XCTAssertEqual(stringifyFieldValue(["k": AnyCodable("v")]), "")
    }

    func testStringifyFieldValueConvertsScalar() {
        XCTAssertEqual(stringifyFieldValue("hello"), "hello")
    }

    // MARK: - buildUpdatePayload / deepMergeAttributes

    func testBuildUpdatePayloadBuildsNestedDotPath() {
        let payload = buildUpdatePayload("name.givenName", "Ada", false)
        let name = payload["name"] as? [String: Any]
        XCTAssertEqual(name?["givenName"] as? String, "Ada")
    }

    func testBuildUpdatePayloadSplitsMultiValuedField() {
        let payload = buildUpdatePayload("tags", "a, b, c", true)
        XCTAssertEqual(payload["tags"] as? [String], ["a", "b", "c"])
    }

    func testDeepMergeAttributesMergesNestedDictionariesRecursively() {
        let base: [String: Any] = ["name": ["givenName": "Ada", "familyName": "Lovelace"]]
        let overrides: [String: Any] = ["name": ["givenName": "Grace"]]
        let merged = deepMergeAttributes(base, overrides)
        let name = merged["name"] as? [String: Any]
        XCTAssertEqual(name?["givenName"] as? String, "Grace")
        XCTAssertEqual(name?["familyName"] as? String, "Lovelace")
    }

    func testDeepMergeAttributesOverwritesScalarValues() {
        let base: [String: Any] = ["email": "old@example.com"]
        let overrides: [String: Any] = ["email": "new@example.com"]
        let merged = deepMergeAttributes(base, overrides)
        XCTAssertEqual(merged["email"] as? String, "new@example.com")
    }

    // MARK: - isPictureField

    func testIsPictureFieldMatchesEverySharedPictureClaimCandidateCaseInsensitively() {
        for candidate in pictureClaimKeys {
            XCTAssertTrue(isPictureField(candidate), "expected '\(candidate)' to match")
            XCTAssertTrue(isPictureField(candidate.uppercased()), "expected '\(candidate.uppercased())' to match")
        }
    }

    func testIsPictureFieldDoesNotMatchAnUnrelatedAttributeName() {
        XCTAssertFalse(isPictureField("firstName"))
        XCTAssertFalse(isPictureField("email"))
    }
}

#if canImport(AppKit)
import AppKit
import SwiftUI

/// A profile save that needs a more recent sign-in signs the user in again and retries once.
@MainActor
final class UserProfileStepUpTests: XCTestCase {
    private final class Captured {
        var state: UserProfileState?
        var puts = 0
        var reauthentications: [Int?] = []
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private let profileBody = #"{"id":"u1","isReadOnly":false,"attributes":{"email":"a@example.com"}}"#
    private let stepUpBody = #"{"code":"AUTH-4011","description":{"params":{"maxAge":"300"}}}"#

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Mounts a custom-rendered `BaseUserProfile`; `PUT /users/me` is refused with a step-up `refusals` times.
    private func mount(
        _ captured: Captured,
        refusals: Int,
        reauthenticate: @escaping (Int?) async throws -> Void = { _ in }
    ) async throws -> NSWindow {
        let storage = InMemoryStorageAdapter()
        storage.store(key: "thunder.access_token", value: "user-token")
        let client = ThunderIDClient()
        _ = try await client.initialize(
            config: ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "c"),
            storage: storage,
            session: MockURLProtocol.makeSession()
        )
        MockURLProtocol.handler = { [profileBody, stepUpBody] request in
            var (status, body) = (200, profileBody)
            switch (request.url?.path, request.httpMethod) {
            case ("/users/me/meta", _): body = #"{"schema":{"email":{"type":"email"}}}"#
            case ("/users/me", "PUT"):
                captured.puts += 1
                if captured.puts <= refusals { (status, body) = (401, stepUpBody) }
            default: break
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        let i18n = ThunderIDI18n(language: "en-US")
        let thunderState = ThunderIDState(client: client, i18n: i18n)
        thunderState.reauthenticate = { maxAge in
            captured.reauthentications.append(maxAge)
            try await reauthenticate(maxAge)
        }
        let view = BaseUserProfile { profile in
            let _ = (captured.state = profile)
            Text(profile.displayName)
        }
        .environmentObject(thunderState)
        .environmentObject(i18n)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderBack(nil)
        try await waitUntil { captured.state?.fields.isEmpty == false }
        return window
    }

    private func saveEmail(_ captured: Captured) async throws -> UserProfileState {
        let state = try XCTUnwrap(captured.state)
        state.edit("email")
        state.setFieldValue("email", "new@example.com")
        state.save("email")
        try await waitUntil { captured.puts > 0 && !state.isLoading }
        try await Task.sleep(nanoseconds: 20_000_000)
        return state
    }

    func testSignsInAgainAndRetriesTheSaveOnce() async throws {
        let captured = Captured()
        let window = try await mount(captured, refusals: 1)
        defer { window.close() }

        let state = try await saveEmail(captured)

        XCTAssertEqual(captured.reauthentications, [300])
        XCTAssertEqual(captured.puts, 2)
        XCTAssertNil(state.fieldError("email"))
        XCTAssertFalse(state.isEditing("email"))
    }

    func testAsksToSignInAgainWhenRefusedAgain() async throws {
        let captured = Captured()
        let window = try await mount(captured, refusals: 2)
        defer { window.close() }

        let state = try await saveEmail(captured)

        XCTAssertEqual(captured.puts, 2, "One retry only")
        XCTAssertEqual(state.fieldError("email"), "Sign in again to save this change.")
        XCTAssertTrue(state.isEditing("email"))
    }

    func testAsksToSignInAgainWhenTheSignInAgainFails() async throws {
        let captured = Captured()
        struct OtherUser: Error {}
        let window = try await mount(captured, refusals: 1) { _ in throw OtherUser() }
        defer { window.close() }

        let state = try await saveEmail(captured)

        XCTAssertEqual(captured.puts, 1)
        XCTAssertEqual(state.fieldError("email"), "Sign in again to save this change.")
        XCTAssertEqual(state.fieldValue(try XCTUnwrap(state.fields.first)), "new@example.com")
    }
}
#endif
