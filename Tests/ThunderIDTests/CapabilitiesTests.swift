// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class CapabilitiesTests: XCTestCase {
    private let base = ManagementTestServer.baseUrl
    private let reported = #"{"scope":{"type":"ou","ouId":"ou-1"},"resources":{"app":{"view":true,"create":false}}}"#

    func testReadsTheCapabilitiesFromTheBaseUrl() async throws {
        let server = ManagementTestServer()
        server.resource = reported
        let client = try await server.makeClient()

        let capabilities = try await client.getCapabilities()

        XCTAssertEqual(server.calls, ["GET \(base)/capabilities"])
        XCTAssertEqual(capabilities.scope, CapabilityScope(type: "ou", ouId: "ou-1"))
        XCTAssertEqual(capabilities.resources["app"], ["view": true, "create": false])
    }

    func testTheEndpointOverrideTakesPrecedenceOverTheBaseUrl() async throws {
        let server = ManagementTestServer()
        server.resource = reported
        let client = try await server.makeClient(endpoints: .init(capabilities: "https://api.example.com/caps"))

        _ = try await client.getCapabilities()

        XCTAssertEqual(server.calls, ["GET https://api.example.com/caps"])
    }

    func testAFetcherPassedToTheCallTakesPrecedenceOverTheConfiguredOne() async throws {
        let configured = ManagementTestServer()
        let perCall = ManagementTestServer()
        perCall.resource = reported
        let client = try await configured.makeClient()

        _ = try await client.getCapabilities(fetcher: perCall.fetcher)

        XCTAssertTrue(configured.requests.isEmpty)
        XCTAssertEqual(perCall.calls, ["GET \(base)/capabilities"])
    }

    func testAFailedReadSurfacesTheServerError() async throws {
        let server = ManagementTestServer()
        server.resourceStatus = 500
        server.resource = #"{"code":"SSE-5000","message":"Internal server error"}"#
        let client = try await server.makeClient()

        do {
            _ = try await client.getCapabilities()
            XCTFail("Expected the read to fail")
        } catch {
            XCTAssertTrue(error is ThunderIDError)
        }
    }

    func testCanAnswersOnlyWhatTheServerReportedTrue() throws {
        let capabilities = try JSONDecoder().decode(Capabilities.self, from: Data(reported.utf8))

        XCTAssertTrue(capabilities.can("app"))
        XCTAssertTrue(capabilities.can("app", "view"))
        XCTAssertFalse(capabilities.can("app", "create"))
        XCTAssertFalse(capabilities.can("app", "delete"))
        XCTAssertFalse(capabilities.can("user"))
    }

    func testAnUnknownScopeTypeKeepsItsRawValue() throws {
        let json = #"{"scope":{"type":"tenant"},"resources":{}}"#
        let capabilities = try JSONDecoder().decode(Capabilities.self, from: Data(json.utf8))
        XCTAssertEqual(capabilities.scope.type, "tenant")
        XCTAssertNil(capabilities.scope.ouId)
    }

    // MARK: - Record access

    private func access(_ actions: Set<String>, isReadOnly: Bool? = nil, isOwnedByOU: Bool? = nil) -> RecordAccess {
        RecordAccess(resource: "app", isReadOnly: isReadOnly, isOwnedByOU: isOwnedByOU) { resource, action in
            resource == "app" && actions.contains(action)
        }
    }

    private func assertAccess(
        _ access: RecordAccess,
        readOnly: Bool,
        canDelete: Bool,
        canChangeState: Bool,
        line: UInt = #line
    ) {
        XCTAssertEqual(access.readOnly, readOnly, "readOnly", line: line)
        XCTAssertEqual(access.canDelete, canDelete, "canDelete", line: line)
        XCTAssertEqual(access.canChangeState, canChangeState, "canChangeState", line: line)
    }

    func testAnOwnedUnlockedRecordFollowsTheCapabilities() {
        assertAccess(access(["update", "delete"]), readOnly: false, canDelete: true, canChangeState: true)
        assertAccess(access(["update", "delete"], isReadOnly: false, isOwnedByOU: true),
                     readOnly: false, canDelete: true, canChangeState: true)
        assertAccess(access([]), readOnly: true, canDelete: false, canChangeState: false)
    }

    func testALockedRecordIsReadOnlyButItsStateCanStillChange() {
        assertAccess(access(["update", "delete"], isReadOnly: true), readOnly: true, canDelete: false, canChangeState: true)
    }

    func testASharedInRecordIsReadOnlyAndItsStateCannotChange() {
        assertAccess(access(["update", "delete"], isOwnedByOU: false), readOnly: true, canDelete: false, canChangeState: false)
    }

    func testDeleteWithoutUpdateLeavesTheRecordReadOnlyButDeletable() {
        assertAccess(access(["delete"]), readOnly: true, canDelete: true, canChangeState: false)
    }
}
