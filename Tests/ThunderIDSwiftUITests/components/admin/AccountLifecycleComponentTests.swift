// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers the access status and the account lifecycle actions of the user, agent and application
/// details components.
@MainActor
final class AccountLifecycleComponentTests: XCTestCase {
    private let i18n = ThunderIDI18n(language: "en-US", storageKey: "account_lifecycle_component_tests_locale")

    private final class Captured<Value> {
        var value: Value?
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func render(_ view: some View) {
        let state = ThunderIDState(client: ThunderIDClient(), i18n: i18n)
        let renderer = ImageRenderer(
            content: view
                .environmentObject(i18n)
                .environmentObject(state)
                .frame(width: 400)
        )
        XCTAssertNotNil(renderer.cgImage)
    }

    private func lockedUser(readOnly: Bool = false) throws -> ManagedUser {
        try decode(
            #"{"id":"u-1","ouId":"ou","type":"customer","display":"Aiko Tanaka","isReadOnly":\#(readOnly),"# +
            #""status":{"value":"LOCKED","details":{"reason":"FAILED_ATTEMPTS","# +
            #""lockedMethods":[{"method":"password","expiresAt":"2026-10-28T10:00:00Z"}]}}}"#
        )
    }

    // MARK: - Strings

    func testEveryLifecycleStringIsInTheBundle() {
        for key in [
            "admin.common.status.active", "admin.common.status.locked", "admin.common.status.suspended",
            "admin.common.lifecycle.suspend", "admin.common.lifecycle.unsuspend", "admin.common.lifecycle.unlock",
            "admin.common.lifecycle.suspend_confirm", "admin.common.lifecycle.unsuspend_confirm",
            "admin.common.lifecycle.operator_note", "admin.common.lifecycle.error",
            "admin.common.lifecycle.load_error", "admin.common.columns.status"
        ] {
            XCTAssertNotNil(DefaultStrings.all[key], "Missing default string for key: \(key)")
        }
    }

    func testShowsTheStatusAsATranslatedLabel() {
        XCTAssertEqual(i18n.accessStatusLabel(.locked), "Locked")
        XCTAssertEqual(i18n.accessStatusLabel(.suspended), "Suspended")
        XCTAssertEqual(i18n.accessStatusLabel(AccessStatusValue(rawValue: "ARCHIVED")), "ARCHIVED")
        XCTAssertEqual(i18n.lifecycleActionLabel(.unsuspend), "Unsuspend")
        XCTAssertEqual(
            i18n.lifecycleConfirmation(.suspend, name: "Aiko Tanaka"),
            "Suspend Aiko Tanaka? It can no longer sign in, and its sessions and tokens are revoked."
        )

        let localized = ThunderIDI18n(
            bundles: ["fr-FR": ["admin.common.status.locked": "Verrouillé"]],
            language: "fr-FR",
            storageKey: "account_lifecycle_component_tests_locale_fr"
        )
        XCTAssertEqual(localized.accessStatusLabel(.locked), "Verrouillé")
    }

    func testOnlySuspendingAndUnsuspendingAskForConfirmation() {
        XCTAssertTrue(AccountLifecycleAction.suspend.requiresConfirmation)
        XCTAssertTrue(AccountLifecycleAction.unsuspend.requiresConfirmation)
        XCTAssertFalse(AccountLifecycleAction.unlock.requiresConfirmation)
    }

    func testTrimsTheOperatorNoteAndKeepsItWithinTheLimit() {
        XCTAssertEqual(AccountLifecycleNote.normalized(" Ticket 4521 "), "Ticket 4521")
        XCTAssertNil(AccountLifecycleNote.normalized("   "))
        XCTAssertEqual(AccountLifecycleNote.clamped(String(repeating: "x", count: 150)).count, 100)
        XCTAssertEqual(AccountLifecycleNote.normalized(String(repeating: "y", count: 101))?.count, 100)
    }

    // MARK: - User details

    func testUserDetailsRenderTheStatusAndTheActions() throws {
        let user = try lockedUser()

        render(BaseUserDetails(user: user))
        render(BaseUserDetails(user: user, lifecycleActions: [.unlock, .suspend], onLifecycleAction: { _, _ in }))
        render(
            BaseUserDetails(
                user: user,
                isRunningLifecycleAction: true,
                lifecycleActions: [.unlock],
                onLifecycleAction: { _, _ in }
            )
        )
    }

    func testOffersNoLifecycleActionsWithoutAHandler() throws {
        let captured = Captured<UserDetailsState>()

        render(
            BaseUserDetails(user: try lockedUser(), lifecycleActions: [.unlock, .suspend]) { state in
                let _ = (captured.value = state)
                Text(state.displayName)
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertEqual(state.user?.status?.value, .locked)
        XCTAssertEqual(state.lifecycleActions, [])
        XCTAssertNil(state.onLifecycleAction)
    }

    func testHandsCustomDetailsTheLifecycleActionsForReadOnlyUsersToo() throws {
        let captured = Captured<UserDetailsState>()
        var runs: [(AccountLifecycleAction, String?)] = []

        render(
            BaseUserDetails(
                user: try lockedUser(readOnly: true),
                isRunningLifecycleAction: true,
                lifecycleActions: [.unlock],
                onLifecycleAction: { runs.append(($0, $1)) }
            ) { state in
                let _ = (captured.value = state)
                Text(state.displayName)
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertEqual(state.lifecycleActions, [.unlock])
        XCTAssertTrue(state.isRunningLifecycleAction)
        XCTAssertNil(state.onDelete, "A read-only user still cannot be deleted")
        state.onLifecycleAction?(.unlock, nil)
        XCTAssertEqual(runs.map(\.0), [.unlock])
    }

    func testOffersNoLifecycleActionsWithoutAUser() throws {
        let captured = Captured<UserDetailsState>()

        render(
            BaseUserDetails(user: nil, isLoading: true, lifecycleActions: [.suspend], onLifecycleAction: { _, _ in }) {
                state in
                let _ = (captured.value = state)
                Text("")
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertEqual(state.lifecycleActions, [])
        XCTAssertNil(state.onLifecycleAction)
    }

    // MARK: - Agent details

    func testAgentDetailsHandTheLifecycleActionsToCustomContent() throws {
        let agent: Agent = try decode(
            #"{"id":"a-1","name":"Billing bot","ouId":"ou-1","type":"bot","status":{"value":"SUSPENDED"}}"#
        )
        let captured = Captured<AgentDetailsState>()
        var runs: [AccountLifecycleAction] = []

        render(BaseAgentDetails(agent: agent, lifecycleActions: [.unsuspend], onLifecycleAction: { _, _ in }))
        render(
            BaseAgentDetails(agent: agent, lifecycleActions: [.unsuspend], onLifecycleAction: { action, _ in
                runs.append(action)
            }) { state in
                let _ = (captured.value = state)
                Text(state.agent?.name ?? "")
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertEqual(state.agent?.status?.value, .suspended)
        XCTAssertEqual(state.lifecycleActions, [.unsuspend])
        state.onLifecycleAction?(.unsuspend, nil)
        XCTAssertEqual(runs, [.unsuspend])
    }

    // MARK: - Application details

    func testApplicationDetailsHandTheLifecycleActionsToCustomContent() throws {
        let application: Application = try decode(
            #"{"id":"app-1","name":"Portal","status":{"value":"ACTIVE"},"isReadOnly":true}"#
        )
        let captured = Captured<ApplicationDetailsState>()

        render(
            BaseApplicationDetails(application: application, lifecycleActions: [.suspend], onLifecycleAction: { _, _ in })
        )
        render(
            BaseApplicationDetails(
                application: application,
                onDelete: {},
                lifecycleActions: [.suspend],
                onLifecycleAction: { _, _ in }
            ) { state in
                let _ = (captured.value = state)
                Text(state.application?.name ?? "")
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertEqual(state.application?.status?.accessStatus, .active)
        XCTAssertEqual(state.lifecycleActions, [.suspend])
        XCTAssertNotNil(state.onLifecycleAction, "Lifecycle actions apply to read-only applications too")
        XCTAssertNil(state.onDelete)
    }
}
