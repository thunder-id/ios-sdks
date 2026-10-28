// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class AgentNameTests: XCTestCase {
    func testDisplayComesFirst() {
        XCTAssertEqual(
            resolveAgentName(id: "ag-1", display: "Triage", attributes: ["name": AnyCodable("triage-bot")]),
            "Triage"
        )
    }

    func testFallsBackToTheNameAttribute() {
        XCTAssertEqual(resolveAgentName(id: "ag-1", attributes: ["name": AnyCodable("Triage")]), "Triage")
        XCTAssertEqual(
            resolveAgentName(id: "ag-1", display: "", attributes: ["name": AnyCodable("Triage")]),
            "Triage"
        )
    }

    func testFallsBackToTheIdentifier() {
        XCTAssertEqual(resolveAgentName(id: "ag-1"), "ag-1")
        XCTAssertEqual(resolveAgentName(id: "ag-1", attributes: ["name": AnyCodable("")]), "ag-1")
        XCTAssertEqual(resolveAgentName(id: "ag-1", attributes: ["name": AnyCodable(42)]), "ag-1")
        XCTAssertEqual(resolveAgentName(id: "ag-1", attributes: ["model": AnyCodable("v2")]), "ag-1")
    }

    func testModelsResolveTheirName() throws {
        let agent = try JSONDecoder().decode(
            Agent.self,
            from: Data(#"{"id":"ag-1","ouId":"ou","type":"bot","attributes":{"name":"Triage"}}"#.utf8)
        )
        let summary = try JSONDecoder().decode(
            BasicAgent.self,
            from: Data(#"{"id":"ag-2","ouId":"ou","type":"bot","display":"Billing"}"#.utf8)
        )

        XCTAssertEqual(agent.resolvedName, "Triage")
        XCTAssertNil(agent.display)
        XCTAssertEqual(summary.resolvedName, "Billing")
    }
}
