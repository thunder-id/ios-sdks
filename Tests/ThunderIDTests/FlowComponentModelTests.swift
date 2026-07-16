/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import XCTest
@testable import ThunderID

/// Exact payload from the Flow Execution API bug report: display metadata (labels, icons,
/// eventType) lives only in `data.meta.components`, not in the flat `data.actions`/`data.inputs`.
private let flowExecutionFixture = """
{
    "executionId": "019f52b4-4a25-79fd-b2a1-885b9a44dbe3",
    "flowStatus": "INCOMPLETE",
    "type": "VIEW",
    "challengeToken": "efb3706d1a8db1a291da65cd49e213af6e63fe6379006dfbd96d545d3a920119",
    "data": {
        "inputs": [
            {"ref": "input_001", "identifier": "username", "type": "TEXT_INPUT", "required": true},
            {"ref": "input_002", "identifier": "password", "type": "PASSWORD_INPUT", "required": true}
        ],
        "actions": [
            {"ref": "action_001", "nextNode": "credentials_auth"},
            {"ref": "action_xoc0", "nextNode": "ID_0e5o"},
            {"ref": "action_zeye", "nextNode": "ID_dbxc"}
        ],
        "meta": {
            "components": [
                {"align": "center", "category": "DISPLAY", "id": "text_001", "label": "Login", "resourceType": "ELEMENT", "type": "TEXT", "variant": "HEADING_1"},
                {"category": "BLOCK", "components": [
                    {"category": "FIELD", "hint": "", "id": "input_001", "inputType": "text", "label": "{{ t(signin:forms.credentials.fields.username.label) }}", "placeholder": "{{ t(signin:forms.credentials.fields.username.placeholder) }}", "ref": "username", "required": true, "resourceType": "ELEMENT", "type": "TEXT_INPUT"},
                    {"category": "FIELD", "hint": "", "id": "input_002", "inputType": "text", "label": "{{ t(signin:forms.credentials.fields.password.label) }}", "placeholder": "{{ t(signin:forms.credentials.fields.password.placeholder) }}", "ref": "password", "required": true, "resourceType": "ELEMENT", "type": "PASSWORD_INPUT"},
                    {"category": "DISPLAY", "id": "rich_text_forgot_password", "label": "<p class=\\"rich-text-paragraph\\"><span class=\\"rich-text-pre-wrap\\">{{ t(signin:forms.credentials.links.forgot_password.prefix) }} </span><a href=\\"{{meta(application.forgot_password_url)}}\\" target=\\"_blank\\" rel=\\"noopener noreferrer\\" class=\\"rich-text-link\\"><span class=\\"rich-text-pre-wrap\\">{{ t(signin:forms.credentials.links.forgot_password.label) }}</span></a></p>", "resourceType": "ELEMENT", "type": "RICH_TEXT"},
                    {"category": "ACTION", "eventType": "SUBMIT", "id": "action_001", "label": "{{ t(signin:forms.credentials.actions.submit.label) }}", "resourceType": "ELEMENT", "type": "ACTION", "variant": "PRIMARY"},
                    {"category": "DISPLAY", "id": "rich_text_signup", "label": "<p class=\\"rich-text-paragraph\\"><span class=\\"rich-text-pre-wrap\\">{{ t(signin:forms.credentials.links.sign_up.prefix) }} </span><a href=\\"{{meta(application.sign_up_url)}}\\" target=\\"_blank\\" rel=\\"noopener noreferrer\\" class=\\"rich-text-link\\"><span class=\\"rich-text-pre-wrap\\">{{ t(signin:forms.credentials.links.sign_up.label) }}</span></a></p>", "resourceType": "ELEMENT", "type": "RICH_TEXT"}
                ], "id": "block_001", "resourceType": "ELEMENT", "type": "BLOCK"},
                {"category": "DISPLAY", "id": "display_tfae", "label": "Or", "resourceType": "ELEMENT", "type": "DIVIDER", "variant": "HORIZONTAL"},
                {"category": "ACTION", "components": [
                    {"category": "ACTION", "eventType": "TRIGGER", "id": "action_xoc0", "image": "assets/images/icons/google.svg", "label": "Continue with Google", "resourceType": "ELEMENT", "type": "ACTION", "variant": "OUTLINED"}
                ], "eventType": "TRIGGER", "id": "block_per3", "resourceType": "ELEMENT", "type": "BLOCK"},
                {"category": "ACTION", "components": [
                    {"category": "ACTION", "eventType": "TRIGGER", "id": "action_zeye", "image": "assets/images/icons/github.svg", "label": "Continue with GitHub", "resourceType": "ELEMENT", "type": "ACTION", "variant": "OUTLINED"}
                ], "eventType": "TRIGGER", "id": "block_dzuu", "resourceType": "ELEMENT", "type": "BLOCK"}
            ]
        }
    }
}
"""

final class FlowComponentModelTests: XCTestCase {
    private func decodeFixture() throws -> EmbeddedFlowResponse {
        let data = flowExecutionFixture.data(using: .utf8)!
        return try JSONDecoder().decode(EmbeddedFlowResponse.self, from: data)
    }

    func testDecodesTopLevelMetaComponents() throws {
        let response = try decodeFixture()
        XCTAssertEqual(response.data?.meta?.components?.count, 5)
    }

    func testDecodesNestedActionComponentFields() throws {
        let response = try decodeFixture()
        let components = try XCTUnwrap(response.data?.meta?.components)
        let googleBlock = try XCTUnwrap(components.first { $0.id == "block_per3" })
        let googleAction = try XCTUnwrap(googleBlock.components?.first)
        XCTAssertEqual(googleAction.ref, nil)
        XCTAssertEqual(googleAction.id, "action_xoc0")
        XCTAssertEqual(googleAction.eventType, "TRIGGER")
        XCTAssertEqual(googleAction.label, "Continue with Google")
        XCTAssertEqual(googleAction.icon, "assets/images/icons/google.svg")
    }

    func testMergingFillsInMissingFlatActionFieldsFromComponent() throws {
        let response = try decodeFixture()
        let flatAction = try XCTUnwrap(response.data?.actions?.first { $0.ref == "action_xoc0" })
        XCTAssertNil(flatAction.label)
        XCTAssertNil(flatAction.eventType)

        let components = try XCTUnwrap(response.data?.meta?.components)
        let matchingComponent = try XCTUnwrap(
            flattenActionComponents(components).first { $0.id == flatAction.ref || $0.ref == flatAction.ref }
        )
        let enriched = flatAction.merging(component: matchingComponent)

        XCTAssertEqual(enriched.eventType, "TRIGGER")
        XCTAssertEqual(enriched.label, "Continue with Google")
        XCTAssertEqual(enriched.icon?.lowercased().contains("google"), true)
    }

    /// Mirrors `SignInState.flattenActionComponents` for test purposes: walks the component tree
    /// collecting every `ACTION`-typed node so it can be matched against a flat `FlowAction`.
    private func flattenActionComponents(_ components: [FlowComponent]) -> [FlowComponent] {
        var result: [FlowComponent] = []
        for component in components {
            if component.type == "ACTION" {
                result.append(component)
            }
            if let children = component.components {
                result.append(contentsOf: flattenActionComponents(children))
            }
        }
        return result
    }
}
