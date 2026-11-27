// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class TelemetryEncoderTests: XCTestCase {
    private let event = TelemetryEvent(
        name: "acme.application.create",
        id: "e1",
        kind: .api,
        timestamp: "2026-01-02T03:04:05.000Z",
        route: "/applications",
        identity: TelemetryIdentity(userId: "not-a-uuid", organizationId: "B3A1C2D4-0000-4000-8000-000000000001"),
        system: TelemetryOS(name: "iOS", version: "18.0.0"),
        data: ["resource_type": "application"],
        context: ["platform": "Acme"]
    )

    private func json(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }

    func testEncodesOpenTelemetryLogRecords() throws {
        let bodies = TelemetryEncoder(format: .otlp).encode([event])
        XCTAssertEqual(bodies.count, 1)
        let parsed = try XCTUnwrap(try json(bodies[0]) as? [String: Any])
        let resourceLogs = try XCTUnwrap(parsed["resourceLogs"] as? [[String: Any]])
        let scopeLogs = try XCTUnwrap(resourceLogs[0]["scopeLogs"] as? [[String: Any]])
        let record = try XCTUnwrap((scopeLogs[0]["logRecords"] as? [[String: Any]])?.first)
        XCTAssertEqual(record["eventName"] as? String, "acme.application.create")
        XCTAssertEqual(record["timeUnixNano"] as? String, "1767323045000000000")
        let attributes = Self.attributes(record["attributes"])
        XCTAssertEqual(attributes["event.data.resource_type"], "application")
        XCTAssertEqual(attributes["url.template"], "/applications")
        XCTAssertEqual(attributes["event.name"], "acme.application.create")
        XCTAssertEqual(attributes["event.id"], "e1")
        XCTAssertEqual(attributes["event.kind"], "api")
        XCTAssertEqual(attributes["user.id"], "not-a-uuid")
        XCTAssertEqual(attributes["organization.id"], "B3A1C2D4-0000-4000-8000-000000000001")
        XCTAssertEqual(attributes["os.name"], "iOS")
        XCTAssertEqual(attributes["os.version"], "18.0.0")
        let resource = Self.attributes((resourceLogs[0]["resource"] as? [String: Any])?["attributes"])
        XCTAssertEqual(resource, ["platform": "Acme", "service.name": "unknown_service"])
    }

    func testLetsTheContextNameTheService() throws {
        var named = event
        named.context = ["service.name": "console"]
        let parsed = try XCTUnwrap(try json(TelemetryEncoder(format: .otlp).encode([named])[0]) as? [String: Any])
        let resource = (parsed["resourceLogs"] as? [[String: Any]])?.first?["resource"] as? [String: Any]
        XCTAssertEqual(Self.attributes(resource?["attributes"]), ["service.name": "console"])
    }

    func testSendsTheEventsAsTheyAreForJson() throws {
        let parsed = try XCTUnwrap(try json(TelemetryEncoder(format: .json).encode([event])[0]) as? [[String: Any]])
        XCTAssertEqual(parsed.first?["name"] as? String, "acme.application.create")
        let attributes = try XCTUnwrap(parsed.first?["attributes"] as? [String: Any])
        XCTAssertEqual(attributes["route"] as? String, "/applications")
        XCTAssertEqual((attributes["os"] as? [String: String])?["name"], "iOS")
        XCTAssertEqual(attributes["data"] as? [String: String], ["resource_type": "application"])
    }

    func testReshapesEventsWithAMappingItsFiltersAndSpreads() throws {
        let encoder = TelemetryEncoder(format: .mapping, mapping: TelemetryMapping(
            template: [
                "action_name": "{{name}}",
                "company_id": "{{attributes.organization.id | uuid}}",
                "metadata": [
                    "...": "{{attributes.data}}",
                    "...context": "{{context}}",
                    "...feature": "{{name | lookup: features}}",
                    "missing": "x-{{attributes.nothing}}"
                ],
                "request": ["time": "{{timestamp}}", "when": "{{timestamp | date}}", "label": "at {{timestamp}}"],
                "user_id": "{{attributes.user.id | uuid}}",
                "fixed": 3
            ],
            tables: ["features": ["acme.application.create": ["category": "application", "tier": "core"]]]
        ))
        let parsed = try XCTUnwrap(try json(encoder.encode([event])[0]) as? [[String: Any]])
        XCTAssertEqual(parsed.count, 1)
        let mapped = parsed[0]
        XCTAssertEqual(mapped["action_name"] as? String, "acme.application.create")
        XCTAssertEqual(mapped["company_id"] as? String, "b3a1c2d4-0000-4000-8000-000000000001")
        XCTAssertNil(mapped["user_id"])
        XCTAssertEqual(mapped["fixed"] as? Int, 3)
        XCTAssertEqual(mapped["metadata"] as? [String: String], [
            "category": "application",
            "platform": "Acme",
            "resource_type": "application",
            "tier": "core"
        ])
        let request = try XCTUnwrap(mapped["request"] as? [String: Any])
        XCTAssertEqual(request["time"] as? String, "2026-01-02T03:04:05.000Z")
        XCTAssertEqual(request["when"] as? Int64, 1_767_323_045_000)
        XCTAssertEqual(request["label"] as? String, "at 2026-01-02T03:04:05.000Z")
    }

    func testSendsEachEventOnItsOwnWhenTheMappingAsksAndNothingForNoEvents() {
        let encoder = TelemetryEncoder(
            format: .mapping,
            mapping: TelemetryMapping(template: ["n": "{{name}}"], batch: .each)
        )
        XCTAssertEqual(encoder.encode([event, event]).map { String(data: $0, encoding: .utf8) }, [
            #"{"n":"acme.application.create"}"#,
            #"{"n":"acme.application.create"}"#
        ])
        XCTAssertTrue(encoder.encode([]).isEmpty)
    }

    private static func attributes(_ value: Any?) -> [String: String] {
        var result: [String: String] = [:]
        for item in value as? [[String: Any]] ?? [] {
            if let key = item["key"] as? String, let text = (item["value"] as? [String: String])?["stringValue"] {
                result[key] = text
            }
        }
        return result
    }
}
