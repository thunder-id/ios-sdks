// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class TelemetryNamesTests: XCTestCase {
    func testNamesAPageFromItsRoutePattern() {
        XCTAssertEqual(TelemetryNames.pageName("/organizations/:org/applications"), "application.list-view")
        XCTAssertEqual(TelemetryNames.pageName("/applications/:id"), "application.detail-view")
        XCTAssertEqual(TelemetryNames.pageName("applications/:id"), "application.detail-view")
        XCTAssertEqual(TelemetryNames.pageName("/applications/{id}"), "application.detail-view")
        XCTAssertEqual(TelemetryNames.pageName("/applications/create"), "application.create-view")
        XCTAssertEqual(TelemetryNames.pageName("/applications/:id/settings"), "setting.list-view")
        XCTAssertEqual(TelemetryNames.pageName("/applications/:id/status"), "application.status-view")
        XCTAssertEqual(TelemetryNames.pageName("/organizations/:org/home"), "organization.home-view")
        XCTAssertEqual(TelemetryNames.pageName("/organization-units/:id"), "organization-unit.detail-view")
        XCTAssertEqual(TelemetryNames.pageName("/policies"), "policy.list-view")
        XCTAssertEqual(TelemetryNames.pageName("/"), "app.home-view")
        XCTAssertEqual(TelemetryNames.pageName("/home"), "app.home-view")
    }

    func testReadsPluralsByEnglishSpellingWithNoListOfWords() {
        XCTAssertEqual(TelemetryNames.singular("applications"), "application")
        XCTAssertEqual(TelemetryNames.singular("policies"), "policy")
        XCTAssertEqual(TelemetryNames.singular("addresses"), "address")
        XCTAssertEqual(TelemetryNames.singular("boxes"), "box")
        XCTAssertFalse(TelemetryNames.isCollection("access"))
        XCTAssertFalse(TelemetryNames.isCollection("status"))
        XCTAssertTrue(TelemetryNames.isCollection("settings"))
    }

    func testMatchesTheWholeStringOnly() {
        XCTAssertTrue(TelemetryNames.isEventName("item.open"))
        XCTAssertFalse(TelemetryNames.isEventName("item.open\n"))
        XCTAssertFalse(TelemetryNames.matches("role.delete\n", "role.delete"))
        XCTAssertEqual(TelemetryNames.templatedPath("/guides\n/start"), "/{id}/{id}")
    }

    func testAddsThePrefixToAFullNameOnlyWhenOneIsSet() {
        XCTAssertEqual(TelemetryNames(prefix: "acme").full("application.create"), "acme.application.create")
        XCTAssertEqual(TelemetryNames().full("application.create"), "application.create")
        XCTAssertEqual(TelemetryNames(prefix: "").full("application.create"), "application.create")
    }

    func testMatchesOneSegmentWithAStarAndTheRestWithTwo() {
        XCTAssertTrue(TelemetryNames.matches("/settings/general", "/settings/*"))
        XCTAssertFalse(TelemetryNames.matches("/settings/general/advanced", "/settings/*"))
        XCTAssertTrue(TelemetryNames.matches("/settings/general/advanced", "/settings/**"))
        XCTAssertTrue(TelemetryNames.matches("https://abc.com/x.y", "https://abc.com/*"))
        XCTAssertFalse(TelemetryNames.matches("https://abcXcom/x", "https://abc.com/*"))
        XCTAssertTrue(TelemetryNames.matches("role.delete", "role.*"))
        XCTAssertFalse(TelemetryNames.matches("group.delete", "role.*"))
    }
}
