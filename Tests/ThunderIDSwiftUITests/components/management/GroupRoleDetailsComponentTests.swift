// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers the group and role details components, built in and through a custom render.
@MainActor
final class GroupRoleDetailsComponentTests: XCTestCase {
    private let i18n = ThunderIDI18n(language: "en-US", storageKey: "group_role_details_component_tests_locale")

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

    private func group() throws -> ManagedGroup {
        try decode(#"{"id":"g-1","name":"Engineering","description":"Builders","ouId":"ou-1","ouHandle":"default"}"#)
    }

    private func role(readOnly: Bool = false) throws -> Role {
        try decode(
            #"{"id":"r-1","name":"Viewer","description":"Read access","ouId":"ou-1","isReadOnly":\#(readOnly),"# +
            #""permissions":[{"resourceServerId":"rs","permissions":["a"]}]}"#
        )
    }

    // MARK: - Defaults

    func testDataChangingActionsAreOffUnlessEnabled() {
        XCTAssertFalse(GroupDetails(groupId: "g-1").editable)
        XCTAssertFalse(GroupDetails(groupId: "g-1").deletable)
        XCTAssertEqual(GroupDetails(groupId: "g-1").administrationMode, .native)
        XCTAssertFalse(RoleDetails(roleId: "r-1").editable)
        XCTAssertFalse(RoleDetails(roleId: "r-1").deletable)
        XCTAssertEqual(RoleDetails(roleId: "r-1").administrationMode, .native)
        XCTAssertNil(BaseGroupDetails(group: nil).onDelete)
        XCTAssertNil(BaseRoleDetails(role: nil).onDelete)
    }

    func testDefaultStringsCarryTheDetailsKeys() {
        for kind in ["groups", "roles"] {
            for key in ["overview", "error", "delete.action", "delete.confirm", "delete.error"] {
                XCTAssertNotNil(DefaultStrings.all["admin.\(kind).details.\(key)"], "Missing admin.\(kind).details.\(key)")
            }
        }
        XCTAssertEqual(i18n.resolve("admin.groups.details.delete.action"), "Delete group")
        XCTAssertEqual(i18n.resolve("admin.roles.details.delete.action"), "Delete role")
        XCTAssertEqual(i18n.resolve("admin.groups.details.delete.confirm", ["name": "Engineering"]), "Delete Engineering?")
    }

    // MARK: - Built-in UI

    func testBaseDetailsRenderStandalone() throws {
        render(BaseGroupDetails(group: try group(), onDelete: {}, sections: AnyView(Text("Members"))))
        render(BaseGroupDetails(group: nil, isLoading: true))
        render(BaseGroupDetails(group: nil, error: "Could not load this group. Please try again."))
        render(BaseRoleDetails(role: try role(), onDelete: {}, sections: AnyView(Text("Permissions"))))
        render(BaseRoleDetails(role: try role(readOnly: true), onDelete: {}))
        render(BaseRoleDetails(role: nil, isLoading: true))
        render(BaseRoleDetails(role: nil))
    }

    func testConnectedDetailsRenderWithoutAServer() {
        render(GroupDetails(groupId: "g-1", administrationMode: .flow, editable: true, deletable: true))
        render(RoleDetails(roleId: "r-1", administrationMode: .flow, editable: true, deletable: true))
    }

    // MARK: - Custom render

    func testGroupDetailsContentGetsTheGroupAndTheDeleteAction() throws {
        let captured = Captured<GroupDetailsState>()
        var deletes = 0

        render(
            BaseGroupDetails(group: try group(), isDeleting: true, onDelete: { deletes += 1 }) { state in
                let _ = (captured.value = state)
                Text(state.group?.name ?? "")
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertEqual(state.group?.name, "Engineering")
        XCTAssertEqual(state.group?.ouHandle, "default")
        XCTAssertTrue(state.isDeleting)
        state.onDelete?()
        XCTAssertEqual(deletes, 1)
    }

    func testGroupDetailsContentGetsNoDeleteWithoutAGroup() throws {
        let captured = Captured<GroupDetailsState>()

        render(
            BaseGroupDetails(group: nil, isLoading: true, onDelete: {}) { state in
                let _ = (captured.value = state)
                Text("")
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertTrue(state.isLoading)
        XCTAssertNil(state.onDelete)
    }

    func testRoleDetailsContentHidesTheDeleteOfAReadOnlyRole() throws {
        let editable = Captured<RoleDetailsState>()
        let readOnly = Captured<RoleDetailsState>()

        render(
            BaseRoleDetails(role: try role(), error: "x", onDelete: {}) { state in
                let _ = (editable.value = state)
                Text(state.role?.name ?? "")
            }
        )
        render(
            BaseRoleDetails(role: try role(readOnly: true), onDelete: {}) { state in
                let _ = (readOnly.value = state)
                Text(state.role?.name ?? "")
            }
        )

        XCTAssertEqual(editable.value?.role?.name, "Viewer")
        XCTAssertEqual(editable.value?.error, "x")
        XCTAssertNotNil(editable.value?.onDelete)
        XCTAssertNil(try XCTUnwrap(readOnly.value).onDelete)
    }

    func testConnectedDetailsHandTheirStateToCustomContent() {
        let group = Captured<GroupDetailsState>()
        let role = Captured<RoleDetailsState>()

        render(
            GroupDetails(groupId: "g-1", deletable: true) { state in
                let _ = (group.value = state)
                Text("")
            }
        )
        render(
            RoleDetails(roleId: "r-1", deletable: true) { state in
                let _ = (role.value = state)
                Text("")
            }
        )

        XCTAssertNotNil(group.value)
        XCTAssertNotNil(role.value)
    }
}
