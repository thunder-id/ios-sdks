// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers ``OrganizationUnitSwitcher``: the built-in UI, a custom render, and how a switch is reported.
@MainActor
final class OrganizationUnitSwitcherTests: XCTestCase {
    private let i18n = ThunderIDI18n(language: "en-US", storageKey: "organization_unit_switcher_tests_locale")
    private let units = [
        AccessibleOrganizationUnit(id: "ou-1", handle: "acme-1", name: "Acme 1"),
        AccessibleOrganizationUnit(id: "ou-2", handle: "acme-2", name: "Acme 2")
    ]

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

    func testDefaultStringsCarryTheSwitcherKeys() {
        for key in [
            "title", "current", "loading", "switching", "empty", "previous", "next",
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
        let props = OrganizationUnitSwitcherProps(
            scope: nil,
            limit: 20,
            switchOptions: .init(),
            onSelect: nil,
            onSwitched: nil,
            onSignInRequired: nil
        )
        await model.switchTo(units[0], appState: state, props: props, i18n: i18n)
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
