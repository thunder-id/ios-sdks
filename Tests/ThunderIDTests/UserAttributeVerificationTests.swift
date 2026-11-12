// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Covers sending a user a verification link through the administrator-initiated flow, and which
/// attributes an admin view offers it for.
final class UserAttributeVerificationTests: XCTestCase {
    private let sent = #"{"executionId":"e-1","flowStatus":"INCOMPLETE","type":"VIEW","data":{"additionalData":"#
        + #"{"channel":"email","emailSent":"true","maskedDestination":"t•••@example.com"}}}"#

    private static let configured = #"{"adminAttributeVerificationFlow":{"defaultHandle":"admin-verification"}}"#

    private func user(_ json: String) throws -> ManagedUser {
        try JSONDecoder().decode(ManagedUser.self, from: Data(json.utf8))
    }

    // MARK: - Sending a link

    func testStartsTheAdminInitiatedFlowWithTheAdministratorsToken() async throws {
        let server = ManagementTestServer()
        server.execution = sent
        server.config = Self.configured
        let client = try await server.makeClient()

        _ = try await client.users.sendAttributeVerification(id: "u-1", attribute: "email", fetcher: server.fetcher)

        XCTAssertEqual(
            server.calls,
            ["GET https://localhost:8090/server-config/flow", "POST https://localhost:8090/flow/execute"]
        )
        XCTAssertEqual(server.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer admin-token")
        let body = try XCTUnwrap(server.executions.first)
        XCTAssertEqual(body["flowType"] as? String, "ADMIN_INITIATED")
        XCTAssertEqual(body["handle"] as? String, "admin-verification")
        XCTAssertEqual(body["inputs"] as? [String: String], ["subject": "u-1", "attribute": "email"])
        XCTAssertEqual(body["verbose"] as? Bool, true)
        XCTAssertNil(body["flowId"])
        XCTAssertNil(body["applicationId"])
    }

    func testRefusesWhenTheServerNamesNoFlowAndNoHandleIsGiven() async throws {
        let server = ManagementTestServer()
        server.execution = sent
        server.config = #"{"userSuspendFlow":{"defaultHandle":"suspend"}}"#
        let client = try await server.makeClient()

        let error = await assertThrowsThunderIDError(.administrationFlowNotConfigured) {
            _ = try await client.users.sendAttributeVerification(id: "u-1", attribute: "email", fetcher: server.fetcher)
        }

        XCTAssertTrue(error?.message.contains("adminAttributeVerificationFlow") == true)
        XCTAssertEqual(server.calls, ["GET https://localhost:8090/server-config/flow"])
    }

    func testRunsTheFlowTheAppNames() async throws {
        let server = ManagementTestServer()
        server.execution = sent
        server.config = Self.configured
        let client = try await server.makeClient()

        _ = try await client.users.sendAttributeVerification(
            id: "u-1",
            attribute: "email",
            handle: "custom-admin-verification",
            fetcher: server.fetcher
        )

        XCTAssertEqual(server.executions.first?["handle"] as? String, "custom-admin-verification")
        XCTAssertEqual(server.calls, ["POST https://localhost:8090/flow/execute"], "The server config is not read")
    }

    func testReturnsTheChannelAndTheMaskedDestination() async throws {
        let server = ManagementTestServer()
        server.execution = sent
        server.config = Self.configured
        let client = try await server.makeClient()

        let result = try await client.users.sendAttributeVerification(
            id: "u-1",
            attribute: "email",
            fetcher: server.fetcher
        )

        XCTAssertEqual(
            result,
            UserAttributeVerificationResult(channel: "email", emailSent: true, maskedDestination: "t•••@example.com")
        )
    }

    func testReadsEmailSentAsABooleanAndLeavesOutWhatTheFlowDoesNotReport() async throws {
        let server = ManagementTestServer()
        server.config = Self.configured
        server.execution = #"{"flowStatus":"INCOMPLETE","data":{"additionalData":{"channel":"email","emailSent":"false"}}}"#
        let client = try await server.makeClient()

        let unsent = try await client.users.sendAttributeVerification(
            id: "u-1",
            attribute: "email",
            fetcher: server.fetcher
        )
        server.execution = #"{"flowStatus":"INCOMPLETE","data":{"additionalData":{"channel":"email"}}}"#
        let bare = try await client.users.sendAttributeVerification(id: "u-1", attribute: "email", fetcher: server.fetcher)

        XCTAssertEqual(unsent, UserAttributeVerificationResult(channel: "email", emailSent: false))
        XCTAssertEqual(bare, UserAttributeVerificationResult(channel: "email"))
    }

    func testRaisesTheRefusingStepsCode() async throws {
        let server = ManagementTestServer()
        server.config = Self.configured
        server.execution = #"{"flowStatus":"ERROR","error":{"code":"FET-1114","# +
            #""message":{"key":"k","defaultValue":"The user is suspended"}}}"#
        let client = try await server.makeClient()

        let error = await assertThrowsThunderIDError(.administrationFlowFailed) {
            _ = try await client.users.sendAttributeVerification(id: "u-1", attribute: "email", fetcher: server.fetcher)
        }

        XCTAssertEqual(error?.flowError?.code, "FET-1114")
        XCTAssertEqual(error?.message, "The user is suspended")
        XCTAssertTrue(error?.isAdministrationFlowError == true)
    }

    func testRefusesAFlowThatReportsNoSentLink() async throws {
        let server = ManagementTestServer()
        server.config = Self.configured
        let client = try await server.makeClient()

        for execution in [
            #"{"flowStatus":"COMPLETE","data":{"additionalData":{"channel":"email"}}}"#,
            #"{"flowStatus":"INCOMPLETE","data":{"additionalData":{}}}"#
        ] {
            server.execution = execution
            let error = await assertThrowsThunderIDError(.administrationFlowFailed) {
                _ = try await client.users.sendAttributeVerification(
                    id: "u-1",
                    attribute: "email",
                    fetcher: server.fetcher
                )
            }
            XCTAssertNil(error?.flowError)
            XCTAssertEqual(error?.message, "The verification flow did not report a sent link.")
        }
    }

    func testKeepsAnHTTPRefusalAsTheAPIError() async throws {
        let server = ManagementTestServer()
        server.config = Self.configured
        server.execution = #"{"code":"FES-1017","message":"Forbidden"}"#
        server.executionStatus = 403
        let client = try await server.makeClient()

        await assertThrowsThunderIDError(.forbidden) {
            _ = try await client.users.sendAttributeVerification(id: "u-1", attribute: "email", fetcher: server.fetcher)
        }
    }

    func testRefusesABlankUserOrAttributeBeforeAnyRequest() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()

        for (id, attribute) in [("", "email"), ("  ", "email"), ("u-1", ""), ("u-1", " \n")] {
            await assertThrowsThunderIDError(.invalidInput) {
                _ = try await client.users.sendAttributeVerification(
                    id: id,
                    attribute: attribute,
                    fetcher: server.fetcher
                )
            }
        }
        XCTAssertTrue(server.requests.isEmpty)
    }

    // MARK: - Eligibility

    func testReadsTheUsersVerifiedAttributes() throws {
        let verified = try user(
            #"{"id":"u","ouId":"o","type":"t","verifiedAttributes":{"email":{"verifiedAt":"2026-11-03T10:00:00Z"}}}"#
        )
        let unknown = try user(#"{"id":"u","ouId":"o","type":"t"}"#)

        XCTAssertEqual(verified.verifiedAttributes?["email"]?.verifiedAt, "2026-11-03T10:00:00Z")
        XCTAssertNil(unknown.verifiedAttributes)
    }
}
