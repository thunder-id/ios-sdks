// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers the reactive wrappers the admin components use to run administration flows and account
/// lifecycle actions, against the real `HTTPClient` path through `MockURLProtocol`.
@MainActor
final class AdministrationFlowStateTests: XCTestCase {
    private static let baseUrl = "https://localhost:8090"

    /// Answers like the server: the `flow` server-config section (configured handle by key), the
    /// administration flow listing (one flow per configured handle, with the id `id-<handle>`), flow
    /// execution, and `resource` for every other request. It records every request.
    private final class FlowServer: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [URLRequest] = []
        let configured: [String: String]
        let resource: String

        init(configured: [String: String], resource: String) {
            self.configured = configured
            self.resource = resource
        }

        var requests: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        /// The JSON bodies sent to `POST /flow/execute`, in order.
        var executions: [[String: Any]] {
            requests
                .filter { $0.url?.path == "/flow/execute" }
                .compactMap { request in
                    let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
                    return body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                }
        }

        func answer(_ request: URLRequest) -> (HTTPURLResponse, Data) {
            lock.lock()
            recorded.append(request)
            lock.unlock()
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body(for: url.path).utf8))
        }

        private func body(for path: String) -> String {
            switch path {
            case "/server-config/flow":
                let entries = configured.map { #""\#($0.key)":{"defaultHandle":"\#($0.value)"}"# }
                return #"{"merged":{\#(entries.joined(separator: ","))}}"#
            case "/flows":
                let flows = configured.values.map { #"{"flowType":"ADMINISTRATION","handle":"\#($0)","id":"id-\#($0)"}"# }
                return #"{"flows":[\#(flows.joined(separator: ","))]}"#
            case "/flow/execute":
                return #"{"flowStatus":"COMPLETE","data":{"additionalData":{"emailSent":"false"}}}"#
            default:
                return resource
            }
        }

        private static func read(_ stream: InputStream) -> Data {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            return data
        }
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeState(serving server: FlowServer) async throws -> ThunderIDState {
        MockURLProtocol.handler = { server.answer($0) }
        let config = ThunderIDConfig(baseUrl: Self.baseUrl, clientId: "test-client")
        let storage = InMemoryStorageAdapter()
        try TokenStore(storage: storage).save(
            TokenResponse(accessToken: "admin-token", tokenType: "Bearer", expiresIn: 3600)
        )
        let client = ThunderIDClient()
        _ = try await client.initialize(config: config, storage: storage, session: MockURLProtocol.makeSession())
        return ThunderIDState(client: client, i18n: ThunderIDI18n())
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - Lifecycle

    func testReadsOnlyTheFlowsOfTheKindAndOffersWhatIsConfigured() async throws {
        let server = FlowServer(
            configured: ["userUnlockFlow": "unlock-user", "agentSuspendFlow": "suspend-agent"],
            resource: "{}"
        )
        let state = try await makeState(serving: server)

        let flows = await state.accountLifecycleFlowsQuery(kind: .user).refetch()

        XCTAssertEqual(flows, [.userUnlock: "id-unlock-user"])
        XCTAssertEqual(
            AccountLifecycleAction.available(for: .user, status: .locked, configuredFlows: flows ?? [:]),
            [.unlock]
        )
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/flow/execute"), 0)
    }

    func testRunsAnActionThroughItsFlowAndRefetchesTheUser() async throws {
        let server = FlowServer(
            configured: ["userSuspendFlow": "suspend-user"],
            resource: #"{"id":"u-1","ouId":"ou","type":"customer","status":{"value":"ACTIVE"}}"#
        )
        let state = try await makeState(serving: server)
        let user = state.userQuery(id: "u-1")
        await user.refetch()
        XCTAssertEqual(user.data?.status?.value, .active)

        let result = await state.accountLifecycleMutation(kind: .user).mutate(
            AccountLifecycleInput(subject: "u-1", action: .suspend, operatorNote: "Ticket 4521")
        )

        XCTAssertEqual(result, AccountLifecycleResult(emailSent: false))
        XCTAssertEqual(server.executions.first?["flowId"] as? String, "id-suspend-user")
        XCTAssertEqual(
            server.executions.first?["inputs"] as? [String: String],
            ["subject": "u-1", "operatorNote": "Ticket 4521"]
        )
        await waitFor { MockURLProtocol.requestCount(forPath: "/users/u-1") == 2 }
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/users/u-1"), 2)
    }

    func testReportsAnActionWithNoConfiguredFlowWithoutThrowing() async throws {
        let server = FlowServer(configured: [:], resource: "{}")
        let state = try await makeState(serving: server)
        let mutation = state.accountLifecycleMutation(kind: .agent)

        let result = await mutation.mutate(AccountLifecycleInput(subject: "a-1", action: .unlock))

        XCTAssertNil(result)
        XCTAssertEqual((mutation.error as? ThunderIDError)?.code, .administrationFlowNotConfigured)
        XCTAssertTrue(server.executions.isEmpty)
    }

    // MARK: - Administration mode

    func testDeletesAUserThroughTheDeletionFlowInFlowMode() async throws {
        let server = FlowServer(configured: ["userDeletionFlow": "delete-user"], resource: "{}")
        let state = try await makeState(serving: server)

        let result: Void? = await state.deleteUserMutation(administrationMode: .flow).mutate("u-1")

        XCTAssertNotNil(result)
        XCTAssertEqual(server.executions.map { $0["inputs"] as? [String: String] }, [["subject": "u-1"]])
        XCTAssertFalse(server.requests.contains { $0.httpMethod == "DELETE" })
    }

    func testDeletesAUserDirectlyByDefault() async throws {
        let server = FlowServer(configured: ["userDeletionFlow": "delete-user"], resource: "{}")
        let state = try await makeState(serving: server)

        await state.deleteUserMutation().mutate("u-1")

        XCTAssertEqual(server.requests.map { $0.httpMethod ?? "" }, ["DELETE"])
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/server-config/flow"), 0)
    }

    func testRemovesMembersAndAssignmentsThroughTheirFlowsInFlowMode() async throws {
        let server = FlowServer(
            configured: [
                "groupMembershipRemovalFlow": "remove-member",
                "roleAssignmentRemovalFlow": "remove-assignment"
            ],
            resource: #"{"id":"g-1","name":"Admins","ouId":"ou"}"#
        )
        let state = try await makeState(serving: server)

        await state.removeGroupMembersMutation(administrationMode: .flow)
            .mutate((groupId: "g-1", members: [GroupMemberInput(id: "u-1", type: .user)]))
        await state.removeRoleAssignmentsMutation(administrationMode: .flow)
            .mutate((roleId: "r-1", assignments: [RoleAssignmentInput(id: "u-1", type: .user)]))

        XCTAssertEqual(server.executions.map { $0["flowId"] as? String }, ["id-remove-member", "id-remove-assignment"])
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/groups/g-1/members/remove"), 0)
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/roles/r-1/assignments/remove"), 0)
    }

    // MARK: - Connected details

    #if canImport(AppKit)
    /// Hosts a connected view in a window so its `.task` modifiers run, and keeps it until the test ends.
    private func host(_ view: some View, state: ThunderIDState) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: view.environmentObject(state.i18n).environmentObject(state)
        )
        window.orderBack(nil)
        return window
    }

    func testUserDetailsReadNoFlowConfigurationUnlessLifecycleActionsAreOn() async throws {
        let server = FlowServer(
            configured: ["userUnlockFlow": "unlock-user"],
            resource: #"{"id":"u-1","ouId":"ou","type":"customer","status":{"value":"LOCKED"}}"#
        )
        let state = try await makeState(serving: server)
        let window = host(UserDetails(userId: "u-1"), state: state)
        defer { window.close() }

        await waitFor { MockURLProtocol.requestCount(forPath: "/users/u-1") > 0 }

        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/users/u-1"), 1)
        XCTAssertEqual(MockURLProtocol.requestCount(forPath: "/server-config/flow"), 0)
    }

    func testUserDetailsOfferOnlyTheConfiguredActionsWhenTheyAreOn() async throws {
        let server = FlowServer(
            configured: ["userUnlockFlow": "unlock-user"],
            resource: #"{"id":"u-1","ouId":"ou","type":"customer","status":{"value":"LOCKED"}}"#
        )
        let state = try await makeState(serving: server)
        let captured = CapturedDetails()
        let window = host(
            UserDetails(userId: "u-1", lifecycleActions: true) { details in
                let _ = (captured.value = details)
                Text(details.displayName)
            },
            state: state
        )
        defer { window.close() }

        await waitFor { captured.value?.lifecycleActions.isEmpty == false }

        let details = try XCTUnwrap(captured.value)
        XCTAssertEqual(details.lifecycleActions, [.unlock])
        details.onLifecycleAction?(.unlock, nil)
        await waitFor { !server.executions.isEmpty }
        XCTAssertEqual(server.executions.first?["flowId"] as? String, "id-unlock-user")
        XCTAssertEqual(server.executions.first?["inputs"] as? [String: String], ["subject": "u-1"])
    }

    private final class CapturedDetails {
        var value: UserDetailsState?
    }
    #endif
}
