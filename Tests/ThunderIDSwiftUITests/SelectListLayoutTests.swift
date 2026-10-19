// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

final class SelectListLayoutTests: XCTestCase {
    func testTheFirstLoadShowsLoadingAndNoLoadMoreRow() {
        let layout = SelectListLayout(optionCount: 0, loading: true, canLoadMore: true)

        XCTAssertEqual(layout.status, .loading)
        XCTAssertFalse(layout.showsLoadMore)
    }

    func testLoadingMoreKeepsTheLoadMoreRowSoItCanShowProgress() {
        let layout = SelectListLayout(optionCount: 30, loading: true, canLoadMore: true)

        XCTAssertEqual(layout.status, .none)
        XCTAssertTrue(layout.showsLoadMore)
    }

    func testOptionsWithMoreToLoadShowTheLoadMoreRow() {
        let layout = SelectListLayout(optionCount: 30, loading: false, canLoadMore: true)

        XCTAssertEqual(layout.status, .none)
        XCTAssertTrue(layout.showsLoadMore)
    }

    func testAFailedFirstLoadLeavesOnlyTheLoadMoreRowToTryAgain() {
        let layout = SelectListLayout(optionCount: 0, loading: false, canLoadMore: true)

        XCTAssertEqual(layout.status, .none)
        XCTAssertTrue(layout.showsLoadMore)
    }

    func testNoOptionsAndNothingMoreToLoadShowsTheEmptyText() {
        let layout = SelectListLayout(optionCount: 0, loading: false, canLoadMore: false)

        XCTAssertEqual(layout.status, .empty)
        XCTAssertFalse(layout.showsLoadMore)
    }

    func testTheLastPageHasNoLoadMoreRow() {
        let layout = SelectListLayout(optionCount: 75, loading: false, canLoadMore: false)

        XCTAssertEqual(layout.status, .none)
        XCTAssertFalse(layout.showsLoadMore)
    }

    func testAnEmptyListThatCannotLoadMoreAndIsStillLoadingShowsLoading() {
        let layout = SelectListLayout(optionCount: 0, loading: true, canLoadMore: false)

        XCTAssertEqual(layout.status, .loading)
    }
}

final class ResolveSelectOptionTests: XCTestCase {
    private let loaded = [SelectOption(label: "Ada", value: "u-1")]
    private let picked = SelectOption(label: "Grace", value: "u-2")
    private let saved = SelectOption(label: "Linus", value: "u-3")

    func testALoadedOptionLabelsItsValue() {
        let option = resolveSelectOption(for: "u-1", in: loaded, picked: picked, selectedOption: saved)

        XCTAssertEqual(option?.label, "Ada")
    }

    func testTheOptionLastPickedLabelsAValueThatIsNotLoaded() {
        let option = resolveSelectOption(for: "u-2", in: loaded, picked: picked, selectedOption: saved)

        XCTAssertEqual(option?.label, "Grace")
    }

    func testTheSelectedOptionLabelsAValueThatIsNeitherLoadedNorPicked() {
        let option = resolveSelectOption(for: "u-3", in: loaded, picked: picked, selectedOption: saved)

        XCTAssertEqual(option?.label, "Linus")
    }

    func testAnOptionOnlyLabelsItsOwnValue() {
        XCTAssertNil(resolveSelectOption(for: "u-9", in: loaded, picked: picked, selectedOption: saved))
    }

    func testAnEmptyValueHasNoOption() {
        XCTAssertNil(resolveSelectOption(for: "", in: loaded, picked: picked, selectedOption: saved))
    }
}
