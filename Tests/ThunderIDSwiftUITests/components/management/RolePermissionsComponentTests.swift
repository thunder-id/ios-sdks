// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers editing a role's permissions: the built-in UI, a custom render, the permission helpers and
/// the candidates query.
@MainActor
final class RolePermissionsComponentTests: XCTestCase {
    private let i18n = ThunderIDI18n(language: "en-US", storageKey: "role_permissions_component_tests_locale")

    private final class Captured<Value> {
        var value: Value?
    }

    private let granted = [
        RoleResourcePermissions(resourceServerId: "rs-1", permissions: ["orders:read"]),
        RoleResourcePermissions(resourceServerId: "rs-2", permissions: [])
    ]

    private let candidates = [
        RolePermissionCandidate(resourceServerId: "rs-1", name: "Orders API", permissions: ["orders:read", "orders:write"]),
        RolePermissionCandidate(resourceServerId: "rs-3", name: "Billing API", permissions: ["billing:read"])
    ]

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
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

    // MARK: - Defaults

    func testEditingIsOffByDefault() {
        XCTAssertFalse(RolePermissions(roleId: "r-1").editable)
        XCTAssertEqual(RolePermissions(roleId: "r-1").administrationMode, .native)
        XCTAssertNil(BaseRolePermissions(permissions: granted).onAdd)
        XCTAssertNil(BaseRolePermissions(permissions: granted).onRemove)
    }

    func testDefaultStringsCarryThePermissionKeys() {
        let keys = [
            "add", "fields.resource_server", "fields.permission", "fields.permission_placeholder",
            "fields.permission_empty", "remove_label", "remove_confirm", "update_error", "options_error"
        ]
        for key in keys {
            XCTAssertNotNil(DefaultStrings.all["admin.roles.permissions.\(key)"], "Missing admin.roles.permissions.\(key)")
        }
        XCTAssertEqual(
            i18n.resolve("admin.roles.permissions.remove_confirm", ["permission": "orders:read"]),
            "Remove orders:read from this role?"
        )
    }

    // MARK: - Built-in UI

    func testBuiltInUIRendersReadOnlyAndEditable() {
        render(BaseRolePermissions(permissions: granted))
        render(BaseRolePermissions(permissions: granted, candidates: candidates, onAdd: { _ in }, onRemove: { _ in }))
        render(BaseRolePermissions(permissions: [], candidates: [], isMutating: true, onAdd: { _ in }))
        render(BaseRolePermissions(permissions: [], isLoading: true))
        render(BaseRolePermissions(permissions: [], error: "Could not update the permissions. Please try again."))
    }

    func testConnectedPermissionsRenderWithoutAServer() {
        render(RolePermissions(roleId: "r-1"))
        render(RolePermissions(roleId: "r-1", editable: true, administrationMode: .flow))
        render(RoleDetails(roleId: "r-1", editable: true))
    }

    // MARK: - Custom render

    func testContentGetsTheActionsOnlyWhenEditable() throws {
        let editable = Captured<RolePermissionsState>()
        let readOnly = Captured<RolePermissionsState>()
        var added: [RolePermission] = []
        var removed: [RolePermission] = []

        render(
            BaseRolePermissions(
                permissions: granted,
                candidates: candidates,
                isMutating: true,
                onAdd: { added.append($0) },
                onRemove: { removed.append($0) }
            ) { state in
                let _ = (editable.value = state)
                Text("\(state.permissions.count)")
            }
        )
        render(
            BaseRolePermissions(permissions: granted) { state in
                let _ = (readOnly.value = state)
                Text("\(state.permissions.count)")
            }
        )

        let state = try XCTUnwrap(editable.value)
        XCTAssertEqual(state.permissions.map(\.resourceServerId), ["rs-1"])
        XCTAssertEqual(state.candidates, candidates)
        XCTAssertTrue(state.isMutating)
        XCTAssertEqual(state.resourceServerName(for: "rs-1"), "Orders API", "Names come from the candidates")
        state.onAdd?(RolePermission(resourceServerId: "rs-3", permission: "billing:read"))
        state.onRemove?(RolePermission(resourceServerId: "rs-1", permission: "orders:read"))
        XCTAssertEqual(added, [RolePermission(resourceServerId: "rs-3", permission: "billing:read")])
        XCTAssertEqual(removed, [RolePermission(resourceServerId: "rs-1", permission: "orders:read")])

        let plain = try XCTUnwrap(readOnly.value)
        XCTAssertNil(plain.candidates)
        XCTAssertNil(plain.onAdd)
        XCTAssertNil(plain.onRemove)
    }

    func testAddingNeedsCandidatesAsWellAsOnAdd() throws {
        let captured = Captured<RolePermissionsState>()
        render(
            BaseRolePermissions(permissions: granted, onAdd: { _ in }) { state in
                let _ = (captured.value = state)
                Text("")
            }
        )
        XCTAssertNil(try XCTUnwrap(captured.value).onAdd)
    }

    func testGivenNamesWinOverCandidateNames() throws {
        let captured = Captured<RolePermissionsState>()
        render(
            BaseRolePermissions(
                permissions: granted,
                resourceServerNames: ["rs-1": "Orders"],
                candidates: candidates,
                onAdd: { _ in }
            ) { state in
                let _ = (captured.value = state)
                Text("")
            }
        )
        XCTAssertEqual(try XCTUnwrap(captured.value).resourceServerName(for: "rs-1"), "Orders")
    }

    // MARK: - Permission helpers

    func testAddingAndRemovingPermissions() {
        let start = [RoleResourcePermissions(resourceServerId: "rs-1", permissions: ["a"])]

        let added = RolePermission.adding(RolePermission(resourceServerId: "rs-1", permission: "b"), to: start)
        XCTAssertEqual(added, [RoleResourcePermissions(resourceServerId: "rs-1", permissions: ["a", "b"])])
        XCTAssertEqual(RolePermission.adding(RolePermission(resourceServerId: "rs-1", permission: "a"), to: start), start)
        let other = RolePermission.adding(RolePermission(resourceServerId: "rs-2", permission: "c"), to: start)
        XCTAssertEqual(other.map(\.resourceServerId), ["rs-1", "rs-2"])

        XCTAssertEqual(
            RolePermission.removing(RolePermission(resourceServerId: "rs-1", permission: "a"), from: added),
            [RoleResourcePermissions(resourceServerId: "rs-1", permissions: ["b"])]
        )
        XCTAssertEqual(RolePermission.removing(RolePermission(resourceServerId: "rs-1", permission: "a"), from: start), [])
    }

    // MARK: - State

    private func makeState() async throws -> ThunderIDState {
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "test-client")
        let storage = InMemoryStorageAdapter()
        try TokenStore(storage: storage).save(
            TokenResponse(accessToken: "test-access-token", tokenType: "Bearer", expiresIn: 3600)
        )
        let client = ThunderIDClient()
        _ = try await client.initialize(config: config, storage: storage, session: MockURLProtocol.makeSession())
        return ThunderIDState(client: client, i18n: ThunderIDI18n())
    }

    func testCandidatesListTheResourceServersAndTheirActions() async throws {
        let state = try await makeState()
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let body = path.hasSuffix("/actions")
                ? #"{"actions":[{"id":"a-1","name":"Read","handle":"read","permission":"\#(path.contains("rs-1") ? "orders:read" : "billing:read")"}]}"#
                : #"{"resourceServers":[{"id":"rs-1","name":"Orders API","identifier":"orders","type":"API","ouId":"ou","delimiter":":"},"#
                    + #"{"id":"rs-2","name":"Billing API","identifier":"billing","type":"API","ouId":"ou","delimiter":":"}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let query = state.rolePermissionCandidatesQuery()
        await query.refetch()

        XCTAssertNil(query.error)
        XCTAssertEqual(query.data, [
            RolePermissionCandidate(resourceServerId: "rs-1", name: "Orders API", permissions: ["orders:read"]),
            RolePermissionCandidate(resourceServerId: "rs-2", name: "Billing API", permissions: ["billing:read"])
        ])
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/resource-servers/rs-1/actions"), 1)
    }

    func testUpdatingARoleSavesItsPermissions() async throws {
        let state = try await makeState()
        var sent: [String: Any]?
        MockURLProtocol.handler = { request in
            if request.httpMethod == "PUT", let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    data.append(buffer, count: read)
                }
                stream.close()
                sent = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            let body = #"{"id":"r-1","name":"Viewer","ouId":"ou","permissions":[{"resourceServerId":"rs-1","permissions":["a","b"]}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let permissions = RolePermission.adding(
            RolePermission(resourceServerId: "rs-1", permission: "b"),
            to: [RoleResourcePermissions(resourceServerId: "rs-1", permissions: ["a"])]
        )

        let role = await state.updateRoleMutation().mutate(
            (id: "r-1", request: UpdateRoleRequest(name: "Viewer", ouId: "ou", permissions: permissions))
        )

        XCTAssertEqual(role?.permissions.first?.permissions, ["a", "b"])
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/roles/r-1"), 1)
        let sentPermissions = sent?["permissions"] as? [[String: Any]]
        XCTAssertEqual(sentPermissions?.first?["permissions"] as? [String], ["a", "b"])
    }
}
