// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ThunderID

/// The account-linking prompt as the server sends it: a KEY_VALUE_LIST bound to `linkingPromptDetails`, whose
/// pairs arrive JSON-encoded under that key in `additionalData`.
private let linkingPromptFixture = """
{
    "executionId": "019f52b4-4a25-79fd-b2a1-885b9a44dbe3",
    "flowStatus": "INCOMPLETE",
    "type": "VIEW",
    "data": {
        "actions": [
            {"ref": "action_confirm", "nextNode": "credentials_auth"},
            {"ref": "action_reject", "nextNode": "linking"}
        ],
        "additionalData": {
            "linkingPromptDetails": "[{\\"label\\":\\"Email\\",\\"value\\":\\"alice@example.com\\"}]"
        },
        "meta": {
            "components": [
                {"category": "DISPLAY", "id": "kv_001", "type": "KEY_VALUE_LIST", "source": "linkingPromptDetails"}
            ]
        }
    }
}
"""

final class KeyValuePairTests: XCTestCase {
    func testReadsPairsFromTheSourceKeyOfADecodedResponse() throws {
        let data = linkingPromptFixture.data(using: .utf8)!
        let response = try JSONDecoder().decode(EmbeddedFlowResponse.self, from: data)
        let component = try XCTUnwrap(response.data?.meta?.components?.first)

        XCTAssertEqual(component.source, "linkingPromptDetails")
        let raw = component.source.flatMap { response.data?.additionalData?[$0]?.value }
        XCTAssertEqual(KeyValuePair.list(from: raw), [KeyValuePair(label: "Email", value: "alice@example.com")])
    }

    func testParsesAJSONEncodedListInOrder() {
        let raw = #"[{"label":"Email","value":"alice@example.com"},{"label":"Username","value":"alice"}]"#
        XCTAssertEqual(KeyValuePair.list(from: raw), [
            KeyValuePair(label: "Email", value: "alice@example.com"),
            KeyValuePair(label: "Username", value: "alice")
        ])
    }

    func testAcceptsAnAlreadyDecodedList() {
        let raw: [Any] = [["label": "Email", "value": "alice@example.com"]]
        XCTAssertEqual(KeyValuePair.list(from: raw), [KeyValuePair(label: "Email", value: "alice@example.com")])
    }

    func testDropsEntriesThatAreNotObjectsOrCarryNoValue() {
        let raw = #"[{"label":"Email","value":"alice@example.com"},{"label":"Empty","value":""},"#
            + #"{"label":"Missing"},{"label":"Number","value":42},"row",null,["Email","a"]]"#
        XCTAssertEqual(KeyValuePair.list(from: raw), [KeyValuePair(label: "Email", value: "alice@example.com")])
    }

    func testDefaultsAMissingLabelToEmpty() {
        XCTAssertEqual(
            KeyValuePair.list(from: #"[{"value":"alice@example.com"}]"#),
            [KeyValuePair(label: "", value: "alice@example.com")]
        )
    }

    func testReturnsNoPairsForAnythingThatIsNotAList() {
        XCTAssertEqual(KeyValuePair.list(from: nil), [])
        XCTAssertEqual(KeyValuePair.list(from: ""), [])
        XCTAssertEqual(KeyValuePair.list(from: "not json"), [])
        XCTAssertEqual(KeyValuePair.list(from: #"{"label":"Email","value":"alice@example.com"}"#), [])
    }
}
