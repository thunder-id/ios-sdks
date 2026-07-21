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
