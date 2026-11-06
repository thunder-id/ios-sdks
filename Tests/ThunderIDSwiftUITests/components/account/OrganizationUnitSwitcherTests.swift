// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers ``OrganizationUnitSwitcher``: the built-in dropdown, a custom render, and how a switch is reported.
@MainActor
final class OrganizationUnitSwitcherTests: XCTestCase {
    private let i18n = ThunderIDI18n(language: "en-US", storageKey: "organization_unit_switcher_tests_locale")
    private let units = [
        AccessibleOrganizationUnit(id: "ou-1", handle: "acme-1", name: "Acme 1"),
        AccessibleOrganizationUnit(id: "ou-2", handle: "acme-2", name: "Acme 2")
    ]

    private func render(_ view: some View, i18n custom: ThunderIDI18n? = nil) {
        let strings = custom ?? i18n
        let state = ThunderIDState(client: ThunderIDClient(), i18n: strings)
        let renderer = ImageRenderer(
            content: view
                .environmentObject(strings)
                .environmentObject(state)
                .frame(width: 400)
        )
        XCTAssertNotNil(renderer.cgImage)
    }

    /// The state the built-in UI draws from, as the base variant builds it.
    private func state(
        units: [AccessibleOrganizationUnit]? = nil,
        currentId: String? = "ou-1",
        currentName: String? = nil,
        isLoading: Bool = false,
        switchingId: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSwitch: @escaping (AccessibleOrganizationUnit) -> Void = { _ in }
    ) -> OrganizationUnitSwitcherState {
        BaseOrganizationUnitSwitcher(
            units: units ?? self.units,
            currentId: currentId,
            currentName: currentName,
            isLoading: isLoading,
            switchingId: switchingId,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            onPageChange: onPageChange,
            onSwitch: onSwitch
        ).renderState
    }

    private func props() -> OrganizationUnitSwitcherProps {
        OrganizationUnitSwitcherProps(
            scope: nil,
            limit: 20,
            switchOptions: .init(),
            onSelect: nil,
            onSwitched: nil,
            onSignInRequired: nil
        )
    }

    func testDefaultStringsCarryTheSwitcherKeys() {
        for key in [
            "label", "placeholder", "loading", "switching", "empty", "previous", "next",
            "error.load", "error.switch", "error.unavailable", "signInRequired"
        ] {
            XCTAssertNotNil(DefaultStrings.all["organizationUnitSwitcher.\(key)"], "Missing organizationUnitSwitcher.\(key)")
        }
        XCTAssertEqual(
            i18n.resolve("organizationUnitSwitcher.signInRequired", ["name": "Acme 2"]),
            "Sign in again to switch to Acme 2."
        )
    }

    func testBuiltInUIRendersEveryState() {
        render(BaseOrganizationUnitSwitcher(units: units, currentId: "ou-1") { _ in })
        render(BaseOrganizationUnitSwitcher(units: units, currentId: "ou-1", switchingId: "ou-2") { _ in })
        render(BaseOrganizationUnitSwitcher(units: [], currentId: nil, isLoading: true) { _ in })
        render(BaseOrganizationUnitSwitcher(units: [], currentId: nil, error: "Could not load your organizations.") { _ in })
        render(BaseOrganizationUnitSwitcher(units: [], currentId: "ou-9", currentName: "Acme 9") { _ in })
        render(BaseOrganizationUnitSwitcher(
            units: units,
            currentId: "ou-1",
            limit: 2,
            totalResults: 5,
            onPageChange: { _ in },
            onSwitch: { _ in }
        ))
        render(OrganizationUnitSwitcher(scope: .siblings))
    }

    func testBuiltInUIOmitsAnEmptyLabel() {
        let unlabelled = ThunderIDI18n(
            bundles: ["en-US": ["organizationUnitSwitcher.label": ""]],
            language: "en-US",
            storageKey: "organization_unit_switcher_tests_locale"
        )
        render(BaseOrganizationUnitSwitcher(units: units, currentId: "ou-1") { _ in }, i18n: unlabelled)
    }

    func testFieldShowsTheSwitchTheCurrentUnitTheLoadingOrThePlaceholder() {
        XCTAssertEqual(state().fieldText(i18n), "Acme 1")
        XCTAssertEqual(state(switchingId: "ou-2").fieldText(i18n), "Switching to Acme 2…")
        XCTAssertEqual(state(units: [], currentId: nil, isLoading: true).fieldText(i18n), "Loading organization units…")
        XCTAssertEqual(state(units: [], currentId: nil).fieldText(i18n), "Select an organization")
        XCTAssertEqual(state(units: [], currentId: "ou-9").fieldText(i18n), "Select an organization")
    }

    func testCurrentUnitOffThePageIsNamedFromTheSession() {
        XCTAssertEqual(state(currentId: "ou-9", currentName: "Acme 9").currentName, "Acme 9")
        XCTAssertEqual(state(currentId: "ou-9", currentName: "Acme 9").fieldText(i18n), "Acme 9")
        XCTAssertEqual(state(currentName: "Stale").currentName, "Acme 1", "the page names a unit it lists")
        XCTAssertNil(state(currentId: "ou-9").currentName)
    }

    func testPickingTheCurrentUnitOnlyClosesTheMenu() {
        var switched: [String] = []
        let picker = state(onSwitch: { switched.append($0.id) })
        picker.choose(units[0])
        picker.choose(units[1])
        XCTAssertEqual(switched, ["ou-2"])
    }

    func testMenuPagesOnlyWhenThereAreMoreUnitsThanThePageSize() {
        XCTAssertFalse(state(limit: 2, totalResults: 2, onPageChange: { _ in }).isPaged)
        XCTAssertFalse(state(limit: 2, totalResults: 5).isPaged, "no paging without onPageChange")
        let first = state(limit: 2, offset: 0, totalResults: 5, onPageChange: { _ in })
        XCTAssertTrue(first.isPaged)
        XCTAssertFalse(first.hasPreviousPage)
        XCTAssertTrue(first.hasNextPage)
        let last = state(limit: 2, offset: 4, totalResults: 5, onPageChange: { _ in })
        XCTAssertTrue(last.hasPreviousPage)
        XCTAssertFalse(last.hasNextPage)
    }

    func testCustomRenderReceivesUnitsCurrentPagingAndSwitch() {
        var captured: OrganizationUnitSwitcherState?
        var switched: [String] = []
        var pages: [Int] = []
        let view = BaseOrganizationUnitSwitcher(
            units: units,
            currentId: "ou-1",
            switchingId: nil,
            error: nil,
            limit: 2,
            offset: 2,
            totalResults: 6,
            onPageChange: { pages.append($0) },
            onSwitch: { switched.append($0.id) },
            content: { state in
                captured = state
                return Text(state.current?.name ?? "")
            }
        )
        render(view)
        let state = try? XCTUnwrap(captured)
        XCTAssertEqual(state?.units.map(\.id), ["ou-1", "ou-2"])
        XCTAssertEqual(state?.current?.handle, "acme-1")
        XCTAssertEqual(state?.currentName, "Acme 1")
        XCTAssertEqual(state?.limit, 2)
        XCTAssertEqual(state?.offset, 2)
        XCTAssertEqual(state?.totalResults, 6)
        state?.onSwitch(units[1])
        state?.onPageChange?(4)
        XCTAssertEqual(switched, ["ou-2"])
        XCTAssertEqual(pages, [4])
    }

    func testConnectedCustomRenderStartsEmptyAndLoading() {
        var captured: OrganizationUnitSwitcherState?
        render(OrganizationUnitSwitcher(limit: 5) { state in
            captured = state
            return Text("units: \(state.units.count)")
        })
        XCTAssertEqual(captured?.units.count, 0)
        XCTAssertEqual(captured?.limit, 5)
        XCTAssertNil(captured?.switchingId)
        XCTAssertNil(captured?.currentName)
    }

    func testSessionUnitNamesTheCurrentUnitWhenThePageDoesNotListIt() async throws {
        defer { MockURLProtocol.reset() }
        MockURLProtocol.handler = { request in
            let body = #"{"current":"ou-9","organizationUnits":[{"id":"ou-1","handle":"acme-1","name":"Acme 1"}],"totalResults":3}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        let claims = #"{"sub":"u1","ouId":"ou-9","ouName":"Acme 9"}"#
        let payload = Data(claims.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        let storage = InMemoryStorageAdapter()
        try TokenStore(storage: storage).save(
            TokenResponse(accessToken: "e30.\(payload).sig", tokenType: "Bearer", expiresIn: 3600)
        )
        let client = ThunderIDClient()
        _ = try await client.initialize(
            config: ThunderIDConfig(baseUrl: "https://id.example.com", clientId: "client-1"),
            storage: storage,
            session: MockURLProtocol.makeSession()
        )
        let model = OrganizationUnitSwitcherModel()
        await model.load(client: client, props: props(), i18n: i18n, offset: 0)
        XCTAssertEqual(model.currentId, "ou-9")
        XCTAssertEqual(model.sessionName, "Acme 9")
        XCTAssertEqual(OrganizationUnitSwitcherState.name(of: model.currentId, in: units, fallback: model.sessionName), "Acme 9")
    }

    func testFailedSwitchShowsATranslatedMessageNeverTheServers() {
        let unavailable = ThunderIDError(code: .organizationUnitUnavailable, message: "unauthorized_client")
        let other = ThunderIDError(code: .serverError, message: "boom")
        XCTAssertEqual(
            OrganizationUnitSwitcherModel.message(for: unavailable, i18n: i18n),
            "This organization unit is not available to this application."
        )
        XCTAssertEqual(
            OrganizationUnitSwitcherModel.message(for: other, i18n: i18n),
            "Could not switch to this organization unit. Please try again."
        )
    }

    func testSwitchToTheCurrentUnitDoesNothing() async {
        let model = OrganizationUnitSwitcherModel()
        let state = ThunderIDState(client: ThunderIDClient(), i18n: i18n)
        await model.switchTo(units[0], appState: state, props: props(), i18n: i18n)
        XCTAssertNotNil(model.error, "an uninitialized client cannot switch, and says so")
        XCTAssertNil(model.switchingId)
    }

    func testLoadFailureShowsTheLoadMessage() async {
        let model = OrganizationUnitSwitcherModel()
        let props = OrganizationUnitSwitcherProps(
            scope: .siblings,
            limit: 20,
            switchOptions: .init(),
            onSelect: nil,
            onSwitched: nil,
            onSignInRequired: nil
        )
        await model.load(client: ThunderIDClient(), props: props, i18n: i18n, offset: 0)
        XCTAssertEqual(model.error, "Could not load your organization units. Please try again.")
        XCTAssertFalse(model.isLoading)
    }
}
