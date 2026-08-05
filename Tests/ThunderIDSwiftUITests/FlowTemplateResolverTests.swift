// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

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
