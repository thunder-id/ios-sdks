// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class AccountLifecycleTests: XCTestCase {
    private let baseUrl = ManagementTestServer.baseUrl

    private let allUserFlows: [AdministrationFlowConfigKey: String] = [
        .userSuspend: "f-suspend",
        .userUnlock: "f-unlock",
        .userUnsuspend: "f-unsuspend"
    ]

    // MARK: - Access status

    func testReadsTheAccessStatusOfUsersAndAgents() throws {
        let user = try JSONDecoder().decode(ManagedUser.self, from: Data(
            (#"{"id":"u-1","ouId":"ou","type":"customer","status":{"value":"SUSPENDED","details":"# +
             #"{"reason":"ADMINISTRATIVE_SUSPENSION","since":"2026-10-01T00:00:00Z","operatorNote":"Ticket 4521"}}}"#)
                .utf8
        ))
        let agent = try JSONDecoder().decode(Agent.self, from: Data(
            #"{"id":"a-1","ouId":"ou","type":"bot","name":"Bot","status":{"value":"LOCKED"}}"#.utf8
        ))
        let bare = try JSONDecoder().decode(ManagedUser.self, from: Data(#"{"id":"u-2","ouId":"ou","type":"c"}"#.utf8))

        XCTAssertEqual(user.status?.value, .suspended)
        XCTAssertEqual(user.status?.details?.reason, .administrativeSuspension)
        XCTAssertEqual(user.status?.details?.operatorNote, "Ticket 4521")
        XCTAssertEqual(agent.status, AccessStatus(value: .locked))
        XCTAssertNil(bare.status)
        XCTAssertEqual(ApplicationAccessStatus(value: "suspended").accessStatus, .suspended)
    }

    // MARK: - Available actions

    func testOffersTheActionsEachStatusAllowsMostExpectedFirst() {
        XCTAssertEqual(AccountLifecycleAction.available(for: .user, status: .active, configuredFlows: allUserFlows), [
            .suspend
        ])
        XCTAssertEqual(AccountLifecycleAction.available(for: .user, status: .locked, configuredFlows: allUserFlows), [
            .unlock, .suspend
        ])
        XCTAssertEqual(
            AccountLifecycleAction.available(for: .user, status: .suspended, configuredFlows: allUserFlows),
            [.unsuspend]
        )
    }

    func testReadsAnIdentityWithNoStatusAsActive() {
        XCTAssertEqual(AccountLifecycleAction.available(for: .user, status: nil, configuredFlows: allUserFlows), [
            .suspend
        ])
    }

    func testOffersOnlyTheActionsWhoseFlowIsConfigured() {
        XCTAssertEqual(
            AccountLifecycleAction.available(for: .user, status: .locked, configuredFlows: [.userSuspend: "f"]),
            [.suspend]
        )
        XCTAssertEqual(AccountLifecycleAction.available(for: .user, status: .active, configuredFlows: [:]), [])
        XCTAssertEqual(
            AccountLifecycleAction.available(for: .user, status: .active, configuredFlows: [.userSuspend: ""]),
            []
        )
    }

    func testReadsTheFlowsOfTheIdentityKindItIsGiven() {
        XCTAssertEqual(AccountLifecycleAction.available(for: .agent, status: .active, configuredFlows: allUserFlows), [])
        XCTAssertEqual(
            AccountLifecycleAction.available(
                for: .agent,
                status: .locked,
                configuredFlows: [.agentSuspend: "a", .agentUnlock: "b"]
            ),
            [.unlock, .suspend]
        )
    }

    func testNeverOffersAnUnlockForAnApplication() {
        XCTAssertNil(AccountLifecycleSubjectKind.application.flowConfigKeys[.unlock])
        XCTAssertEqual(
            AccountLifecycleAction.available(
                for: .application,
                status: .locked,
                configuredFlows: [.applicationSuspend: "a", .applicationUnsuspend: "b"]
            ),
            [.suspend]
        )
    }

    func testOffersNothingForAStatusItDoesNotKnow() {
        XCTAssertEqual(
            AccountLifecycleAction.available(
                for: .user,
                status: AccessStatusValue(rawValue: "ARCHIVED"),
                configuredFlows: allUserFlows
            ),
            []
        )
    }

    // MARK: - Running an action

    func testRunsTheFlowConfiguredForEachKindAndAction() async throws {
        let cases: [(AccountLifecycleSubjectKind, AccountLifecycleAction, String)] = [
            (.user, .suspend, "userSuspendFlow"),
            (.user, .unsuspend, "userUnsuspendFlow"),
            (.user, .unlock, "userUnlockFlow"),
            (.agent, .suspend, "agentSuspendFlow"),
            (.agent, .unsuspend, "agentUnsuspendFlow"),
            (.agent, .unlock, "agentUnlockFlow"),
            (.application, .suspend, "applicationSuspendFlow"),
            (.application, .unsuspend, "applicationUnsuspendFlow")
        ]
        for (kind, action, configKey) in cases {
            let server = ManagementTestServer()
            server.config = #"{"\#(configKey)":{"defaultHandle":"lifecycle"}}"#
            server.flows = [("lifecycle", "id-lifecycle")]
            let client = try await server.makeClient()

            _ = try await client.runAccountLifecycleAction(action, kind: kind, subject: "s-1")

            XCTAssertEqual(server.executions.first?["flowId"] as? String, "id-lifecycle", "\(kind) \(action)")
            XCTAssertEqual(server.executions.first?["inputs"] as? [String: String], ["subject": "s-1"])
            XCTAssertEqual(kind.flowConfigKeys[action]?.rawValue, configKey)
        }
    }

    func testPassesTheOperatorNoteAndReportsWhetherTheNotificationWasSent() async throws {
        let server = ManagementTestServer()
        server.config = #"{"userSuspendFlow":{"defaultHandle":"suspend"}}"#
        server.flows = [("suspend", "id-suspend")]
        server.execution = #"{"flowStatus":"COMPLETE","data":{"additionalData":{"emailSent":"false"}}}"#
        let client = try await server.makeClient()

        let result = try await client.runAccountLifecycleAction(
            .suspend,
            kind: .user,
            subject: "u-1",
            operatorNote: "Ticket 4521"
        )

        XCTAssertEqual(result, AccountLifecycleResult(emailSent: false))
        XCTAssertEqual(
            server.executions.first?["inputs"] as? [String: String],
            ["operatorNote": "Ticket 4521", "subject": "u-1"]
        )
    }

    func testFailsWithTheOperationErrorWhenNoFlowIsConfigured() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()

        await assertThrowsThunderIDError(.administrationFlowNotConfigured) {
            _ = try await client.runAccountLifecycleAction(.unlock, kind: .agent, subject: "a-1")
        }
        XCTAssertTrue(server.executions.isEmpty)
    }

    func testRefusesToUnlockAnApplicationWithoutCallingTheServer() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()

        await assertThrowsThunderIDError(.invalidInput) {
            _ = try await client.runAccountLifecycleAction(.unlock, kind: .application, subject: "app-1")
        }
        XCTAssertTrue(server.requests.isEmpty)
    }
}
