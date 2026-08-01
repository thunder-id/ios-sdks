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
