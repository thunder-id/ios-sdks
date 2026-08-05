// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ThunderIDSwiftUI

final class RichTextLinksTests: XCTestCase {

    func testSentinelAnchorResolvesActionRefInsteadOfHref() {
        let html = """
        <p data-component-ref="self-sign-up-link"><span class="rich-text-pre-wrap">Don't have an \
        account? </span><a href="#" data-action-ref="action_signup" class="rich-text-link">\
        <span class="rich-text-pre-wrap">Sign up</span></a></p>
        """

        let segments = RichTextLinks.segments(from: html)
        let linkSegment = segments.first { $0.isLink }

        XCTAssertNotNil(linkSegment)
        XCTAssertEqual(linkSegment?.text, "Sign up")
        XCTAssertEqual(linkSegment?.actionRef, "action_signup")
    }

    func testAnchorWithoutActionRefResolvesHref() {
        let html = """
        <p><span>Forgot password? </span><a href="https://example.com/reset">Reset</a></p>
        """

        let segments = RichTextLinks.segments(from: html)
        let linkSegment = segments.first { $0.isLink }

        XCTAssertNotNil(linkSegment)
        XCTAssertNil(linkSegment?.actionRef)
        XCTAssertEqual(linkSegment?.url, URL(string: "https://example.com/reset"))
    }

    func testPlainTextPrecedesLinkSegmentInOutputOrder() {
        let html = """
        <p><span>Don't have an account? </span><a href="#" data-action-ref="action_signup">Sign up</a></p>
        """

        let segments = RichTextLinks.segments(from: html)

        XCTAssertEqual(segments.count, 2)
        XCTAssertFalse(segments[0].isLink)
        XCTAssertEqual(segments[0].text, "Don't have an account?")
        XCTAssertTrue(segments[1].isLink)
        XCTAssertEqual(segments[1].text, "Sign up")
    }
}
