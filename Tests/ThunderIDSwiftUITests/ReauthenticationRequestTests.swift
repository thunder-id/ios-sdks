// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers the re-sign-in a session from an embedded sign-in gets: `performWithStepUp` opens a request the
/// provider shows as a sheet, waits for it, and retries once it completes.
@MainActor
final class ReauthenticationRequestTests: XCTestCase {
    private func makeState(embedded: Bool = true) async throws -> ThunderIDState {
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "test-client", applicationId: "app-1")
        let storage = InMemoryStorageAdapter()
        storage.store(key: "thunder.access_token", value: "test-access-token")
        if embedded { storage.store(key: "thunder.embedded_sign_in", value: "true") }
        let client = ThunderIDClient()
        _ = try await client.initialize(config: config, storage: storage, session: MockURLProtocol.makeSession())
        return ThunderIDState(client: client, i18n: ThunderIDI18n())
    }

    private func waitForRequest(_ state: ThunderIDState) async throws -> ReauthenticationRequest {
        for _ in 0..<300 where state.reauthenticationRequest == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return try XCTUnwrap(state.reauthenticationRequest)
    }

    private let stepUp = ThunderIDError(
        code: .stepUpRequired,
        message: "Sign in again",
        authenticationChallenge: AuthenticationChallenge(error: "insufficient_user_authentication", maxAge: 180)
    )

    func testRetriesOnceAfterTheSheetSignsTheUserInAgain() async throws {
        let state = try await makeState()
        var calls = 0
        let task = Task { [stepUp] in
            try await state.performWithStepUp(onReauthenticationRequired: nil) {
                calls += 1
                if calls == 1 { throw stepUp }
                return "saved"
            }
        }

        let request = try await waitForRequest(state)
        XCTAssertEqual(request.applicationId, "app-1")
        XCTAssertEqual(request.maxAge, 180)
        state.finishReauthentication(request, .success(()))

        let result = try await task.value
        XCTAssertEqual(result, "saved")
        XCTAssertEqual(calls, 2)
        XCTAssertNil(state.reauthenticationRequest)
    }

    func testClosingTheSheetFailsWithTheStepUpErrorAndDoesNotRetry() async throws {
        let state = try await makeState()
        var calls = 0
        let task = Task { [stepUp] in
            try await state.performWithStepUp(onReauthenticationRequired: nil) {
                calls += 1
                throw stepUp
            }
        }

        let request = try await waitForRequest(state)
        state.finishReauthentication(request, .failure(ThunderIDState.reauthenticationCancelled))

        do {
            _ = try await task.value
            XCTFail("Expected the step-up error")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .stepUpRequired)
        }
        XCTAssertEqual(calls, 1)
    }

    func testANewRequestEndsTheOneStillOpen() async throws {
        let state = try await makeState()
        let first = Task { try await state.reauthenticateWithFlow(maxAge: 30) }
        let firstRequest = try await waitForRequest(state)

        let second = Task { try await state.reauthenticateWithFlow(maxAge: 60) }
        for _ in 0..<300 where state.reauthenticationRequest?.id == firstRequest.id {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        await XCTAssertThrowsErrorAsync { try await first.value }
        XCTAssertEqual(state.reauthenticationRequest?.maxAge, 60)
        // A late completion from the replaced request's sheet leaves the open one waiting.
        state.finishReauthentication(firstRequest, .success(()))
        XCTAssertEqual(state.reauthenticationRequest?.maxAge, 60)
        state.finishReauthentication(try XCTUnwrap(state.reauthenticationRequest), .success(()))
        try await second.value
    }
}

private func XCTAssertThrowsErrorAsync(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        try await body()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
