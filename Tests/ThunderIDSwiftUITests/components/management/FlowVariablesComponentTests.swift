// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers the flow variables form, its rules, the model behind it, and the shared flow list, built in and
/// through a custom render.
@MainActor
final class FlowVariablesComponentTests: XCTestCase {
    private let i18n = ThunderIDI18n(language: "en-US", storageKey: "flow_variables_component_tests_locale")

    private struct Failure: Error {}

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

    private func variables() throws -> [FlowVariableDefinition] {
        try decode(
            #"[{"identifier":"brand","type":"TEXT_INPUT","label":"Brand","defaultValue":"Acme","#
                + #""validation":[{"type":"minLength","value":2,"message":"Brand too short"}]},"#
                + #"{"identifier":"otp","type":"NUMBER_INPUT","defaultValue":60,"min":30,"max":300},"#
                + #"{"identifier":"mfa","type":"BOOLEAN_INPUT","defaultValue":false},"#
                + #"{"identifier":"idp","type":"CONNECTION_SELECT","category":"identity-provider"},"#
                + #"{"identifier":"mode","type":"SELECT","options":["fast","safe"],"defaultValue":"safe"}]"#
        )
    }

    private func connections() throws -> [ConnectionInstance] {
        try decode(
            #"[{"id":"c-1","name":"Google","type":"google","categories":["identity-provider"]},"#
                + #"{"id":"c-2","name":"Okta","type":"oidc","categories":["identity-provider"]}]"#
        )
    }

    /// Shared with the unit: `otp` and `idp` are editable, `idp` limited to `c-1`; `mfa` is pinned on.
    private func overlay() throws -> ResolvedOverlay {
        try decode(
            #"{"ouId":"ou-1","isOwnedByOU":false,"rules":{"variables.otp":{"editable":true},"#
                + #""variables.idp":{"editable":true,"allowedValues":["c-1"]},"variables.mfa":{"value":["true"]}}}"#
        )
    }

    // MARK: - Form rules

    func testStartingValuesTakeTheUnitsValuesOnlyWhereItMaySetThem() throws {
        let logic = FlowVariablesFormLogic(variables: try variables(), overlay: try overlay(), connections: [])
        let starting = logic.startingValues(["brand": .string("Other"), "otp": .number(90)])
        XCTAssertEqual(starting, ["brand": .string("Acme"), "otp": .number(90), "mfa": .bool(true), "mode": .string("safe")])
        XCTAssertEqual(logic.defaults(), ["brand": .string("Acme"), "otp": .number(60), "mfa": .bool(true), "mode": .string("safe")])
    }

    func testOnlyEditableVariablesAreValidatedAndOverridden() throws {
        let logic = FlowVariablesFormLogic(variables: try variables(), overlay: try overlay(), connections: try connections())
        var values = logic.startingValues(nil)
        XCTAssertEqual(logic.problems(values).keys.sorted(), ["idp"])
        values["idp"] = .string("c-1")
        values["otp"] = .string("120")
        values["brand"] = .string("X")
        XCTAssertTrue(logic.problems(values).isEmpty)
        XCTAssertEqual(logic.overrides(values), ["idp": .string("c-1"), "otp": .number(120)])
        values["otp"] = .number(5)
        XCTAssertEqual(logic.problems(values)["otp"]?.code, .min)
        XCTAssertEqual(logic.options(try variables()[3]).map(\.value), ["c-1"])
    }

    func testEveryVariableIsEditableWithoutAnOverlay() throws {
        let logic = FlowVariablesFormLogic(variables: try variables(), overlay: nil, connections: try connections())
        var values = logic.startingValues(nil)
        values["brand"] = .string("B")
        values["idp"] = .string("c-2")
        let problems = logic.problems(values)
        XCTAssertEqual(problems["brand"], FlowVariableValidationError(code: .minLength, message: "Brand too short"))
        XCTAssertEqual(FlowVariablesFormLogic.message(try XCTUnwrap(problems["brand"]), i18n: i18n), "Brand too short")
        XCTAssertEqual(
            FlowVariablesFormLogic.message(FlowVariableValidationError(code: .notOption), i18n: i18n),
            "Choose one of the available options."
        )
        XCTAssertEqual(logic.options(try variables()[3]).count, 2)
    }

    // MARK: - Model

    private func model(
        flow: Result<String, Failure> = .success(""),
        connectionsFail: Bool = false,
        saveFails: Bool = false,
        saved: Captured<FlowVariableValues>? = nil
    ) -> FlowVariablesModel {
        let decodeFlow: () throws -> FlowDefinition = {
            let json = try flow.get()
            return try JSONDecoder().decode(
                FlowDefinition.self,
                from: Data(
                    (json.isEmpty
                        ? #"{"id":"f-1","name":"Login","handle":"login","flowType":"AUTHENTICATION","isOwnedByOU":false,"#
                            + #""variables":[{"identifier":"idp","type":"CONNECTION_SELECT"},"#
                            + #"{"identifier":"otp","type":"NUMBER_INPUT","defaultValue":60}]}"#
                        : json).utf8
                )
            )
        }
        let connectionsJSON = #"{"totalResults":1,"startIndex":1,"count":1,"connections":"#
            + #"[{"id":"c-1","name":"Google","type":"google","categories":["identity-provider"]}]}"#
        return FlowVariablesModel(
            operations: FlowVariablesModel.Operations(
                flow: { try decodeFlow() },
                values: { try JSONDecoder().decode(FlowVariablesResponse.self, from: Data(#"{"values":{"otp":90}}"#.utf8)) },
                overlay: { try JSONDecoder().decode(ResolvedOverlay.self, from: Data(#"{"isOwnedByOU":false}"#.utf8)) },
                connections: {
                    if connectionsFail { throw Failure() }
                    return try JSONDecoder().decode(ConnectionListResponse.self, from: Data(connectionsJSON.utf8))
                },
                update: { values in
                    if saveFails { throw ThunderIDError(code: .forbidden, message: "denied") }
                    saved?.value = values
                    return FlowVariablesResponse(values: values.mapValues(\.anyCodable))
                }
            )
        )
    }

    func testModelLoadsTheVariablesValuesRulesAndConnections() async {
        let model = model()
        await model.load()
        XCTAssertTrue(model.isLoaded)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.definitions.map(\.identifier), ["idp", "otp"])
        XCTAssertEqual(model.overrides, ["otp": .number(90)])
        XCTAssertEqual(model.overlay?.isOwnedByOU, false)
        XCTAssertEqual(model.connections.map(\.id), ["c-1"])
        XCTAssertFalse(model.isLoading)
    }

    func testModelSkipsConnectionsWhenNoVariableNeedsThem() async {
        let model = model(
            flow: .success(#"{"id":"f","name":"n","handle":"h","flowType":"AUTHENTICATION","variables":[]}"#),
            connectionsFail: true
        )
        await model.load()
        XCTAssertTrue(model.isLoaded)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.connections.isEmpty)
    }

    func testModelReportsALoadFailure() async {
        let failed = model(flow: .failure(Failure()))
        await failed.load()
        XCTAssertFalse(failed.isLoaded)
        XCTAssertNotNil(failed.error)

        let noConnections = model(connectionsFail: true)
        await noConnections.load()
        XCTAssertTrue(noConnections.isLoaded)
        XCTAssertNotNil(noConnections.error)
    }

    func testModelSavesAndReportsASaveFailureWithoutThrowing() async {
        let saved = Captured<FlowVariableValues>()
        let model = model(saved: saved)
        let result = await model.save(["otp": .number(120)])
        XCTAssertEqual(result, ["otp": .number(120)])
        XCTAssertEqual(saved.value, ["otp": .number(120)])
        XCTAssertEqual(model.overrides, ["otp": .number(120)])
        XCTAssertNil(model.saveError)

        let failing = self.model(saveFails: true)
        let nothing = await failing.save(["otp": .number(1)])
        XCTAssertNil(nothing)
        XCTAssertEqual((failing.saveError as? ThunderIDError)?.code, .forbidden)
        XCTAssertEqual(
            i18n.managementErrorMessage(failing.saveError, fallbackKey: "admin.flowVariables.error"),
            "You do not have permission to do this."
        )
        XCTAssertFalse(failing.isSaving)
    }

    // MARK: - Built-in UI

    func testBaseFormRendersStandalone() throws {
        render(
            BaseFlowVariables(
                variables: try variables(),
                connections: try connections(),
                initialValues: ["otp": .number(90)],
                overlay: try overlay(),
                title: "Flow variables",
                ouName: "Acme",
                ownerName: "Root",
                showScopeNotice: true,
                onSubmit: { _, _ in },
                onCancel: {},
                onCreateConnection: {}
            )
        )
        render(BaseFlowVariables(variables: try variables(), readOnly: true))
        render(BaseFlowVariables(variables: [], error: "Could not load the variables. Please try again."))
    }

    func testConnectedComponentsRenderWithoutAServer() {
        render(FlowVariablesForm(flowId: "f-1", ouId: "ou-1"))
        render(SharedFlowList(ouId: "ou-1"))
        render(SharedFlowList(ouId: "ou-1", ownership: .all, flowType: "AUTHENTICATION"))
    }

    // MARK: - Custom render

    func testContentGetsTheValuesSettersAndSubmit() throws {
        let captured = Captured<FlowVariablesFormState>()
        let preview = Captured<FlowVariablesFormState>()
        render(
            BaseFlowVariables(variables: try variables(), overlay: try overlay(), onSubmit: { _, _ in }) { form in
                let _ = (captured.value = form)
                Text("")
            }
        )
        render(
            BaseFlowVariables(variables: try variables()) { form in
                let _ = (preview.value = form)
                Text("")
            }
        )

        let form = try XCTUnwrap(captured.value)
        XCTAssertEqual(form.values["mfa"], .bool(true))
        XCTAssertFalse(form.isValid)
        XCTAssertTrue(form.errors.isEmpty)
        XCTAssertFalse(form.rule(for: form.variables[2]).editable)
        XCTAssertEqual(form.options(for: form.variables[4]).map(\.label), ["fast", "safe"])
        XCTAssertNotNil(form.submit)
        XCTAssertNil(try XCTUnwrap(preview.value).submit)
    }

    // MARK: - Shared flow list

    private func flowPage() throws -> ManagedFlowListResponse {
        try decode(
            #"{"totalResults":40,"flows":[{"id":"f-1","handle":"login","flowType":"AUTHENTICATION","isOwnedByOU":true},"#
                + #"{"id":"f-2","handle":"mfa","flowType":"AUTHENTICATION","isOwnedByOU":false,"name":"MFA"},"#
                + #"{"id":"f-3","handle":"signup","flowType":"REGISTRATION","isOwnedByOU":false},"#
                + #"{"id":"f-4","handle":"legacy","flowType":"AUTHENTICATION"}]}"#
        )
    }

    func testOwnershipNarrowsThePageOnTheClient() throws {
        let response = try flowPage()
        let shared = SharedFlowPage(response: response, ownership: .shared, limit: 1, offset: 1)
        XCTAssertEqual(shared.flows.map(\.id), ["f-3"])
        XCTAssertEqual(shared.totalResults, 2)
        let owned = SharedFlowPage(response: response, ownership: .owned, limit: 20, offset: 0)
        XCTAssertEqual(owned.flows.map(\.id), ["f-1"])
        XCTAssertEqual(owned.totalResults, 1)
        let all = SharedFlowPage(response: response, ownership: .all, limit: 20, offset: 0)
        XCTAssertEqual(all.flows.count, 4)
        XCTAssertEqual(all.totalResults, 40)
        XCTAssertEqual(SharedFlowPage(response: nil, ownership: .shared, limit: 20, offset: 0).totalResults, 0)
    }

    func testBaseListRendersAndHandsItsStateToContent() throws {
        let flows = try flowPage().flows
        render(BaseSharedFlowList(flows: flows, totalResults: 40, selectedFlowId: "f-2", onPageChange: { _ in }, onSelect: { _ in }))
        render(BaseSharedFlowList(flows: [], isLoading: true))
        render(BaseSharedFlowList(flows: [], error: "Could not load flows. Please try again."))

        let captured = Captured<AdminListState<ManagedFlow>>()
        var selected: [String] = []
        render(BaseSharedFlowList(flows: flows, selectedFlowId: "f-1", onSelect: { selected.append($0.id) }) { list in
            let _ = (captured.value = list)
            Text("")
        })
        let list = try XCTUnwrap(captured.value)
        XCTAssertEqual(list.rows.count, 4)
        XCTAssertEqual(list.totalResults, 4)
        XCTAssertEqual(list.selectedId, "f-1")
        XCTAssertNil(list.onPageChange)
        list.onSelect?(list.rows[1])
        XCTAssertEqual(selected, ["f-2"])
    }

    func testOwnershipDefaultsToShared() {
        XCTAssertEqual(SharedFlowList(ouId: "ou-1").ownership, .shared)
        XCTAssertFalse(FlowVariablesForm(flowId: "f-1", ouId: "ou-1").readOnly)
    }

    // MARK: - State wrappers

    func testFlowsQueryListsAnOrganizationUnitsFlows() async throws {
        defer { MockURLProtocol.reset() }
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "test-client")
        let storage = InMemoryStorageAdapter()
        try TokenStore(storage: storage).save(TokenResponse(accessToken: "token", tokenType: "Bearer", expiresIn: 3600))
        let client = ThunderIDClient()
        _ = try await client.initialize(config: config, storage: storage, session: MockURLProtocol.makeSession())
        let state = ThunderIDState(client: client, i18n: i18n)
        var urls: [String] = []
        MockURLProtocol.handler = { request in
            urls.append(request.url?.absoluteString ?? "")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"totalResults":0,"flows":[]}"#.utf8))
        }

        let query = state.flowsQuery(flowType: "AUTHENTICATION", ouId: "ou-1", limit: 100, offset: 0)
        await query.refetch()

        XCTAssertNotNil(query.data)
        XCTAssertEqual(query.key.first, FlowQueryKeys.flows)
        XCTAssertEqual(
            urls,
            ["https://localhost:8090/flows?filter=ouId%20eq%20%22ou-1%22&flowType=AUTHENTICATION&limit=100&offset=0"]
        )
    }
}
