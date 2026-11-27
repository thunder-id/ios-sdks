// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
@testable import ThunderID
@testable import ThunderIDSwiftUI
import XCTest

/// A capabilities read the test controls: call N gets `answers[N - 1]`, and waits for
/// ``release(_:)`` while ``holds`` is on.
@MainActor
private final class Reader {
    var answers: [Result<Capabilities, Error>] = []
    var permissions: [String] = ["system"]
    var holds = false
    private(set) var calls = 0
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]

    func read() async throws -> Capabilities {
        calls += 1
        let call = calls
        if holds { await withCheckedContinuation { waiting[call] = $0 } }
        let answer = call <= answers.count ? answers[call - 1] : .success(.everything)
        return try answer.get()
    }

    func release(_ call: Int) {
        waiting.removeValue(forKey: call)?.resume()
    }

    func makeState() -> CapabilitiesState {
        CapabilitiesState(read: { try await self.read() }, grantedPermissions: { self.permissions })
    }
}

private struct ReadFailed: Error {}

@MainActor
final class CapabilitiesStateTests: XCTestCase {
    private let resources = ["app", "user", "group", "role", "agent", "ou", "project", "flow", "serverconfig"]
    private let actions = ["view", "create", "update", "delete"]

    private func settle(_ condition: () -> Bool = { false }) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func testNothingIsReadUntilTheCapabilitiesAreUsed() async {
        let reader = Reader()
        let state = reader.makeState()

        state.setSession(["u-1", "ou-1"])
        await settle()

        XCTAssertEqual(reader.calls, 0)
        XCTAssertFalse(state.can("app"))
    }

    func testCanIsFalseWhileLoadingAndFollowsTheAnswerOnceRead() async {
        let reader = Reader()
        reader.holds = true
        reader.answers = [.success(.allowing(["app": ["view", "update"]]))]
        let state = reader.makeState()
        state.setSession(["u-1", nil])

        state.load()
        await settle { reader.calls == 1 }
        XCTAssertTrue(state.isLoading)
        XCTAssertFalse(state.can("app"))

        reader.release(1)
        await settle { !state.isLoading }
        XCTAssertTrue(state.can("app"))
        XCTAssertTrue(state.can("app", "view"))
        XCTAssertTrue(state.can("app", "update"))
        XCTAssertFalse(state.can("app", "delete"), "an action the server did not report")
        XCTAssertFalse(state.can("user"), "a resource the server did not report")
    }

    func testAFailedReadNeverAllowsAnything() async {
        let reader = Reader()
        reader.answers = [.failure(ReadFailed())]
        let state = reader.makeState()
        state.setSession(["u-1", nil])

        state.load()
        await settle { state.error != nil }

        for resource in resources {
            for action in actions {
                XCTAssertFalse(state.can(resource, action), "\(resource).\(action) after a failed read")
            }
            XCTAssertFalse(state.recordAccess(resource).canDelete)
            XCTAssertFalse(state.recordAccess(resource).canChangeState)
            XCTAssertTrue(state.recordAccess(resource).readOnly)
        }
    }

    func testAFailureIsReportedApartFromADenialAndRetryReadsAgain() async {
        let reader = Reader()
        reader.answers = [.failure(ReadFailed()), .success(.allowing(["app": ["view"]]))]
        let state = reader.makeState()
        state.setSession(["u-1", nil])

        state.load()
        await settle { state.error != nil }
        XCTAssertTrue(state.error is ReadFailed)
        XCTAssertNil(state.capabilities)
        XCTAssertFalse(state.isLoading)

        state.retry()
        await settle { state.capabilities != nil }
        XCTAssertEqual(reader.calls, 2)
        XCTAssertNil(state.error)
        XCTAssertTrue(state.can("app"))
    }

    func testSeveralConsumersShareOneRead() async {
        let reader = Reader()
        reader.holds = true
        let state = reader.makeState()
        state.setSession(["u-1", nil])

        state.load()
        state.load()
        state.load()
        await settle { reader.calls > 0 }
        reader.release(1)
        await settle { state.capabilities != nil }
        state.load()
        await settle()

        XCTAssertEqual(reader.calls, 1)
    }

    func testTheSameSessionAndPermissionsAreNotReadAgain() async {
        let reader = Reader()
        let state = reader.makeState()
        state.setSession(["u-1", "ou-1"])
        state.load()
        await settle { state.capabilities != nil }

        state.setSession(["u-1", "ou-1"])
        await settle()

        XCTAssertEqual(reader.calls, 1)
    }

    func testAnotherUserIsReadAgain() async {
        await assertReadAgain { state, _ in state.setSession(["u-2", "ou-1"]) }
    }

    func testAnotherOrganizationUnitIsReadAgain() async {
        await assertReadAgain { state, _ in state.setSession(["u-1", "ou-2"]) }
    }

    func testOtherGrantedPermissionsAreReadAgain() async {
        await assertReadAgain { state, reader in
            reader.permissions = ["system:user:view"]
            state.setSession(["u-1", "ou-1"])
        }
    }

    private func assertReadAgain(
        line: UInt = #line,
        _ change: (CapabilitiesState, Reader) -> Void
    ) async {
        let reader = Reader()
        reader.answers = [.success(.allowing(["app": ["view"]])), .success(.allowing(["user": ["view"]]))]
        let state = reader.makeState()
        state.setSession(["u-1", "ou-1"])
        state.load()
        await settle { state.capabilities != nil }

        change(state, reader)
        await settle { reader.calls == 2 && !state.isLoading }

        XCTAssertEqual(reader.calls, 2, line: line)
        XCTAssertFalse(state.can("app"), line: line)
        XCTAssertTrue(state.can("user"), line: line)
    }

    func testSigningOutDiscardsTheCapabilitiesAndTheNextSignInReadsThemAgain() async {
        let reader = Reader()
        let state = reader.makeState()
        state.setSession(["u-1", nil])
        state.load()
        await settle { state.capabilities != nil }

        state.setSession(nil)
        XCTAssertNil(state.capabilities)
        XCTAssertNil(state.error)
        XCTAssertFalse(state.can("app"))

        state.setSession(["u-1", nil])
        await settle { reader.calls == 2 && state.capabilities != nil }
        XCTAssertEqual(reader.calls, 2)
    }

    func testAReadSupersededBySignOutIsDiscarded() async {
        let reader = Reader()
        reader.holds = true
        let state = reader.makeState()
        state.setSession(["u-1", nil])
        state.load()
        await settle { reader.calls == 1 }

        state.setSession(nil)
        reader.release(1)
        await settle()

        XCTAssertNil(state.capabilities)
        XCTAssertFalse(state.can("app"))
    }

    func testAReadSupersededByAnotherUserIsDiscarded() async {
        let reader = Reader()
        reader.holds = true
        reader.answers = [.success(.allowing(["app": ["view"]])), .success(.allowing(["user": ["view"]]))]
        let state = reader.makeState()
        state.setSession(["u-1", nil])
        state.load()
        await settle { reader.calls == 1 }

        state.setSession(["u-2", nil])
        await settle { reader.calls == 2 }
        reader.release(2)
        await settle { state.capabilities != nil }
        reader.release(1)
        await settle()

        XCTAssertFalse(state.can("app"), "the first user's answer arrived late")
        XCTAssertTrue(state.can("user"))
    }
}

/// The capabilities through ``ThunderIDState`` and ``CapabilityGuard``, against a mock server.
@MainActor
final class CapabilityGuardTests: XCTestCase {
    private static let baseUrl = "https://localhost:8090"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeState(status: Int = 200, body: String) async throws -> ThunderIDState {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        let storage = InMemoryStorageAdapter()
        try TokenStore(storage: storage).save(
            TokenResponse(accessToken: "admin-token", tokenType: "Bearer", expiresIn: 3600)
        )
        let client = ThunderIDClient()
        _ = try await client.initialize(
            config: ThunderIDConfig(baseUrl: Self.baseUrl, clientId: "test-client"),
            storage: storage,
            session: MockURLProtocol.makeSession()
        )
        let state = ThunderIDState(client: client, i18n: ThunderIDI18n())
        state.capabilities.setSession(["u-1", nil])
        return state
    }

    private func host(_ view: some View, state: ThunderIDState) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view.environmentObject(state.i18n).environmentObject(state))
        window.orderBack(nil)
        return window
    }

    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testSeveralGuardsUnderOneProviderSendOneRequest() async throws {
        let state = try await makeState(body: #"{"scope":{"type":"deployment"},"resources":{"app":{"view":true}}}"#)
        let window = host(
            VStack {
                CapabilityGuard(resource: "app") { Text("apps") }
                CapabilityGuard(resource: "user") { Text("users") }
                CapabilityGuard(anyOf: [CapabilityRequirement("app", "create"), CapabilityRequirement("app")]) {
                    Text("either")
                }
            },
            state: state
        )
        defer { window.close() }

        await settle { state.capabilities.capabilities != nil }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/capabilities"), 1)
        XCTAssertTrue(state.capabilities.can("app"))
    }

    func testAFailedReadIsReportedAsAnErrorNotADenial() async throws {
        let state = try await makeState(status: 500, body: #"{"code":"SSE-5000","message":"Internal server error"}"#)
        let window = host(CapabilityGuard(resource: "app") { Text("apps") }, state: state)
        defer { window.close() }

        await settle { state.capabilities.error != nil }

        XCTAssertNotNil(state.capabilities.error)
        XCTAssertFalse(state.capabilities.can("app"))
    }

    func testTheGuardChecksLoadingThenErrorThenTheCapability() async {
        let guarded = CapabilityGuard(anyOf: [CapabilityRequirement("app", "create"), CapabilityRequirement("user")]) {
            Text("content")
        }
        let reader = Reader()
        reader.holds = true
        reader.answers = [.failure(ReadFailed()), .success(.allowing(["user": ["view"]]))]
        let store = reader.makeState()
        XCTAssertEqual(guarded.phase(store), .denied, "nothing read yet")

        store.setSession(["u-1", nil])
        store.load()
        XCTAssertEqual(guarded.phase(store), .loading)
        await settle { reader.calls == 1 }
        reader.release(1)
        await settle { store.error != nil }
        XCTAssertEqual(guarded.phase(store), .error)

        store.retry()
        await settle { reader.calls == 2 }
        reader.release(2)
        await settle { store.capabilities != nil }
        XCTAssertEqual(guarded.phase(store), .allowed, "any one of the requirements")
        XCTAssertEqual(CapabilityGuard(resource: "app") { Text("content") }.phase(store), .denied)
    }
}
