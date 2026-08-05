// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

final class LogoIconCatalogTests: XCTestCase {

    func testAllAnonymousAnimalNamesResolveToABundledIcon() {
        for name in anonymousAnimalNames.sorted() {
            let image = LogoIconCatalog.anonymousAnimalImage(named: name)
            XCTAssertNotNil(image, "Missing bundled anonymous animal icon for \(name)")
        }
    }

    func testUnknownAnonymousAnimalNameResolvesToNil() {
        XCTAssertNil(LogoIconCatalog.anonymousAnimalImage(named: "dragon"))
    }

    func testAnonymousAnimalLookupIsCaseInsensitive() {
        XCTAssertNotNil(LogoIconCatalog.anonymousAnimalImage(named: "Jackalope"))
        XCTAssertNotNil(LogoIconCatalog.anonymousAnimalImage(named: "OTTER"))
    }

    func testAllAnonymousEntityNamesResolveToABundledIcon() {
        for name in anonymousEntityNames.sorted() {
            let image = LogoIconCatalog.anonymousEntityImage(named: name)
            XCTAssertNotNil(image, "Missing bundled anonymous entity icon for \(name)")
        }
    }

    func testUnknownAnonymousEntityNameResolvesToNil() {
        XCTAssertNil(LogoIconCatalog.anonymousEntityImage(named: "dragon"))
    }

    func testAnonymousEntityLookupIsCaseInsensitive() {
        XCTAssertNotNil(LogoIconCatalog.anonymousEntityImage(named: "Hexagon"))
        XCTAssertNotNil(LogoIconCatalog.anonymousEntityImage(named: "STAR"))
    }
}
