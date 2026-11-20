// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers the personal agent list and details, built in and under a custom render, and the personal agent
/// additions to the admin agent views.
@MainActor
final class PersonalAgentComponentTests: XCTestCase {
    private let i18n = ThunderIDI18n(language: "en-US", storageKey: "personal_agent_component_tests_locale")

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

    private func agent(appliedBy: [String] = [], readOnly: Bool = false) throws -> Agent {
        let status = appliedBy.isEmpty
            ? #"{"value":"ACTIVE"}"#
            : #"{"value":"SUSPENDED","details":{"appliedBy":["# + appliedBy.map { "\"\($0)\"" }.joined(separator: ",")
                + "]}}"
        return try decode(
            #"{"id":"a-1","ouId":"ou","type":"assistant","kind":"personal-assistant","clientId":"c-1","# +
                #""isReadOnly":\#(readOnly),"owner":{"id":"u-1"},"attributes":{"name":"Spending assistant","# +
                #""limits":{"daily":5}},"inboundAuthConfig":[{"type":"oauth2","config":{"grantTypes":"# +
                #"["authorization_code"],"redirectUris":["https://a.example/cb"]}}],"status":\#(status)}"#
        )
    }

    private func basicAgents() throws -> [BasicAgent] {
        try decode(
            #"[{"id":"a-1","ouId":"ou","type":"assistant","kind":"personal-assistant","clientId":"c-1","# +
                #""attributes":{"name":"Spending assistant"},"status":{"value":"ACTIVE"}},"# +
                #"{"id":"a-2","ouId":"ou","type":"bot","attributes":{"name":"Triage"}}]"#
        )
    }

    // MARK: - Strings

    func testEveryStringIsInTheBundle() {
        for key in PersonalAgentDefaultStrings.all.keys {
            XCTAssertNotNil(DefaultStrings.all[key], "Missing default string for key: \(key)")
        }
        XCTAssertEqual(PersonalAgentDefaultStrings.all.count, 41)
        XCTAssertEqual(
            DefaultStrings.strings(for: "fr-FR")?["user.agents.suspension.cascade"],
            "Cet agent reste suspendu tant que votre compte est suspendu."
        )
        for grantType in PersonalAgentGrantTypes.all {
            XCTAssertNotNil(PersonalAgentGrantTypes.labelKeys[grantType].flatMap { DefaultStrings.all[$0] })
        }
    }

    // MARK: - List

    func testListRendersTheAgentsAndTheSuspendAllAction() throws {
        let agents = try basicAgents()

        render(BasePersonalAgentList(agents: agents))
        render(BasePersonalAgentList(agents: agents, onPageChange: { _ in }, onSuspendAll: {}, suspendedCount: 2))
        render(BasePersonalAgentList(agents: [], error: "Could not load your agents."))
        render(PersonalAgentList(suspendable: true))
    }

    func testListOffersSuspendAllOnlyWhenTurnedOnAndThereAreAgents() throws {
        let captured = Captured<PersonalAgentListState>()
        let capture = { (agents: [BasicAgent], onSuspendAll: (() -> Void)?) in
            self.render(
                BasePersonalAgentList(agents: agents, totalResults: 7, onSuspendAll: onSuspendAll) { state in
                    let _ = (captured.value = state)
                    Text(state.agents.first?.resolvedName ?? "")
                }
            )
            return captured.value
        }

        let agents = try basicAgents()
        let offered = try XCTUnwrap(capture(agents) {})
        XCTAssertNotNil(offered.onSuspendAll)
        XCTAssertEqual(offered.totalResults, 7)
        XCTAssertEqual(offered.agents.map(\.isPersonal), [true, false])

        XCTAssertNil(try XCTUnwrap(capture(agents, nil)).onSuspendAll)
        XCTAssertNil(try XCTUnwrap(capture([]) {}).onSuspendAll)
    }

    // MARK: - Details

    func testDetailsRenderTheAgentItsSuspensionsAndTheEditForm() throws {
        render(BasePersonalAgentDetails(agent: try agent()))
        render(
            BasePersonalAgentDetails(
                agent: try agent(appliedBy: ["owner", "organization", "cascade"]),
                error: "The action could not be completed.",
                onUpdate: { _ in true },
                onDelete: {},
                onSuspend: {},
                onUnsuspend: {}
            )
        )
        render(BasePersonalAgentDetails(agent: nil, isLoading: true))
        render(BasePersonalAgentDetails(agent: nil))
        render(
            PersonalAgentEditForm(
                i18n: i18n,
                values: .constant(PersonalAgentFormValues(agent: try agent())),
                isUpdating: false,
                onCancel: {},
                onSave: { _ in }
            )
        )
        render(PersonalAgentDetails(agentId: "a-1", editable: true, deletable: true, suspendable: true))
    }

    private func detailsState(_ agent: Agent?) throws -> PersonalAgentDetailsState {
        let captured = Captured<PersonalAgentDetailsState>()
        render(
            BasePersonalAgentDetails(
                agent: agent,
                onUpdate: { _ in true },
                onDelete: {},
                onSuspend: {},
                onUnsuspend: {}
            ) { state in
                let _ = (captured.value = state)
                Text(state.agent?.resolvedName ?? "")
            }
        )
        return try XCTUnwrap(captured.value)
    }

    func testDetailsOfferTheOwnerTheSuspensionActionThatApplies() throws {
        let active = try detailsState(try agent())
        XCTAssertNotNil(active.onSuspend)
        XCTAssertNil(active.onUnsuspend)
        XCTAssertEqual(active.oauth?.redirectUris, ["https://a.example/cb"])

        let ownerHeld = try detailsState(try agent(appliedBy: ["organization", "owner"]))
        XCTAssertNil(ownerHeld.onSuspend)
        XCTAssertNotNil(ownerHeld.onUnsuspend)

        let organizationHeld = try detailsState(try agent(appliedBy: ["organization"]))
        XCTAssertNotNil(organizationHeld.onSuspend, "The owner can add their own suspension")
        XCTAssertNil(organizationHeld.onUnsuspend, "Only the organization lifts its own")
    }

    func testDetailsNeverOfferEditingOrDeletingAReadOnlyAgent() throws {
        let readOnly = try detailsState(try agent(readOnly: true))
        XCTAssertNil(readOnly.onUpdate)
        XCTAssertNil(readOnly.onDelete)
        XCTAssertNotNil(readOnly.onSuspend, "Suspension changes only runtime state")

        let missing = try detailsState(nil)
        XCTAssertNil(missing.onUpdate)
        XCTAssertNil(missing.onDelete)
        XCTAssertNil(missing.onSuspend)
        XCTAssertNil(missing.onUnsuspend)
    }

    func testDetailsExplainEachSuspensionAndShowEveryAttribute() throws {
        XCTAssertEqual(
            PersonalAgentParts.suspensionNotices(try agent(appliedBy: ["cascade", "owner", "future"]), i18n: i18n),
            [
                "You suspended this agent.",
                "This agent stays suspended while your account is suspended."
            ]
        )
        XCTAssertEqual(PersonalAgentParts.suspensionNotices(try agent(), i18n: i18n), [])
        XCTAssertEqual(PersonalAgentParts.text("Spending"), "Spending")
        XCTAssertEqual(PersonalAgentParts.text(true), "true")
        XCTAssertEqual(PersonalAgentParts.text(5), "5")
        XCTAssertEqual(PersonalAgentParts.text(["daily": AnyCodable(5), "cap": AnyCodable("a/b")]), #"{"cap":"a/b","daily":5}"#)
        XCTAssertEqual(
            PersonalAgentParts.grantTypeLabel(PersonalAgentGrantTypes.ciba, i18n: i18n),
            "Backchannel authentication (CIBA)"
        )
        XCTAssertEqual(PersonalAgentParts.grantTypeLabel("client_credentials", i18n: i18n), "client_credentials")
    }

    // MARK: - Admin agent views

    func testAdminViewsShowThePersonalKindAndWhoHoldsASuspension() throws {
        let held = try agent(appliedBy: ["owner"])

        render(BaseAgentList(agents: try basicAgents()))
        render(BaseAgentDetails(agent: held, lifecycleActions: [.suspend], onLifecycleAction: { _, _ in }))
        XCTAssertEqual(held.status?.suspendedBy, [.owner])
        XCTAssertEqual(held.status?.adminSuspendedBy, [.owner])
        XCTAssertEqual(i18n.resolve("admin.agents.details.suspension.owner"), "Owner")
        XCTAssertEqual(i18n.resolve("admin.agents.kind.personal"), "Personal")
    }

    func testAdminViewsNameTheOrganizationForASuspensionThatNamesNoParty() throws {
        let unnamed: Agent = try decode(#"{"id":"a-1","ouId":"ou","type":"x","status":{"value":"SUSPENDED"}}"#)
        let empty: Agent = try decode(
            #"{"id":"a-1","ouId":"ou","type":"x","status":{"value":"SUSPENDED","details":{"appliedBy":[]}}}"#
        )

        XCTAssertEqual(unnamed.status?.adminSuspendedBy, [.organization])
        XCTAssertEqual(empty.status?.adminSuspendedBy, [.organization])
        XCTAssertEqual(try agent().status?.adminSuspendedBy, [], "An active agent names no party")
        render(BaseAgentDetails(agent: unnamed))
    }
}
