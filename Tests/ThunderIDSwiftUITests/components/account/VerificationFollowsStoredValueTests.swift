// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Status and the verify action follow the stored value only, and a standalone `VerifyAttribute` reads
/// `/users/me` again itself after `COMPLETE`.
@MainActor
final class VerificationFollowsStoredValueTests: XCTestCase {
    private let schema: [String: AttributeSchema] = ["email": AttributeSchema(type: "email")]

    private func makeProfileState() -> UserProfileState {
        let state = UserProfileState()
        let profile = ThunderID.UserProfile(
            id: "u1",
            attributes: ["email": AnyCodable("a@example.com")],
            verifiedAttributes: [:]
        )
        state.profile = profile
        state.fields = buildProfileFields(schema: schema, profile: profile)
        return state
    }

    private func apply(_ state: UserProfileState) -> (ThunderID.UserProfile) -> Void {
        { [schema] profile in
            state.profile = profile
            state.fields = buildProfileFields(schema: schema, profile: profile)
        }
    }

    func testAnEditedEmailShowsNoStatusOrVerifyWhileTheSaveIsInFlightOrAfterItFails() async throws {
        let state = makeProfileState()
        let stored = try XCTUnwrap(state.fields.first)
        XCTAssertEqual(state.verificationStatus(stored), .unverified)
        XCTAssertTrue(state.canVerify(stored))
        state.editingFields["email"] = true
        state.editedValues["email"] = "typed@example.com"

        var duringSave: (AttributeVerificationStatus?, Bool)?
        do {
            try await state.commitSave(stored, value: "typed@example.com", update: { _ in
                duringSave = (state.verificationStatus(stored), state.canVerify(stored))
                state.verify("email")
                throw ThunderIDError(code: .invalidInput, message: "Rejected")
            }, apply: apply(state))
            XCTFail("Expected the save to fail")
        } catch {}

        XCTAssertNil(duringSave?.0)
        XCTAssertEqual(duringSave?.1, false)
        XCTAssertNil(state.verificationStatus(stored))
        XCTAssertFalse(state.canVerify(stored))
        state.verify("email")
        XCTAssertNil(state.verifyingField)
        XCTAssertEqual(state.profile?.attributes["email"]?.value as? String, "a@example.com")
    }

    func testASavedEmailShowsTheStatusOfTheStoredValueAndOpensItsVerification() async throws {
        let state = makeProfileState()
        let stored = try XCTUnwrap(state.fields.first)
        state.editingFields["email"] = true

        try await state.commitSave(stored, value: "new@example.com", update: { payload in
            XCTAssertEqual(payload["email"] as? String, "new@example.com")
            return ThunderID.UserProfile(
                id: "u1",
                attributes: ["email": AnyCodable("new@example.com")],
                verifiedAttributes: [:]
            )
        }, apply: apply(state))

        let saved = try XCTUnwrap(state.fields.first)
        XCTAssertEqual(saved.rawValue as? String, "new@example.com")
        XCTAssertEqual(state.verificationStatus(saved), .unverified)
        XCTAssertEqual(state.verifyingField, "email")
        XCTAssertFalse(state.canVerify(saved))
    }

    func testVerifyRequiresEditableProfileAndField() throws {
        let state = makeProfileState()
        let field = try XCTUnwrap(state.fields.first)
        XCTAssertTrue(state.canVerify(field))
        state.profile = ThunderID.UserProfile(
            id: "u1", attributes: state.profile!.attributes, isReadOnly: true, verifiedAttributes: [:]
        )
        XCTAssertFalse(state.canVerify(field))
        state.verify("email")
        XCTAssertNil(state.verifyingField)
        state.profile = ThunderID.UserProfile(id: "u1", attributes: state.profile!.attributes, verifiedAttributes: [:])
        let readonly = ProfileField(
            name: "email", schema: field.schema, rawValue: field.rawValue, isReadonly: true, isMultiValued: false
        )
        XCTAssertFalse(state.canVerify(readonly))

    }

    // MARK: - Standalone VerifyAttribute

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testAStandaloneVerificationReadsUsersMeAfterComplete() async throws {
        let storage = InMemoryStorageAdapter()
        storage.store(key: "thunder.access_token", value: "user-token")
        let client = ThunderIDClient()
        _ = try await client.initialize(
            config: ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "c"),
            storage: storage,
            session: MockURLProtocol.makeSession()
        )
        var profileTokens: [String?] = []
        MockURLProtocol.handler = { request in
            let body: String
            switch request.url?.path {
            case "/users/me/meta": body = #"{"schema":{"email":{"type":"email"}}}"#
            case "/flow/execute": body = #"{"executionId":"e","flowStatus":"COMPLETE"}"#
            default:
                profileTokens.append(request.value(forHTTPHeaderField: "Authorization"))
                body = """
                {"id":"u1","attributes":{"email":"a@example.com"},"isReadOnly":false,
                 "verifiedAttributes":{"email":{"verifiedAt":"2026-10-25T10:00:00Z"}}}
                """
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        let thunderState = ThunderIDState(client: client, i18n: ThunderIDI18n())
        let state = VerifyAttributeState(attribute: "email", attributeDisplayName: nil)
        state.engine = .live(thunderState, attribute: "email", flowHandle: AttributeVerification.defaultFlowHandle)

        // No callback: the component reads /users/me itself.
        await state.start()

        XCTAssertEqual(state.phase, .complete)
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/flow/execute"), 1)
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/users/me"), 1)
        XCTAssertEqual(profileTokens, ["Bearer user-token"])
    }

    // MARK: - Custom render

    #if canImport(AppKit)
    private final class Captured {
        var profile: UserProfileState?
        var step: VerifyAttributeState?
        var events: [String] = []
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// A custom-rendered profile opens a custom-rendered `VerifyAttribute`; the step, the status after
    /// `COMPLETE` and the callbacks all come through the SDK's state.
    func testACustomRenderedProfileVerifiesThroughACustomRenderedStep() async throws {
        let storage = InMemoryStorageAdapter()
        storage.store(key: "thunder.access_token", value: "user-token")
        let client = ThunderIDClient()
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "c")
        _ = try await client.initialize(config: config, storage: storage, session: MockURLProtocol.makeSession())
        MockURLProtocol.handler = { request in
            let flowRequests = MockURLProtocol.requestCount(forPath: "/flow/execute")
            let body: String
            switch request.url?.path {
            case "/users/me/meta": body = #"{"schema":{"email":{"type":"email"}}}"#
            case "/flow/execute" where flowRequests == 1:
                body = """
                {"executionId":"e","flowStatus":"INCOMPLETE","challengeToken":"ct",
                 "data":{"inputs":[{"identifier":"otp","type":"OTP_INPUT","required":true}],
                  "additionalData":{"maskedDestination":"a***@example.com"},
                  "meta":{"components":[{"type":"OTP_INPUT","id":"i","ref":"otp"},{"type":"ACTION","id":"verify"}]}}}
                """
            case "/flow/execute": body = #"{"executionId":"e","flowStatus":"COMPLETE"}"#
            default:
                let verified = flowRequests >= 2 ? #"{"email":{"verifiedAt":"2026-10-25T10:00:00Z"}}"# : "{}"
                body = #"{"id":"u1","isReadOnly":false,"attributes":{"email":"a@example.com"},"#
                    + #""verifiedAttributes":\#(verified)}"#
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        let i18n = ThunderIDI18n()
        let thunderState = ThunderIDState(client: client, i18n: i18n)
        // The client is already initialized, so this only marks the state initialized.
        await thunderState.initialize(config: config)
        let captured = Captured()

        let root = BaseUserProfile { profile in
            let _ = (captured.profile = profile)
            VStack {
                ForEach(profile.fields) { field in
                    Text(field.name)
                }
                if let name = profile.verifyingField {
                    VerifyAttribute(
                        attribute: name,
                        onComplete: {
                            let status = profile.fields.first.flatMap(profile.verificationStatus)
                            captured.events.append("onComplete \(String(describing: status))")
                        },
                        onCancel: { captured.events.append("onCancel") }
                    ) { step in
                        let _ = (captured.step = step)
                        Text(step.destination ?? "")
                    }
                    .id(name)
                }
            }
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
        window.contentView = NSHostingView(rootView: root)
        window.orderFront(nil)
        defer { window.close() }

        try await waitUntil { captured.profile?.fields.isEmpty == false }
        let profile = try XCTUnwrap(captured.profile)
        let field = try XCTUnwrap(profile.fields.first)
        XCTAssertEqual(profile.verificationStatus(field), .unverified)
        XCTAssertTrue(profile.canVerify(field))

        profile.verify("email")
        try await waitUntil { captured.step?.phase == .active }
        let step = try XCTUnwrap(captured.step, "The custom render replaces the built-in step")
        XCTAssertEqual(step.destination, "a***@example.com")
        step.onCancel?()
        XCTAssertEqual(captured.events, ["onCancel"])

        step.binding(for: "otp").wrappedValue = "123456"
        step.submit(actionId: "verify")
        try await waitUntil { captured.events.count == 2 }

        XCTAssertEqual(step.phase, .complete)
        // The profile was read again and shown before onComplete.
        XCTAssertEqual(
            captured.events.last,
            "onComplete \(String(describing: Optional(AttributeVerificationStatus.verified(verifiedAt: "2026-10-25T10:00:00Z"))))"
        )
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/flow/execute"), 2, "Started once")
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/users/me"), 2, "One load and one read again")
    }
    func testFailedProfileSaveShowsBundleMessageAndStartsNoVerification() async throws {
        let storage = InMemoryStorageAdapter()
        storage.store(key: "thunder.access_token", value: "user-token")
        let client = ThunderIDClient()
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "c")
        _ = try await client.initialize(config: config, storage: storage, session: MockURLProtocol.makeSession())
        MockURLProtocol.handler = { request in
            let status: Int
            let body: String
            switch (request.url?.path, request.httpMethod) {
            case ("/users/me/meta", _):
                status = 200
                body = #"{"schema":{"email":{"type":"email"}}}"#
            case ("/users/me", "PUT"):
                status = 500
                body = #"{"message":"private server route detail"}"#
            default:
                status = 200
                body = #"{"id":"u1","isReadOnly":false,"attributes":{"email":"a@example.com"},"verifiedAttributes":{}}"#
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        let i18n = ThunderIDI18n(bundles: ["en-US": ["userProfile.error.save": "Translated save failure"]], language: "en-US")
        let thunderState = ThunderIDState(client: client, i18n: i18n)
        let captured = Captured()
        let root = BaseUserProfile(onError: { captured.events.append("error") }) { state in
            let _ = (captured.profile = state)
            Text(state.fieldError("email") ?? "")
        }
        .environmentObject(thunderState)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        window.orderFront(nil)
        defer { window.close() }
        try await waitUntil { captured.profile?.fields.isEmpty == false }
        let state = try XCTUnwrap(captured.profile)
        state.edit("email")
        state.setFieldValue("email", "new@example.com")
        state.save("email")
        try await waitUntil { !captured.events.isEmpty }
        XCTAssertEqual(captured.events, ["error"])
        XCTAssertEqual(state.fieldError("email"), "Translated save failure")
        XCTAssertNil(state.verifyingField)
        XCTAssertTrue(state.isEditing("email"))
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/flow/execute"), 0)
    }
    #endif

    // MARK: - Verified at

    func testTheVerifiedTimeIsFormattedForDisplay() {
        let i18n = ThunderIDI18n(language: "en-US", storageKey: "verification.test.locale")
        let plain = verifiedAtText(.verified(verifiedAt: "2026-10-25T10:00:00Z"), i18n: i18n)
        let fractional = verifiedAtText(.verified(verifiedAt: "2026-10-25T10:00:00.123456Z"), i18n: i18n)

        XCTAssertEqual(plain?.hasPrefix("Verified on "), true)
        XCTAssertEqual(plain?.contains("2026"), true)
        XCTAssertEqual(plain?.contains("T10:00"), false)
        XCTAssertEqual(fractional?.contains("T10:00"), false)
        XCTAssertEqual(verifiedAtText(.verified(verifiedAt: "soon"), i18n: i18n), "Verified on soon")
        XCTAssertNil(verifiedAtText(.verified(verifiedAt: nil), i18n: i18n))
        XCTAssertNil(verifiedAtText(.unverified, i18n: i18n))
    }
}
