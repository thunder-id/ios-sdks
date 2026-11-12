// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Flows and connections scoped to an organization unit, and the flow variable helpers.
final class FlowVariablesTests: XCTestCase {
    private let base = ManagementTestServer.baseUrl

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func variable(
        _ type: FlowVariableType,
        _ identifier: String = "v",
        defaultValue: FlowVariableValue? = nil,
        options: [FlowVariableValue]? = nil,
        min: Double? = nil,
        max: Double? = nil,
        validation: [FlowVariableValidationRule]? = nil
    ) -> FlowVariableDefinition {
        FlowVariableDefinition(
            identifier: identifier,
            type: type,
            defaultValue: defaultValue,
            options: options,
            min: min,
            max: max,
            validation: validation
        )
    }

    // MARK: - Scoped to an organization unit

    func testFlowsAndConnectionsAreListedForAnOrganizationUnit() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        server.listing = { _ in
            #"{"totalResults":2,"flows":[{"id":"f-1","handle":"login","flowType":"AUTHENTICATION","isOwnedByOU":true},"#
                + #"{"id":"f-2","handle":"mfa","flowType":"AUTHENTICATION","isOwnedByOU":false}]}"#
        }
        server.resource = #"{"flows":[]}"#

        let flows = try await client.flows.list(flowType: "AUTHENTICATION", ouId: "ou-1", limit: 100, offset: 0)
        _ = try await client.flows.list()
        _ = try await client.flows.list(ouId: " ")
        server.resource = #"{"totalResults":0,"startIndex":1,"count":0,"connections":[]}"#
        _ = try await client.connections.list(category: "identity-provider", ouId: "o\"u-1", limit: 100)

        XCTAssertEqual(server.calls, [
            "GET \(base)/flows?filter=ouId%20eq%20%22ou-1%22&flowType=AUTHENTICATION&limit=100&offset=0",
            "GET \(base)/flows",
            "GET \(base)/flows",
            "GET \(base)/connections?category=identity-provider&filter=ouId%20eq%20%22ou-1%22&limit=100"
        ])
        XCTAssertEqual(flows.flows.map(\.isOwnedByOU), [true, false])
    }

    func testAFlowSharedWithAUnitComesBackAsItsVariables() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        server.resource = #"{"id":"f-1","name":"Login","handle":"login","flowType":"AUTHENTICATION","ouId":"ou-1","#
            + #""isOwnedByOU":false,"variables":[{"identifier":"brand","type":"TEXT_INPUT","defaultValue":"Acme"}]}"#

        let flow = try await client.flows.get(id: "f-1", ouId: "ou-1")
        _ = try await client.flows.get(id: "f-1")

        XCTAssertEqual(server.calls, ["GET \(base)/flows/f-1?ouId=ou-1", "GET \(base)/flows/f-1"])
        XCTAssertEqual(flow.isOwnedByOU, false)
        XCTAssertEqual(flow.ouId, "ou-1")
        XCTAssertTrue(flow.nodes.isEmpty)
        XCTAssertEqual(getFlowVariableDefinitions(flow), [variable(.textInput, "brand", defaultValue: .string("Acme"))])
    }

    func testAFailedFlowReadSurfacesAsAnAPIError() async throws {
        let server = ManagementTestServer()
        let client = try await server.makeClient()
        server.resourceStatus = 404
        server.resource = #"{"code":"FLM-1003","message":"Not found"}"#

        await assertThrowsThunderIDError(.notFound) { _ = try await client.flows.get(id: "f-1", ouId: "ou-1") }
        server.resourceStatus = 403
        await assertThrowsThunderIDError(.forbidden) { _ = try await client.connections.list(ouId: "ou-1") }
    }

    func testValuesConvertToAndFromJSON() throws {
        let response: FlowVariablesResponse = try decode(
            #"{"values":{"name":"Acme","otp":120,"ratio":0.5,"enabled":true,"nested":{"a":1}}}"#
        )
        XCTAssertEqual(
            response.variableValues,
            ["name": .string("Acme"), "otp": .number(120), "ratio": .number(0.5), "enabled": .bool(true)]
        )
        let request = FlowVariablesRequest(ouId: "ou-1", variables: ["otp": .number(120), "on": .bool(false)])
        XCTAssertEqual(request.values["otp"]?.value as? Int, 120)
        XCTAssertEqual(request.values["on"]?.value as? Bool, false)
        XCTAssertEqual(FlowVariableValue.number(2.5).text, "2.5")
        let values: [FlowVariableValue] = try decode(#"["a", 3, true]"#)
        XCTAssertEqual(values, [.string("a"), .number(3), .bool(true)])
        XCTAssertEqual(String(data: try JSONEncoder().encode(values), encoding: .utf8), #"["a",3,true]"#)
    }

    // MARK: - getFlowVariableDefinitions

    func testDefinitionsAreReadFromTheVariablesNodeOfAnOwnedFlow() throws {
        let flow: FlowDefinition = try decode(
            #"{"id":"f","name":"n","handle":"h","flowType":"AUTHENTICATION","nodes":[{"id":"start","type":"START"},"#
                + #"{"id":"vars","type":"VARIABLES","inputs":[{"identifier":"otp","type":"NUMBER_INPUT","min":1},"#
                + #"{"identifier":"broken"},{"type":"TEXT_INPUT"},{"identifier":"mode","type":"SELECT","#
                + #""options":["a","b"],"validation":[{"type":"regex","value":"^a","message":"Starts with a"}]}]}]}"#
        )
        let definitions = getFlowVariableDefinitions(flow)
        XCTAssertEqual(definitions.map(\.identifier), ["otp", "mode"])
        XCTAssertEqual(definitions[0].min, 1)
        XCTAssertEqual(definitions[1].options, [.string("a"), .string("b")])
        XCTAssertEqual(definitions[1].validation?.first?.message, "Starts with a")
        XCTAssertEqual(getFlowVariableDefinitions(nil), [])
        let noVariables: FlowDefinition = try decode(
            #"{"id":"f","name":"n","handle":"h","flowType":"AUTHENTICATION","nodes":[{"id":"s","type":"START"}]}"#
        )
        XCTAssertEqual(getFlowVariableDefinitions(noVariables), [])
    }

    // MARK: - getFlowVariableOptions

    func testSelectOptionsAreItsValuesNarrowedByTheRestriction() {
        let mode = variable(.select, options: [.string("a"), .number(2), .string("c")])
        XCTAssertEqual(getFlowVariableOptions(mode).map(\.value), ["a", "2", "c"])
        XCTAssertEqual(
            getFlowVariableOptions(
                mode,
                restriction: FlowVariableOptionRestriction(allowedValues: ["a", "2"], excludedValues: ["2"])
            ),
            [FlowVariableOption(label: "a", value: "a")]
        )
        XCTAssertEqual(getFlowVariableOptions(variable(.textInput)), [])
    }

    func testConnectionOptionsMatchCategoryAndVendor() throws {
        let connections: [ConnectionInstance] = try decode(
            #"[{"id":"c-1","name":"Google","type":"google","categories":["identity-provider"]},"#
                + #"{"id":"c-2","name":"GitHub","type":"github","categories":["identity-provider"]},"#
                + #"{"id":"c-3","name":"Twilio","type":"twilio","categories":["sms-provider"]}]"#
        )
        let anyIdp = FlowVariableDefinition(identifier: "idp", type: .connectionSelect, category: "IDENTITY_PROVIDER")
        XCTAssertEqual(getFlowVariableOptions(anyIdp, connections: connections).map(\.value), ["c-1", "c-2"])
        let google = FlowVariableDefinition(
            identifier: "idp",
            type: .connectionSelect,
            category: "identity_provider",
            connectionTypes: ["GOOGLE"]
        )
        XCTAssertEqual(
            getFlowVariableOptions(google, connections: connections),
            [FlowVariableOption(label: "Google", value: "c-1")]
        )
        let everything = FlowVariableDefinition(identifier: "any", type: .connectionSelect)
        XCTAssertEqual(
            getFlowVariableOptions(
                everything,
                connections: connections,
                restriction: FlowVariableOptionRestriction(excludedValues: ["c-3"])
            ).count,
            2
        )
    }

    // MARK: - resolveFlowVariableRule

    func testRulesFollowOwnershipAndPolicies() throws {
        let otp = variable(.numberInput, "otp", defaultValue: .number(60))
        XCTAssertEqual(resolveFlowVariableRule(otp), ResolvedFlowVariableRule(defaultValue: .number(60), editable: true))

        let owned: ResolvedOverlay = try decode(#"{"isOwnedByOU":true,"rules":{"variables.otp":{"value":["5"]}}}"#)
        XCTAssertEqual(
            resolveFlowVariableRule(otp, overlay: owned),
            ResolvedFlowVariableRule(defaultValue: .number(60), editable: true)
        )

        let shared: ResolvedOverlay = try decode(
            #"{"isOwnedByOU":false,"rules":{"variables.otp":{"editable":true,"value":["120"],"#
                + #""allowedValues":["90","120"],"excludedValues":["90"]},"variables.on":{"value":["true"]},"#
                + #""variables.mode":{"value":["2"]},"variables.name":{"value":["Beta"]}}}"#
        )
        XCTAssertEqual(
            resolveFlowVariableRule(otp, overlay: shared),
            ResolvedFlowVariableRule(
                allowedValues: ["90", "120"],
                defaultValue: .number(120),
                editable: true,
                excludedValues: ["90"]
            )
        )
        XCTAssertEqual(
            resolveFlowVariableRule(variable(.booleanInput, "on"), overlay: shared),
            ResolvedFlowVariableRule(defaultValue: .bool(true), editable: false)
        )
        XCTAssertEqual(
            resolveFlowVariableRule(variable(.select, "mode", options: [.number(2)]), overlay: shared).defaultValue,
            .number(2)
        )
        XCTAssertEqual(resolveFlowVariableRule(variable(.textInput, "name"), overlay: shared).defaultValue, .string("Beta"))
        let unnamed = resolveFlowVariableRule(variable(.textInput, "other", defaultValue: .string("x")), overlay: shared)
        XCTAssertEqual(unnamed, ResolvedFlowVariableRule(defaultValue: .string("x"), editable: false))
    }

    // MARK: - validateFlowVariableValue

    func testValidationByType() {
        let cases: [(FlowVariableDefinition, FlowVariableValue?, FlowVariableValidationError.Code?)] = [
            (variable(.booleanInput), nil, nil),
            (variable(.booleanInput), .bool(false), nil),
            (variable(.booleanInput), .string("yes"), .invalid),
            (variable(.textInput), nil, .required),
            (variable(.textInput), .string(""), .required),
            (variable(.textInput), .string("x"), nil),
            (variable(.numberInput, min: 1, max: 10), .number(5), nil),
            (variable(.numberInput, min: 1, max: 10), .string("7"), nil),
            (variable(.numberInput, min: 1, max: 10), .string("seven"), .invalid),
            (variable(.numberInput, min: 1, max: 10), .number(0), .min),
            (variable(.numberInput, min: 1, max: 10), .number(11), .max),
            (variable(.select, options: [.string("a"), .number(2)]), .number(2), nil),
            (variable(.select, options: [.string("a"), .number(2)]), .string("2"), nil),
            (variable(.select, options: [.bool(true), .bool(false)]), .string("true"), nil),
            (variable(.select, options: [.bool(true), .bool(false)]), .bool(false), nil),
            (variable(.select, options: [.bool(true), .bool(false)]), .string("yes"), .notOption),
            (variable(.emailInput), .string("a@b.co"), nil),
            (variable(.emailInput), .string("a@b"), .invalid),
            (variable(.phoneInput), .string("+94 (77) 123-4567"), nil),
            (variable(.phoneInput), .string("12ab"), .invalid),
            (variable(.dateInput), .string("2026-11-10"), nil),
            (variable(.dateInput), .string("10/11/2026"), .invalid),
            (variable(.connectionSelect), .string("c-1"), nil),
            (variable(.connectionSelect), .number(1), .invalid)
        ]
        for (definition, value, code) in cases {
            XCTAssertEqual(
                validateFlowVariableValue(definition, value)?.code,
                code,
                "\(definition.type.rawValue) \(String(describing: value))"
            )
        }
    }

    func testTextRulesCarryTheirOwnMessage() {
        let name = variable(
            .textInput,
            validation: [
                FlowVariableValidationRule(type: "minLength", value: .number(2), message: "Too short"),
                FlowVariableValidationRule(type: "maxLength", value: .string("4")),
                FlowVariableValidationRule(type: "regex", value: .string("^[a-z]+$"), message: "Lowercase")
            ]
        )
        XCTAssertEqual(validateFlowVariableValue(name, .string("a")), FlowVariableValidationError(code: .minLength, message: "Too short"))
        XCTAssertEqual(validateFlowVariableValue(name, .string("abcde")), FlowVariableValidationError(code: .maxLength))
        XCTAssertEqual(validateFlowVariableValue(name, .string("AB")), FlowVariableValidationError(code: .pattern, message: "Lowercase"))
        XCTAssertNil(validateFlowVariableValue(name, .string("abc")))
        let broken = variable(.textInput, validation: [FlowVariableValidationRule(type: "regex", value: .string("("))])
        XCTAssertNil(validateFlowVariableValue(broken, .string("anything")))
    }
}
