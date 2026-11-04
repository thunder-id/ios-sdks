// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers the organization unit components, built in and through a custom render.
@MainActor
final class OrganizationUnitComponentTests: XCTestCase {
    private let i18n = ThunderIDI18n(language: "en-US", storageKey: "organization_unit_component_tests_locale")

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

    private func unit() throws -> OrganizationUnit {
        try decode(
            #"{"id":"ou-1","handle":"eng","name":"Engineering","parent":"ou-root","description":"Builders","# +
            #""themeId":"theme-1"}"#
        )
    }

    private func children() throws -> [OrganizationUnitSummary] {
        try decode(#"[{"id":"ou-2","handle":"web","name":"Web"},{"id":"ou-3","handle":"ios","name":"iOS"}]"#)
    }

    // MARK: - Defaults

    func testDataChangingActionsAreOffUnlessEnabled() {
        XCTAssertFalse(OrganizationUnitDetails(organizationUnitId: "ou-1").editable)
        XCTAssertFalse(OrganizationUnitDetails(organizationUnitId: "ou-1").deletable)
        XCTAssertNil(BaseOrganizationUnitDetails(unit: nil, onUpdate: { _ in }, onDelete: {}).renderState.onDelete)
        XCTAssertNil(BaseOrganizationUnitDetails(unit: nil, onUpdate: { _ in }, onDelete: {}).renderState.onUpdate)
    }

    // MARK: - Built-in UI

    func testBaseComponentsRenderStandalone() throws {
        let rows = try children()
        render(BaseOrganizationUnitList(units: rows, totalResults: 40, onPageChange: { _ in }, onSelect: { _ in }))
        render(BaseOrganizationUnitList(units: [], isLoading: true))
        render(BaseOrganizationUnitCreate(parents: [AdminOption(label: "Root", value: "ou-root")]) { _ in })
        render(BaseOrganizationUnitCreate(parentId: "ou-root", error: "x", onCancel: {}) { _ in })
        render(
            BaseOrganizationUnitDetails(
                unit: try unit(),
                children: rows,
                users: try decode(#"[{"id":"u-1","display":"Ada"}]"#),
                groups: try decode(#"[{"id":"g-1","name":"Admins"}]"#),
                roles: try decode(#"[{"id":"r-1","name":"Viewer"}]"#),
                onSelectChild: { _ in },
                onUpdate: { _ in },
                onDelete: {}
            )
        )
        render(BaseOrganizationUnitDetails(unit: nil, isLoading: true))
        render(BaseOrganizationUnitDetails(unit: nil, error: "Could not load this organization unit."))
    }

    func testConnectedComponentsRenderWithoutAServer() {
        render(OrganizationUnitList())
        render(OrganizationUnitList(parentId: "ou-1"))
        render(OrganizationUnitCreate())
        render(OrganizationUnitCreate(parentId: "ou-1"))
        render(OrganizationUnitDetails(organizationUnitId: "ou-1", editable: true, deletable: true))
    }

    // MARK: - Custom render

    func testListContentReceivesUnitsAndSelection() throws {
        let captured = Captured<AdminListState<OrganizationUnitSummary>>()
        var selected: [String] = []

        render(
            BaseOrganizationUnitList(units: try children(), onSelect: { selected.append($0.id) }) { list in
                let _ = (captured.value = list)
                Text("")
            }
        )

        let list = try XCTUnwrap(captured.value)
        XCTAssertEqual(list.rows.map(\.handle), ["web", "ios"])
        XCTAssertNil(list.onPageChange)
        list.onSelect?(list.rows[1])
        XCTAssertEqual(selected, ["ou-3"])
    }

    func testCreateContentFixesTheGivenParentAndRejectsInvalidValues() throws {
        let fixed = Captured<OrganizationUnitFormState>()
        let picked = Captured<OrganizationUnitFormState>()
        var submissions: [OrganizationUnitRequest] = []
        let parents = [AdminOption(label: "Root", value: "ou-root")]

        render(
            BaseOrganizationUnitCreate(parentId: "ou-1", parents: parents, onSubmit: { submissions.append($0) }) { form in
                let _ = (fixed.value = form)
                Text("")
            }
        )
        render(
            BaseOrganizationUnitCreate(defaultParentId: "ou-root", parents: parents, onSubmit: { _ in }) { form in
                let _ = (picked.value = form)
                Text("")
            }
        )

        let fixedForm = try XCTUnwrap(fixed.value)
        XCTAssertTrue(fixedForm.isParentFixed)
        XCTAssertEqual(fixedForm.parentId.wrappedValue, "ou-1")
        XCTAssertTrue(fixedForm.parents.isEmpty)
        XCTAssertFalse(fixedForm.isValid)
        fixedForm.submit()
        XCTAssertTrue(submissions.isEmpty)
        let pickedForm = try XCTUnwrap(picked.value)
        XCTAssertFalse(pickedForm.isParentFixed)
        XCTAssertEqual(pickedForm.parentId.wrappedValue, "ou-root")
        XCTAssertEqual(pickedForm.parents, parents)
    }

    func testDetailsContentGetsTheUnitItsMembersAndTheAllowedActions() throws {
        let captured = Captured<OrganizationUnitDetailsState>()
        var updates: [OrganizationUnitRequest] = []
        var deletes = 0

        render(
            BaseOrganizationUnitDetails(
                unit: try unit(),
                children: try children(),
                groups: try decode(#"[{"id":"g-1","name":"Admins"}]"#),
                onUpdate: { updates.append($0) },
                onDelete: { deletes += 1 }
            ) { details in
                let _ = (captured.value = details)
                Text(details.unit?.name ?? "")
            }
        )

        let details = try XCTUnwrap(captured.value)
        XCTAssertEqual(details.unit?.description, "Builders")
        XCTAssertEqual(details.unit?.themeId, "theme-1")
        XCTAssertEqual(details.children.count, 2)
        XCTAssertEqual(details.groups.map(\.name), ["Admins"])
        XCTAssertTrue(details.users.isEmpty)
        XCTAssertNil(details.onSelectChild)
        details.onDelete?()
        details.onUpdate?(OrganizationUnitRequest(handle: "eng", name: "Eng", parent: "ou-root"))
        XCTAssertEqual(deletes, 1)
        XCTAssertEqual(updates.first?.name, "Eng")
    }
}
