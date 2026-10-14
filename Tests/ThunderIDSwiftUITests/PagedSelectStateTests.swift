// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

@MainActor
final class PagedSelectStateTests: XCTestCase {
    private struct Item: Equatable {
        let id: String
    }

    private func page(_ start: Int, _ count: Int, _ total: Int) -> PagedSelectPage<Item> {
        PagedSelectPage(
            items: (0..<count).map { Item(id: "user-\(start + $0 + 1)") },
            nextOffset: start + count < total ? start + count : nil,
            totalResults: total
        )
    }

    private func toOptions(_ items: [Item]) -> [PagedSelectOption] {
        items.map { PagedSelectOption(label: $0.id, value: $0.id) }
    }

    private func makeState(
        pageSize: Int = 30,
        fetch: @escaping FetchPagedOptions<Item>
    ) -> PagedSelectState<Item> {
        PagedSelectState(pageSize: pageSize, fetch: fetch, convert: toOptions)
    }

    private func wait(until condition: @escaping () -> Bool, timeout: Int = 500) async {
        for _ in 0..<timeout where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "condition not met before timeout")
    }

    func testMakesNoRequestUntilLoadInitial() async {
        var calls = 0
        let state = makeState { _ in
            calls += 1
            return self.page(0, 0, 0)
        }

        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(calls, 0)
        XCTAssertFalse(state.hasLoaded)
    }

    func testLoadInitialRequestsPageZero() async {
        var requests: [PagedSelectRequest] = []
        let state = makeState { request in
            requests.append(request)
            return self.page(0, 30, 75)
        }

        state.loadInitial()
        await wait(until: { state.hasLoaded })

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.offset, 0)
        XCTAssertEqual(requests.first?.limit, 30)
        XCTAssertEqual(state.options.count, 30)
        XCTAssertTrue(state.hasMore)
    }

    func testLoadInitialTwiceOnlyFetchesOnce() async {
        var calls = 0
        let state = makeState { _ in
            calls += 1
            return self.page(0, 30, 30)
        }

        state.loadInitial()
        await wait(until: { state.hasLoaded })
        state.loadInitial()
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(calls, 1)
    }

    func testLoadMoreAppendsTheNextPage() async {
        var offsets: [Int] = []
        let state = makeState(pageSize: 30) { request in
            offsets.append(request.offset)
            return self.page(request.offset, min(30, 75 - request.offset), 75)
        }

        state.loadInitial()
        await wait(until: { state.hasLoaded })
        state.loadMore()
        await wait(until: { state.options.count == 60 })
        state.loadMore()
        await wait(until: { state.options.count == 75 })

        XCTAssertEqual(offsets, [0, 30, 60])
        XCTAssertEqual(Set(state.options.map(\.value)).count, 75)
        XCTAssertFalse(state.hasMore)
    }

    func testLoadMoreDoesNothingOnceExhausted() async {
        var calls = 0
        let state = makeState { _ in
            calls += 1
            return self.page(0, 10, 10)
        }

        state.loadInitial()
        await wait(until: { state.hasLoaded })
        XCTAssertFalse(state.hasMore)
        state.loadMore()
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(calls, 1)
    }

    func testFirstPageFailureShowsRetryThenRecovers() async {
        var attempt = 0
        let state = makeState { _ in
            attempt += 1
            if attempt == 1 { throw ThunderIDError(code: .serverError, message: "Upstream exploded") }
            return self.page(0, 5, 5)
        }

        state.loadInitial()
        await wait(until: { state.failure != nil })
        XCTAssertEqual(state.failure?.message, "Upstream exploded")
        XCTAssertFalse(state.hasLoaded)

        state.retry()
        await wait(until: { state.hasLoaded })
        XCTAssertNil(state.failure)
        XCTAssertEqual(state.options.count, 5)
    }

    func testNextPageFailureKeepsAlreadyLoadedOptions() async {
        var attempt = 0
        let state = makeState(pageSize: 30) { request in
            attempt += 1
            if attempt == 2 { throw ThunderIDError(code: .networkError, message: "Offline") }
            return self.page(request.offset, 30, 60)
        }

        state.loadInitial()
        await wait(until: { state.hasLoaded })
        state.loadMore()
        await wait(until: { state.failure != nil })

        XCTAssertEqual(state.options.count, 30)
        XCTAssertEqual(state.failure?.message, "Offline")

        state.retry()
        await wait(until: { state.options.count == 60 })
        XCTAssertNil(state.failure)
    }

    func testAPlainErrorShowsNoMessage() async {
        struct PlainError: Error {}
        let state = makeState { _ in throw PlainError() }

        state.loadInitial()
        await wait(until: { state.failure != nil })

        XCTAssertNil(state.failure?.message)
    }

    func testResetDropsAStaleInFlightResult() async {
        let state = makeState { request in
            try? await Task.sleep(nanoseconds: 30_000_000)
            return self.page(0, 5, 5)
        }

        state.loadInitial()
        for _ in 0..<5 { await Task.yield() }
        state.reset()
        try? await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertFalse(state.hasLoaded)
        XCTAssertTrue(state.options.isEmpty)
    }

    func testDedupesAnItemRepeatedAcrossAPageBoundary() async {
        let state = makeState(pageSize: 2) { request in
            if request.offset == 0 {
                return PagedSelectPage(items: [Item(id: "a"), Item(id: "b")], nextOffset: 2, totalResults: 3)
            }
            return PagedSelectPage(items: [Item(id: "b"), Item(id: "c")], nextOffset: nil, totalResults: 3)
        }

        state.loadInitial()
        await wait(until: { state.hasLoaded })
        state.loadMore()
        await wait(until: { !state.hasMore })

        XCTAssertEqual(state.options.map(\.value), ["a", "b", "c"])
    }

    func testTwoImmediateLoadInitialCallsFetchOnce() async {
        var calls = 0
        let state = makeState { _ in
            calls += 1
            return self.page(0, 5, 5)
        }

        state.loadInitial()
        state.loadInitial()
        await wait(until: { state.hasLoaded })

        XCTAssertEqual(calls, 1)
    }

    func testRepeatedLoadMoreWhileAPageIsLoadingFetchesItOnce() async {
        var offsets: [Int] = []
        let state = makeState { request in
            offsets.append(request.offset)
            return self.page(request.offset, min(30, 75 - request.offset), 75)
        }

        state.loadInitial()
        await wait(until: { state.hasLoaded })
        state.loadMore()
        state.loadMore()
        state.loadMore()
        await wait(until: { state.options.count == 60 })

        XCTAssertEqual(offsets, [0, 30])
    }

    func testRetryDoesNothingWithoutAFailure() async {
        var calls = 0
        let state = makeState { _ in
            calls += 1
            return self.page(0, 5, 5)
        }

        state.loadInitial()
        await wait(until: { state.hasLoaded })
        state.retry()
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(calls, 1)
    }

    func testResetBeforeAQueuedLoadStartsPublishesNothing() async {
        let state = makeState { _ in self.page(0, 5, 5) }

        state.loadInitial()
        state.reset()
        try? await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertFalse(state.hasLoaded)
        XCTAssertTrue(state.options.isEmpty)
        XCTAssertFalse(state.isLoading)
    }

    func testAPageMappedToNoOptionsStillLeavesLaterPagesReachable() async {
        var offsets: [Int] = []
        let state = PagedSelectState<Item>(fetch: { request in
            offsets.append(request.offset)
            if request.offset == 0 {
                return PagedSelectPage(items: [Item(id: "hidden")], nextOffset: 30, totalResults: 31)
            }
            return PagedSelectPage(items: [Item(id: "user-31")], nextOffset: nil, totalResults: 31)
        }, convert: { $0.filter { $0.id != "hidden" }.map { PagedSelectOption(label: $0.id, value: $0.id) } })

        state.loadInitial()
        await wait(until: { state.hasLoaded })

        XCTAssertTrue(state.options.isEmpty)
        XCTAssertTrue(state.hasMore)

        state.loadMore()
        await wait(until: { !state.hasMore })

        XCTAssertEqual(offsets, [0, 30])
        XCTAssertEqual(state.options.map(\.value), ["user-31"])
    }

    func testTheSelectedLabelSurvivesResetAndOnlyMatchesItsOwnValue() async {
        let state = makeState { _ in self.page(0, 3, 3) }
        state.loadInitial()
        await wait(until: { state.hasLoaded })

        state.select(PagedSelectOption(label: "Jane Smith", value: "user-2"))
        state.reset()

        XCTAssertTrue(state.options.isEmpty)
        XCTAssertEqual(state.label(forValue: "user-2"), "Jane Smith")
        XCTAssertNil(state.label(forValue: "user-9"))
    }

    func testALoadedOptionLabelsAValueThatWasNeverSelectedHere() async {
        let state = PagedSelectState<Item>(fetch: { _ in
            PagedSelectPage(options: [PagedSelectOption(label: "Jane Smith", value: "user-2")], nextOffset: nil)
        }, convert: { _ in [] })

        state.loadInitial()
        await wait(until: { state.hasLoaded })

        XCTAssertEqual(state.label(forValue: "user-2"), "Jane Smith")
    }

    func testChangingTheFilterResetsAndTheNextLoadUsesIt() async {
        var filters: [String?] = []
        let fetch: FetchPagedOptions<Item> = { request in
            filters.append(request.filter)
            return self.page(0, 2, 2)
        }
        let state = PagedSelectState<Item>(filter: "department eq \"A\"", fetch: fetch, convert: toOptions)
        state.loadInitial()
        await wait(until: { state.hasLoaded })

        let didReset = state.configure(pageSize: 30, filter: "department eq \"B\"", fetch: fetch, convert: toOptions)
        XCTAssertTrue(didReset)
        XCTAssertFalse(state.hasLoaded)
        XCTAssertTrue(state.options.isEmpty)

        state.loadInitial()
        await wait(until: { state.hasLoaded })

        XCTAssertEqual(filters, ["department eq \"A\"", "department eq \"B\""])
    }

    func testAnUnchangedFilterKeepsThePagesButAdoptsTheNewLoader() async {
        var source = "first"
        let state = makeState { _ in
            source = "first"
            return self.page(0, 30, 60)
        }
        state.loadInitial()
        await wait(until: { state.hasLoaded })

        let didReset = state.configure(
            pageSize: 30,
            filter: nil,
            fetch: { request in
                source = "second"
                return self.page(request.offset, 30, 60)
            },
            convert: toOptions
        )
        state.loadMore()
        await wait(until: { state.options.count == 60 })

        XCTAssertFalse(didReset)
        XCTAssertEqual(source, "second")
    }

    func testAResultFromTheOldFilterIsDroppedAfterAChange() async {
        let state = PagedSelectState<Item>(filter: "old", fetch: { _ in
            try? await Task.sleep(nanoseconds: 30_000_000)
            return self.page(0, 5, 5)
        }, convert: toOptions)

        state.loadInitial()
        for _ in 0..<5 { await Task.yield() }
        state.configure(pageSize: 30, filter: "new", fetch: { _ in self.page(0, 1, 1) }, convert: toOptions)
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertFalse(state.hasLoaded)
        XCTAssertTrue(state.options.isEmpty)
    }
}
