// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class UserSelectPagingTests: XCTestCase {
    func testComputeNextPageOffsetAdvancesByCount() {
        XCTAssertEqual(computeNextPageOffset(0, count: 30, totalResults: 75), 30)
        XCTAssertEqual(computeNextPageOffset(30, count: 30, totalResults: 75), 60)
    }

    func testComputeNextPageOffsetStopsAtTotal() {
        XCTAssertNil(computeNextPageOffset(60, count: 15, totalResults: 75))
    }

    func testComputeNextPageOffsetStopsOnEmptyPage() {
        XCTAssertNil(computeNextPageOffset(0, count: 0, totalResults: 0))
    }

    func testComputeNextPageOffsetWithoutTotalResultsStillAdvances() {
        XCTAssertEqual(computeNextPageOffset(0, count: 30, totalResults: nil), 30)
    }

    func testIsAdvancingPageOffsetAcceptsAGreaterOffset() {
        XCTAssertTrue(isAdvancingPageOffset(0, 30))
    }

    func testIsAdvancingPageOffsetRejectsNil() {
        XCTAssertFalse(isAdvancingPageOffset(0, nil))
    }

    func testIsAdvancingPageOffsetRejectsNonAdvancingValues() {
        XCTAssertFalse(isAdvancingPageOffset(30, 30))
        XCTAssertFalse(isAdvancingPageOffset(30, 10))
    }

    func testDedupeKeepsFirstPositionAndNewestData() {
        let existing = [PagedSelectOption(label: "Old", value: "1")]
        let incoming = [PagedSelectOption(label: "New", value: "1"), PagedSelectOption(label: "Two", value: "2")]

        let result = dedupePagedSelectOptions(existing, incoming)

        XCTAssertEqual(result.map(\.value), ["1", "2"])
        XCTAssertEqual(result.first?.label, "New")
    }
}

final class PagedSelectMappingTests: XCTestCase {
    private struct Product {
        let sku: String
        let title: String?
    }

    private let mapping = PagedSelectOptionMapping<Product>(label: { $0.title }, value: { $0.sku })

    func testUsesTheMappedLabelAndValue() {
        let option = toPagedSelectOption(Product(sku: "p-1", title: "Widget"), mapping: mapping)

        XCTAssertEqual(option, PagedSelectOption(label: "Widget", value: "p-1"))
    }

    func testFallsBackToTheValueWhenThereIsNoLabel() {
        let option = toPagedSelectOption(Product(sku: "p-1", title: nil), mapping: mapping)

        XCTAssertEqual(option?.label, "p-1")
    }

    func testDropsAnItemWithoutAValue() {
        let noValue = PagedSelectOptionMapping<Product>(label: { $0.title }, value: { _ in nil })

        XCTAssertNil(toPagedSelectOption(Product(sku: "p-1", title: "Widget"), mapping: noValue))
    }

    func testConvertsAPageAndSkipsItemsWithoutAValue() {
        let selective = PagedSelectOptionMapping<Product>(
            label: { $0.title },
            value: { $0.sku.isEmpty ? nil : $0.sku }
        )
        let items = [Product(sku: "p-1", title: "A"), Product(sku: "", title: "B"), Product(sku: "p-3", title: "C")]

        XCTAssertEqual(toPagedSelectOptions(items, mapping: selective).map(\.value), ["p-1", "p-3"])
    }
}

final class UserSelectMappingTests: XCTestCase {
    // `ManagedUser` is `Decodable`-only (no public memberwise initializer, matching how
    // `ManagementAPITests` builds every management model), so tests decode it from JSON too.
    private func user(
        id: String = "u-1",
        display: String? = nil,
        username: String? = nil,
        email: String? = nil
    ) -> ManagedUser {
        var json: [String: Any] = ["id": id, "ouId": "ou", "type": "person"]
        if let display { json["display"] = display }
        var attributes: [String: String] = [:]
        if let username { attributes["username"] = username }
        if let email { attributes["email"] = email }
        if !attributes.isEmpty { json["attributes"] = attributes }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(ManagedUser.self, from: data)
    }

    private func usersResponse(
        totalResults: Int, startIndex: Int, count: Int, users: [ManagedUser]
    ) -> ManagedUserListResponse {
        let usersData = users.map { user -> [String: Any] in
            var json: [String: Any] = ["id": user.id, "ouId": user.ouId, "type": user.type]
            if let display = user.display { json["display"] = display }
            return json
        }
        let json: [String: Any] = [
            "totalResults": totalResults, "startIndex": startIndex, "count": count, "users": usersData,
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(ManagedUserListResponse.self, from: data)
    }

    func testPrefersDisplay() {
        let option = toUserSelectOption(user(display: "Ada Lovelace", username: "ada"))
        XCTAssertEqual(option, PagedSelectOption(label: "Ada Lovelace", value: "u-1"))
    }

    func testFallsBackToUsernameWhenDisplayEqualsId() {
        // The backend returns the ID as display when the user type has no display attribute.
        let option = toUserSelectOption(user(id: "u-1", display: "u-1", username: "ada"))
        XCTAssertEqual(option?.label, "ada")
    }

    func testFallsBackToEmailWhenNoUsername() {
        let option = toUserSelectOption(user(email: "ada@example.com"))
        XCTAssertEqual(option?.label, "ada@example.com")
    }

    func testFallsBackToIdWhenNothingElseIsSet() {
        let option = toUserSelectOption(user())
        XCTAssertEqual(option?.label, "u-1")
    }

    func testAlwaysSubmitsTheId() {
        let option = toUserSelectOption(user(id: "u-42", display: "Grace Hopper"))
        XCTAssertEqual(option?.value, "u-42")
    }

    func testMappingOverridesLabelAndValue() {
        let mapping = UserSelectOptionMapping(
            label: { $0.attributes?["email"]?.value as? String },
            value: { $0.attributes?["email"]?.value as? String }
        )
        let option = toUserSelectOption(user(display: "Ada Lovelace", email: "ada@example.com"), mapping: mapping)
        XCTAssertEqual(option, PagedSelectOption(label: "ada@example.com", value: "ada@example.com"))
    }

    func testMappingDropsAUserWithNoValue() {
        let mapping = UserSelectOptionMapping(label: { _ in nil }, value: { $0.attributes?["email"]?.value as? String })
        XCTAssertNil(toUserSelectOption(user(), mapping: mapping))
    }

    func testToUserSelectPageComputesNextOffsetFromCount() {
        let response = usersResponse(
            totalResults: 75, startIndex: 1, count: 30, users: [user(id: "u-1", display: "Ada")]
        )

        let page = toUserSelectPage(response, requestOffset: 0)

        XCTAssertEqual(page.nextOffset, 30)
        XCTAssertEqual(page.options?.first?.label, "Ada")
    }

    func testToUserSelectPageStopsAtTheLastPage() {
        let response = usersResponse(totalResults: 75, startIndex: 61, count: 15, users: [])

        let page = toUserSelectPage(response, requestOffset: 60)

        XCTAssertNil(page.nextOffset)
    }
}

final class ManagedSelectMappingTests: XCTestCase {
    private func flow(id: String, name: String, handle: String = "login") throws -> ManagedFlow {
        let json = #"{"id":"\#(id)","handle":"\#(handle)","name":"\#(name)","flowType":"AUTHENTICATION"}"#
        return try JSONDecoder().decode(ManagedFlow.self, from: Data(json.utf8))
    }

    private func userType(id: String, handle: String, displayName: String? = "Staff") throws -> ManagedUserType {
        var json = #"{"id":"\#(id)","handle":"\#(handle)""#
        if let displayName { json += #","displayName":"\#(displayName)""# }
        json += "}"
        return try JSONDecoder().decode(ManagedUserType.self, from: Data(json.utf8))
    }

    private func flowsResponse(_ flows: [ManagedFlow], startIndex: Int, totalResults: Int) -> ManagedFlowListResponse {
        ManagedFlowListResponse(totalResults: totalResults, startIndex: startIndex, count: flows.count, flows: flows, links: nil)
    }

    private func typesResponse(
        _ types: [ManagedUserType], startIndex: Int, totalResults: Int
    ) -> ManagedUserTypeListResponse {
        ManagedUserTypeListResponse(totalResults: totalResults, startIndex: startIndex, count: types.count, types: types, links: nil)
    }

    func testAFlowIsShownByNameAndSubmitsItsId() throws {
        let option = toAuthFlowSelectOption(try flow(id: "flow-1", name: "Password login"))

        XCTAssertEqual(option, PagedSelectOption(label: "Password login", value: "flow-1"))
    }

    func testAFlowWithAnEmptyNameFallsBackToItsHandleThenItsId() throws {
        XCTAssertEqual(toAuthFlowSelectOption(try flow(id: "flow-1", name: "", handle: "sso")).label, "sso")
        XCTAssertEqual(toAuthFlowSelectOption(try flow(id: "flow-2", name: " ", handle: "")).label, "flow-2")
    }

    func testAUserTypeIsShownAndSubmittedByItsHandleNeverItsDisplayName() throws {
        let option = toUserTypeSelectOption(try userType(id: "type-1", handle: "employee"))

        XCTAssertEqual(option, PagedSelectOption(label: "employee", value: "employee"))
    }

    func testAUserTypeWithoutAHandleIsDropped() throws {
        XCTAssertNil(toUserTypeSelectOption(try userType(id: "type-1", handle: "")))
    }

    func testTheFlowPageAdvancesByTheBackendCountAndEndsOnTheLastPage() throws {
        let page = toAuthFlowSelectPage(
            flowsResponse([try flow(id: "f1", name: "A"), try flow(id: "f2", name: "B")], startIndex: 31, totalResults: 75),
            requestOffset: 30
        )
        let last = toAuthFlowSelectPage(
            flowsResponse([try flow(id: "f75", name: "Z")], startIndex: 75, totalResults: 75),
            requestOffset: 74
        )

        XCTAssertEqual(page.nextOffset, 32)
        XCTAssertEqual(page.options?.map(\.value), ["f1", "f2"])
        XCTAssertNil(last.nextOffset)
    }

    func testTheUserTypePageStillAdvancesWhenATypeIsDropped() throws {
        let page = toUserTypeSelectPage(
            typesResponse(
                [try userType(id: "t1", handle: ""), try userType(id: "t2", handle: "employee")],
                startIndex: 1,
                totalResults: 10
            ),
            requestOffset: 0
        )

        XCTAssertEqual(page.options?.map(\.value), ["employee"])
        XCTAssertEqual(page.nextOffset, 2)
    }

    func testThePageSizeCapMatchesTheBackendMaximum() {
        XCTAssertEqual(PagedSelectLimits.maxPageSize, 100)
        XCTAssertEqual(min(500, PagedSelectLimits.maxPageSize), 100)
    }
}

final class PagedSelectErrorMappingTests: XCTestCase {
    func testTrustsAThunderIDErrorMessage() {
        let failure = mapPagedSelectError(ThunderIDError(code: .serverError, message: "Upstream exploded"))
        XCTAssertEqual(failure.message, "Upstream exploded")
    }

    func testDoesNotTrustAPlainError() {
        struct PlainError: Error {}
        let failure = mapPagedSelectError(PlainError())
        XCTAssertNil(failure.message)
    }
}
