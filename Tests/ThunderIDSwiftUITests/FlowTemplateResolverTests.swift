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
@testable import ThunderIDSwiftUI

final class FlowTemplateResolverTests: XCTestCase {
    func testResolvesTranslationTemplate() {
        let meta: [String: Any] = [
            "i18n": [
                "translations": [
                    "signin": [
                        "forms.credentials.fields.username.label": "Username"
                    ]
                ]
            ]
        ]
        let resolver = FlowTemplateResolver(meta: meta)
        XCTAssertEqual(
            resolver.resolve("{{ t(signin:forms.credentials.fields.username.label) }}"),
            "Username"
        )
    }

    func testResolvesMetaDotPathTemplate() {
        let meta: [String: Any] = [
            "application": [
                "forgot_password_url": "https://example.com/reset"
            ]
        ]
        let resolver = FlowTemplateResolver(meta: meta)
        XCTAssertEqual(
            resolver.resolve("{{meta(application.forgot_password_url)}}"),
            "https://example.com/reset"
        )
    }

    func testLeavesUnrecognisedExpressionUnchanged() {
        let resolver = FlowTemplateResolver(meta: [:])
        XCTAssertEqual(resolver.resolve("{{ unknown(foo) }}"), "{{ unknown(foo) }}")
    }

    func testReturnsPlainTextUnchangedWhenNoTemplate() {
        let resolver = FlowTemplateResolver(meta: [:])
        XCTAssertEqual(resolver.resolve("Plain text"), "Plain text")
    }

    func testResolvesMultipleTemplatesInOneString() {
        let meta: [String: Any] = [
            "i18n": [
                "translations": [
                    "signin": [
                        "forms.credentials.links.forgot_password.prefix": "Forgot",
                        "forms.credentials.links.forgot_password.label": "password?"
                    ]
                ]
            ]
        ]
        let resolver = FlowTemplateResolver(meta: meta)
        let text = "{{ t(signin:forms.credentials.links.forgot_password.prefix) }} " +
            "{{ t(signin:forms.credentials.links.forgot_password.label) }}"
        XCTAssertEqual(resolver.resolve(text), "Forgot password?")
    }

    func testReturnsEmptyStringForMissingTranslationKey() {
        let resolver = FlowTemplateResolver(meta: [:])
        XCTAssertEqual(resolver.resolve("{{ t(signin:missing.key) }}"), "")
    }
}
