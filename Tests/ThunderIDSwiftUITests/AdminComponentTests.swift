// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

@MainActor
final class AdminComponentTests: XCTestCase {
    private let i18n = ThunderIDI18n(language: "en-US", storageKey: "admin_component_tests_locale")

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Error messages

    func testForbiddenAndNotFoundGetTheirOwnTranslatedMessages() {
        let forbidden = ThunderIDError(code: .forbidden, message: "Forbidden")
        let notFound = ThunderIDError(code: .notFound, message: "Not found")

        XCTAssertEqual(
            i18n.managementErrorMessage(forbidden, fallbackKey: "admin.users.list.error"),
            "You do not have permission to do this."
        )
        XCTAssertEqual(
            i18n.managementErrorMessage(notFound, fallbackKey: "admin.users.list.error"),
            "This item could not be found."
        )
        XCTAssertNil(i18n.managementErrorMessage(nil, fallbackKey: "admin.users.list.error"))
    }

    func testServerErrorTextIsNeverShown() {
        let serverError = ThunderIDError(code: .invalidInput, message: "SQL constraint users_email_key violated")

        let message = i18n.managementErrorMessage(serverError, fallbackKey: "admin.users.create.error")

        XCTAssertEqual(message, "Could not create the user. Please try again.")
    }

    func testAdminMessagesFollowTheConfiguredBundle() {
        let localized = ThunderIDI18n(
            bundles: ["fr-FR": ["admin.common.errors.forbidden": "Accès refusé."]],
            language: "fr-FR",
            storageKey: "admin_component_tests_locale_fr"
        )

        let message = localized.managementErrorMessage(
            ThunderIDError(code: .forbidden, message: "Forbidden"),
            fallbackKey: "admin.users.list.error"
        )

        XCTAssertEqual(message, "Accès refusé.")
        XCTAssertEqual(localized.resolve("admin.users.list.title"), "Users")
    }

    func testDefaultStringsCarryTheAdminBundle() {
        for key in [
            "admin.users.details.delete.confirm", "admin.groups.members.remove_label",
            "admin.roles.permissions.empty", "admin.agents.create.submit", "admin.common.pagination.range"
        ] {
            XCTAssertNotNil(DefaultStrings.all[key], "Missing default string for key: \(key)")
        }
        XCTAssertEqual(DefaultStrings.all["signIn.button"], "Sign in")
        XCTAssertEqual(
            i18n.resolve("admin.users.details.delete.confirm", ["name": "Alice"]),
            "Delete Alice?"
        )
    }

    // MARK: - Components

    func testDestructiveActionsAreOffUnlessEnabled() {
        XCTAssertFalse(UserDetails(userId: "u-1").deletable)
        XCTAssertFalse(UserDetails(userId: "u-1").editable)
        XCTAssertFalse(AgentDetails(agentId: "ag-1").deletable)
        XCTAssertFalse(GroupMembers(groupId: "g-1").editable)
        XCTAssertFalse(RoleAssignments(roleId: "r-1").editable)
        XCTAssertNil(BaseUserDetails(user: nil).onDelete)
        XCTAssertNil(BaseUserDetails(user: nil).onUpdate)
        XCTAssertNil(BaseAgentDetails(agent: nil).onDelete)
        XCTAssertNil(BaseGroupMembers(members: []).onRemove)
        XCTAssertNil(BaseRoleAssignments(assignments: []).onUnassign)
    }

    func testPaginationDescribesTheVisibleRange() {
        let middle = AdminPagination(i18n: i18n, limit: 20, offset: 20, total: 45) { _ in }
        let last = AdminPagination(i18n: i18n, limit: 20, offset: 40, total: 45) { _ in }
        let empty = AdminPagination(i18n: i18n, limit: 20, offset: 0, total: 0) { _ in }

        XCTAssertEqual(middle.range, "21 to 40 of 45")
        XCTAssertEqual(last.range, "41 to 45 of 45")
        XCTAssertEqual(empty.range, "0 to 0 of 0")
    }

    func testAttributesAreRenderedAsText() throws {
        let user: ManagedUser = try decode(
            #"{"id":"u-1","ouId":"ou","type":"customer","attributes":{"# +
            #""age":42,"verified":true,"name":{"given":"Ada"},"tags":["a","b"],"email":"ada@example.com"}}"#
        )
        let attributes = try XCTUnwrap(user.attributes)

        XCTAssertEqual(stringifyManagedAttribute(try XCTUnwrap(attributes["email"])), "ada@example.com")
        XCTAssertEqual(stringifyManagedAttribute(try XCTUnwrap(attributes["age"])), "42")
        XCTAssertEqual(stringifyManagedAttribute(try XCTUnwrap(attributes["verified"])), "true")
        XCTAssertEqual(stringifyManagedAttribute(try XCTUnwrap(attributes["name"])), #"{"given":"Ada"}"#)
        XCTAssertEqual(stringifyManagedAttribute(try XCTUnwrap(attributes["tags"])), #"["a","b"]"#)
    }

    func testCandidatesUseResolvedNames() throws {
        let users: ManagedUserListResponse = try decode(
            #"{"totalResults":1,"startIndex":1,"count":1,"users":[{"id":"u-1","ouId":"ou","type":"customer","# +
            #""attributes":{"given_name":"Ada","family_name":"Lovelace"}}]}"#
        )

        XCTAssertEqual(AdminCandidates.users(users), [IdentityCandidate(id: "u-1", label: "Ada Lovelace")])
        XCTAssertEqual(AdminCandidates.agents(nil), [])
    }

    func testBaseComponentsRenderStandalone() throws {
        let state = ThunderIDState(client: ThunderIDClient(), i18n: i18n)
        let user: ManagedUser = try decode(#"{"id":"u-1","ouId":"ou","type":"customer","display":"Alice"}"#)
        let views: [AnyView] = [
            AnyView(BaseUserList(users: [user], totalResults: 1, onPageChange: { _ in }, onSelect: { _ in })),
            AnyView(BaseUserDetails(user: user, groups: [], onDelete: {})),
            AnyView(BaseUserDetails(user: nil, error: "x")),
            AnyView(BaseGroupMembers(members: [GroupMember(id: "u-1", type: .user, display: "Alice")])),
            AnyView(BaseRoleAssignments(assignments: [], candidates: [.user: []], onAssign: { _ in })),
            AnyView(BaseRolePermissions(permissions: [RoleResourcePermissions(resourceServerId: "rs", permissions: ["a"])])),
            AnyView(BaseAgentCreate(agentTypes: [AdminOption(label: "Default", value: "default")]) { _ in })
        ]

        for view in views {
            let renderer = ImageRenderer(
                content: view
                    .environmentObject(i18n)
                    .environmentObject(state)
                    .frame(width: 400)
            )
            XCTAssertNotNil(renderer.cgImage)
        }
    }

    // MARK: - Content closures

    private final class Captured<Value> {
        var value: Value?
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

    func testListContentReceivesRowsAndPagination() throws {
        let user: ManagedUser = try decode(#"{"id":"u-1","ouId":"ou","type":"customer","display":"Alice"}"#)
        let captured = Captured<AdminListState<ManagedUser>>()

        render(
            BaseUserList(users: [user], limit: 20, offset: 20, totalResults: 45, onPageChange: { _ in }) { state in
                let _ = (captured.value = state)
                Text(state.rows.map(\.id).joined())
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertEqual(state.rows.map(\.id), ["u-1"])
        XCTAssertEqual(state.totalResults, 45)
        XCTAssertEqual(state.offset, 20)
        XCTAssertNotNil(state.onPageChange)
        XCTAssertNil(state.onSelect)
    }

    func testDetailsContentHidesCredentialsAndReadOnlyActions() throws {
        let user: ManagedUser = try decode(
            #"{"id":"u-1","ouId":"ou","type":"customer","display":"Alice","isReadOnly":true,"# +
            #""attributes":{"username":"alice","password":"secret"}}"#
        )
        let captured = Captured<UserDetailsState>()

        render(
            BaseUserDetails(user: user, onDelete: {}, onUpdate: { _ in }) { state in
                let _ = (captured.value = state)
                Text(state.displayName)
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertEqual(state.displayName, "Alice")
        XCTAssertEqual(Array(state.attributes.keys), ["username"])
        XCTAssertNil(state.onDelete)
        XCTAssertNil(state.onUpdate)
    }

    func testMembersAndPermissionsContentGetTheirData() throws {
        let members = Captured<GroupMembersState>()
        let permissions = Captured<RolePermissionsState>()

        render(
            BaseGroupMembers(
                members: [GroupMember(id: "u-1", type: .user, display: "Alice")],
                onAdd: { _ in },
                onRemove: { _ in }
            ) { state in
                let _ = (members.value = state)
                Text("\(state.members.count)")
            }
        )
        render(
            BaseRolePermissions(
                permissions: [
                    RoleResourcePermissions(resourceServerId: "rs-1", permissions: ["read"]),
                    RoleResourcePermissions(resourceServerId: "rs-2", permissions: [])
                ],
                resourceServerNames: ["rs-1": "Orders API"]
            ) { state in
                let _ = (permissions.value = state)
                Text("\(state.permissions.count)")
            }
        )

        let membersState = try XCTUnwrap(members.value)
        XCTAssertNil(membersState.onAdd, "Adding needs candidates as well as onAdd")
        XCTAssertNotNil(membersState.onRemove)
        let permissionsState = try XCTUnwrap(permissions.value)
        XCTAssertEqual(permissionsState.permissions.map(\.resourceServerId), ["rs-1"])
        XCTAssertEqual(permissionsState.resourceServerName(for: "rs-1"), "Orders API")
        XCTAssertEqual(permissionsState.resourceServerName(for: "rs-9"), "rs-9")
    }

    func testFormContentDoesNotSubmitInvalidValues() throws {
        let captured = Captured<NamedResourceFormState>()
        var submissions: [NamedResourceSubmission] = []

        render(
            BaseGroupCreate(onSubmit: { submissions.append($0) }) { state in
                let _ = (captured.value = state)
                TextField("Name", text: state.name)
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertFalse(state.isValid)
        state.submit()
        XCTAssertTrue(submissions.isEmpty)
    }

    // MARK: - Search and filters

    func testEqualityFilterTrimsAndRejectsInvalidInput() {
        XCTAssertEqual(ManagementFilter.equality(attribute: "username", value: "  ada "), #"username eq "ada""#)
        XCTAssertEqual(ManagementFilter.equality(attribute: "name", value: #"Say "hi""#), #"name eq "Say hi""#)
        XCTAssertNil(ManagementFilter.equality(attribute: "username", value: "   "))
        XCTAssertNil(ManagementFilter.equality(attribute: "user name", value: "ada"))
    }

    func testListContentReceivesTheSearch() throws {
        let captured = Captured<AdminListState<ManagedUser>>()
        let search = AdminSearch(attribute: "email", value: "ada@example.com")

        render(
            BaseUserList(
                users: [],
                search: search,
                searchAttributes: [AdminOption(label: "Email", value: "email")],
                onSearch: { _ in }
            ) { state in
                let _ = (captured.value = state)
                Text("\(state.rows.count)")
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertEqual(state.search, search)
        XCTAssertEqual(state.searchAttributes.map(\.value), ["email"])
        XCTAssertNotNil(state.onSearch)
    }

    func testDefaultListsRenderWithSearchAndTypeFilter() {
        render(
            BaseUserList(
                users: [],
                search: AdminSearch(attribute: "username", value: "nobody"),
                searchAttributes: [AdminOption(label: "Username", value: "username")],
                onSearch: { _ in }
            )
        )
        render(BaseRoleAssignments(assignments: [], typeFilter: .group, onTypeFilterChange: { _ in }))
    }

    func testRoleAssignmentsContentReceivesTheTypeFilter() throws {
        let captured = Captured<RoleAssignmentsState>()

        render(
            BaseRoleAssignments(assignments: [], typeFilter: .agent, onTypeFilterChange: { _ in }) { state in
                let _ = (captured.value = state)
                Text("\(state.assignments.count)")
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertEqual(state.typeFilter, .agent)
        XCTAssertNotNil(state.onTypeFilterChange)
    }
}
