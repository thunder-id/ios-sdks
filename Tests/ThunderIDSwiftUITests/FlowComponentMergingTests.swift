// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ThunderIDSwiftUI

final class FlowComponentMergingTests: XCTestCase {
    func testSecondaryAndOutlinedVariantsRenderOutlined() {
        XCTAssertTrue(FlowComponentMerging.isOutlinedVariant("SECONDARY"))
        XCTAssertTrue(FlowComponentMerging.isOutlinedVariant("secondary"))
        XCTAssertTrue(FlowComponentMerging.isOutlinedVariant("OUTLINED"))
    }

    func testPrimaryAndMissingVariantsKeepTheFilledLook() {
        XCTAssertFalse(FlowComponentMerging.isOutlinedVariant("PRIMARY"))
        XCTAssertFalse(FlowComponentMerging.isOutlinedVariant(nil))
        XCTAssertFalse(FlowComponentMerging.isOutlinedVariant(""))
    }
}
