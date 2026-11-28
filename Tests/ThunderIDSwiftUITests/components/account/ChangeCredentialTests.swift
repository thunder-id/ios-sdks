// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

final class ChangeCredentialTests: XCTestCase {
    // MARK: - evaluateCredentialForm

    func testInvalidWhenNewValueEmpty() {
        let result = evaluateCredentialForm(newValue: "", confirm: "", regex: nil)
        XCTAssertFalse(result.isValid)
    }

    func testInvalidWhenConfirmMismatch() {
        let result = evaluateCredentialForm(newValue: "n3wValue!", confirm: "typo", regex: nil)
        XCTAssertFalse(result.confirmMatches)
        XCTAssertFalse(result.isValid)
    }

    func testValidWithNoPolicy() {
        let result = evaluateCredentialForm(newValue: "n3wValue!", confirm: "n3wValue!", regex: nil)
        XCTAssertFalse(result.patternChecked)
        XCTAssertTrue(result.isValid)
    }

    func testAppliesRegexPolicy() {
        let regex = "^.{8,}$"
        let short = evaluateCredentialForm(newValue: "short", confirm: "short", regex: regex)
        XCTAssertTrue(short.patternChecked)
        XCTAssertFalse(short.patternPassed)
        XCTAssertFalse(short.isValid)

        let long = evaluateCredentialForm(newValue: "longEnough1", confirm: "longEnough1", regex: regex)
        XCTAssertTrue(long.patternPassed)
        XCTAssertTrue(long.isValid)
    }

    func testTreatsUncompilableRegexAsPassing() {
        let result = evaluateCredentialForm(newValue: "anything", confirm: "anything", regex: "([)")
        XCTAssertTrue(result.patternPassed)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - mapCredentialError

    private func serverFailure(_ code: ThunderIDErrorCode, _ serverCode: String, message: String? = nil) -> ThunderIDError {
        ThunderIDError(
            code: code,
            message: "failed",
            serverError: ServerError(code: serverCode, message: message.map { ServerErrorMessage(defaultValue: $0) })
        )
    }

    func testMapsBadRequestToNewField() {
        let error = ThunderIDError(code: .invalidInput, message: "Bad request")
        XCTAssertEqual(mapCredentialError(error), .new)
    }

    func testMapsAMissingOrWrongCurrentValueToTheCurrentField() {
        XCTAssertEqual(mapCredentialError(serverFailure(.invalidInput, "USR-1047")), .current)
        XCTAssertEqual(mapCredentialError(serverFailure(.forbidden, "USR-1048")), .current)
    }

    func testMapsARecentSignInRequestToFormLevel() {
        XCTAssertEqual(mapCredentialError(serverFailure(.authenticationFailed, "AUTH-4011")), .form)
        let headerOnly = ThunderIDError(
            code: .authenticationFailed,
            message: "Unauthorized",
            authenticationChallenge: AuthenticationChallenge(error: "insufficient_user_authentication")
        )
        XCTAssertEqual(mapCredentialError(headerOnly), .form)
        XCTAssertTrue(credentialNeedsReauthentication(headerOnly))
    }

    func testMapsOtherFailuresToFormLevel() {
        XCTAssertEqual(mapCredentialError(ThunderIDError(code: .serverError, message: "boom")), .form)
        XCTAssertEqual(mapCredentialError(NSError(domain: "x", code: 1)), .form)
    }

    // MARK: - credentialErrorTemplate

    func testUsesTranslatedTextForTheCodesTheFormKnows() {
        let i18n = ThunderIDI18n(language: "en-US")
        let text = { (error: Error) in
            substituteCredential(credentialErrorTemplate(error) { i18n.resolve($0) }, "Password")
        }
        XCTAssertEqual(text(serverFailure(.invalidInput, "USR-1047")), "Enter your current password.")
        XCTAssertEqual(text(serverFailure(.forbidden, "USR-1048")), "The current password is incorrect.")
        XCTAssertEqual(text(serverFailure(.authenticationFailed, "AUTH-4011")), "Sign in again to set your password.")
    }

    func testUsesTheServersMessageElseTheGenericText() {
        let i18n = ThunderIDI18n(language: "en-US")
        let resolve = { (key: String) in i18n.resolve(key) }
        let readable = serverFailure(.invalidInput, "USR-1017", message: "Missing credentials")
        XCTAssertEqual(credentialErrorTemplate(readable, resolve: resolve), "Missing credentials")
        XCTAssertEqual(
            credentialErrorTemplate(NSError(domain: "x", code: 1), resolve: resolve),
            i18n.resolve("changeCredential.generic.error")
        )
    }

    // MARK: - helpers

    func testSubstituteCredentialReplacesPlaceholders() {
        let resolved = substituteCredential("Change {credential} ({credentialLower})", "PIN")
        XCTAssertEqual(resolved, "Change PIN (pin)")
    }

    func testTitleCasedCredential() {
        XCTAssertEqual(titleCasedCredential("pin"), "Pin")
        XCTAssertEqual(titleCasedCredential("password"), "Password")
    }
}

#if canImport(AppKit)
import AppKit
import SwiftUI

/// The rendered form and the requests `BaseChangeCredential` sends, against a mocked server.
@MainActor
final class ChangeCredentialFormTests: XCTestCase {
    private final class Captured {
        var state: ChangeCredentialState?
        var maxAges: [Int?] = []
        var reauthentications: [Int?] = []
        var bodies: [[String: Any]] = []
    }

    private struct Reply {
        var status = 204
        var body = ""
        var headers: [String: String]?
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private static func body(of request: URLRequest) -> [String: Any]? {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                guard read > 0 else { break }
                data.append(buffer, count: read)
            }
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func host<V: View>(_ view: V) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderBack(nil)
        return window
    }

    /// Mounts a custom-rendered `BaseChangeCredential` whose update requests get `replies` in turn (the last
    /// repeats). With `override`, the app handles a step-up itself; otherwise the view signs in again
    /// through `reauthenticate`.
    private func mount(
        _ captured: Captured,
        replies: [Reply],
        override: Bool = true,
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
        MockURLProtocol.handler = { request in
            var answer = Reply(status: 200, body: #"{"schema":{"password":{"credential":true}}}"#)
            if request.url?.path == "/users/me/update-credentials" {
                captured.bodies.append(Self.body(of: request) ?? [:])
                answer = replies[min(captured.bodies.count, replies.count) - 1]
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: answer.status,
                httpVersion: nil,
                headerFields: answer.headers
            )!
            return (response, Data(answer.body.utf8))
        }
        let i18n = ThunderIDI18n(language: "en-US")
        let thunderState = ThunderIDState(client: client, i18n: i18n)
        thunderState.reauthenticate = { maxAge in
            captured.reauthentications.append(maxAge)
            try await reauthenticate(maxAge)
        }
        let onReauthenticationRequired: ((Int?) -> Void)? = override ? { captured.maxAges.append($0) } : nil
        let view = BaseChangeCredential(onReauthenticationRequired: onReauthenticationRequired) { state in
            let _ = (captured.state = state)
            Text(state.credentialDisplayName)
        }
        .environmentObject(thunderState)
        .environmentObject(i18n)
        let window = host(view)
        try await waitUntil { MockURLProtocol.requestCount(forPath: "/users/me/meta") > 0 }
        try await Task.sleep(nanoseconds: 50_000_000)
        return window
    }

    private func submit(_ state: ChangeCredentialState, current: String) async throws {
        let before = MockURLProtocol.requestCount(forPath: "/users/me/update-credentials")
        state.currentValue = current
        state.newValue = "n3wValue!"
        state.confirmValue = "n3wValue!"
        state.submit()
        try await waitUntil {
            MockURLProtocol.requestCount(forPath: "/users/me/update-credentials") > before && !state.loading
        }
    }

    func testSendsTheCurrentValueOnlyWhenFilled() async throws {
        let captured = Captured()
        let window = try await mount(captured, replies: [Reply()])
        defer { window.close() }
        let state = try XCTUnwrap(captured.state)

        try await submit(state, current: "")
        try await submit(state, current: "0ldValue!")

        XCTAssertEqual(captured.bodies.count, 2)
        XCTAssertEqual(captured.bodies[0] as NSDictionary, ["name": "password", "newValue": "n3wValue!"])
        XCTAssertEqual(
            captured.bodies[1] as NSDictionary,
            ["name": "password", "currentValue": "0ldValue!", "newValue": "n3wValue!"]
        )
        XCTAssertTrue(state.success)
        XCTAssertEqual(state.currentValue, "")
    }

    func testShowsAWrongCurrentValueOnTheCurrentField() async throws {
        let captured = Captured()
        let reply = Reply(status: 403, body: #"{"code":"USR-1048","message":{"defaultValue":"Invalid current credential"}}"#)
        let window = try await mount(captured, replies: [reply])
        defer { window.close() }
        let state = try XCTUnwrap(captured.state)

        try await submit(state, current: "wrong")

        XCTAssertEqual(state.fieldError(.current), "The current password is incorrect.")
        XCTAssertNil(state.error)
        XCTAssertTrue(captured.maxAges.isEmpty)
    }

    func testAsksForASignInAgainAtFormLevel() async throws {
        let captured = Captured()
        let reply = Reply(
            status: 401,
            body: #"{"code":"AUTH-4011","message":{"defaultValue":"Recent authentication required"}}"#,
            headers: ["WWW-Authenticate": #"Bearer error="insufficient_user_authentication", max_age="300""#]
        )
        let window = try await mount(captured, replies: [reply])
        defer { window.close() }
        let state = try XCTUnwrap(captured.state)

        try await submit(state, current: "")

        XCTAssertEqual(state.error, "Sign in again to set your password.")
        XCTAssertNil(state.fieldError(.current))
        XCTAssertEqual(captured.maxAges, [300])
        XCTAssertTrue(captured.reauthentications.isEmpty, "The app's callback replaces the sign-in again")
    }

    private let stepUp = Reply(
        status: 401,
        body: #"{"code":"AUTH-4011","message":{"defaultValue":"Recent authentication required"}}"#,
        headers: ["WWW-Authenticate": #"Bearer error="insufficient_user_authentication", max_age="300""#]
    )

    func testSignsInAgainAndRetriesTheSameChangeOnce() async throws {
        let captured = Captured()
        let window = try await mount(captured, replies: [stepUp, Reply()], override: false)
        defer { window.close() }
        let state = try XCTUnwrap(captured.state)

        try await submit(state, current: "")

        XCTAssertEqual(captured.reauthentications, [300])
        XCTAssertEqual(captured.bodies.count, 2)
        XCTAssertEqual(captured.bodies[1] as NSDictionary, captured.bodies[0] as NSDictionary)
        XCTAssertTrue(state.success)
        XCTAssertNil(state.error)
    }

    func testShowsTheMessageWhenTheRetryIsRefusedAgain() async throws {
        let captured = Captured()
        let window = try await mount(captured, replies: [stepUp], override: false)
        defer { window.close() }
        let state = try XCTUnwrap(captured.state)

        try await submit(state, current: "")

        XCTAssertEqual(captured.reauthentications, [300])
        XCTAssertEqual(captured.bodies.count, 2, "One retry only")
        XCTAssertEqual(state.error, "Sign in again to set your password.")
        XCTAssertFalse(state.success)
    }

    func testShowsTheMessageWhenTheSignInAgainFails() async throws {
        let captured = Captured()
        struct Cancelled: Error {}
        let window = try await mount(captured, replies: [stepUp, Reply()], override: false) { _ in throw Cancelled() }
        defer { window.close() }
        let state = try XCTUnwrap(captured.state)

        try await submit(state, current: "")

        XCTAssertEqual(captured.bodies.count, 1, "No retry without a new sign-in")
        XCTAssertEqual(state.error, "Sign in again to set your password.")
        XCTAssertEqual(state.newValue, "n3wValue!", "The entered change stays in memory")
    }

    func testTheBuiltInFormRendersTheCurrentFieldAboveTheNewValue() async throws {
        let i18n = ThunderIDI18n(language: "en-US")
        let state = ChangeCredentialState(credentialDisplayName: "Password")
        let window = host(ChangeCredentialSheet(state: state, i18n: i18n))
        defer { window.close() }
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(
            Self.placeholders(in: window.contentView),
            ["Current Password", "New Password", "Confirm New Password"]
        )
    }

    /// The placeholders of the rendered text fields, in view order.
    private static func placeholders(in root: NSView?) -> [String] {
        guard let root else { return [] }
        var result: [String] = []
        if let field = root as? NSTextField, let placeholder = field.placeholderString { result.append(placeholder) }
        for child in root.subviews { result += placeholders(in: child) }
        return result
    }
}
#endif
