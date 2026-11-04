// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

private struct Boom: Error, Equatable {
    let id: Int
}

@MainActor
private final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?

    /// Whether a caller is suspended at the gate.
    var isWaiting: Bool { continuation != nil }

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class InfiniteOptionsStateTests: XCTestCase {
    private func options(_ range: Range<Int>) -> [SelectOption] {
        range.map { SelectOption(label: "User \($0 + 1)", value: "user-\($0 + 1)") }
    }

    private func page(_ start: Int, _ count: Int, _ total: Int) -> SelectOptionsBatch<Int> {
        .page(options: options(start..<(start + count)), nextCursor: start + count < total ? start + count : nil)
    }

    private func makeState(
        initialOptions: [SelectOption] = [],
        onError: ((Error) -> Void)? = nil,
        load: @escaping InfiniteOptionsState<Int>.Load
    ) -> InfiniteOptionsState<Int> {
        InfiniteOptionsState(initialOptions: initialOptions, load: load, onError: onError)
    }

    private func wait(until condition: @escaping () -> Bool, timeout: Int = 500) async {
        for _ in 0..<timeout where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "condition not met before timeout")
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func testMakesNoRequestUntilLoadMore() async {
        var calls = 0
        let state = makeState { _ in
            calls += 1
            return self.page(0, 0, 0)
        }

        await settle()

        XCTAssertEqual(calls, 0)
        XCTAssertTrue(state.options.isEmpty)
        XCTAssertFalse(state.loading)
    }

    func testTheInitialOptionsAreShownBeforeAnythingLoads() {
        let state = makeState(initialOptions: options(0..<2)) { _ in nil }

        XCTAssertEqual(state.options.map(\.value), ["user-1", "user-2"])
    }

    func testTheFirstLoadHasNoCursor() async {
        var contexts: [SelectOptionsLoadContext<Int>] = []
        let state = makeState { context in
            contexts.append(context)
            return self.page(0, 30, 75)
        }

        state.loadMore()
        await wait(until: { !state.loading && !state.options.isEmpty })

        XCTAssertEqual(contexts.count, 1)
        XCTAssertNil(contexts.first?.cursor)
        XCTAssertEqual(state.options.count, 30)
        XCTAssertTrue(state.hasMore)
    }

    func testTwoImmediateCallsMakeOneRequest() async {
        var calls = 0
        let state = makeState { _ in
            calls += 1
            return self.page(0, 30, 75)
        }

        state.loadMore()
        state.loadMore()
        await wait(until: { !state.loading && !state.options.isEmpty })

        XCTAssertEqual(calls, 1)
    }

    func testTheNextLoadContinuesFromTheStoredCursor() async {
        var cursors: [Int?] = []
        let state = makeState { context in
            cursors.append(context.cursor)
            let start = context.cursor ?? 0
            return self.page(start, 30, 75)
        }

        state.loadMore()
        await wait(until: { state.options.count == 30 && !state.loading })
        state.loadMore()
        await wait(until: { state.options.count == 60 && !state.loading })

        XCTAssertEqual(cursors, [nil, 30])
        XCTAssertEqual(state.options.map(\.value).last, "user-60")
    }

    func testDoesNothingOnceTheDataHasEnded() async {
        var calls = 0
        let state = makeState { _ in
            calls += 1
            return .page(options: self.options(0..<3), nextCursor: nil)
        }

        state.loadMore()
        await wait(until: { !state.loading && state.options.count == 3 })
        state.loadMore()
        await settle()

        XCTAssertEqual(calls, 1)
        XCTAssertFalse(state.hasMore)
    }

    func testAFailedLoadKeepsTheOptionsSetsTheErrorAndCallsOnError() async {
        var reported: [Error] = []
        var attempt = 0
        let state = makeState(onError: { reported.append($0) }) { context in
            attempt += 1
            if attempt == 2 { throw Boom(id: 2) }
            return self.page(context.cursor ?? 0, 30, 75)
        }

        state.loadMore()
        await wait(until: { state.options.count == 30 && !state.loading })
        state.loadMore()
        await wait(until: { state.error != nil && !state.loading })

        XCTAssertEqual(state.options.count, 30)
        XCTAssertEqual(state.error as? Boom, Boom(id: 2))
        XCTAssertEqual(reported.count, 1)
        XCTAssertTrue(state.hasMore)
    }

    func testAskingAgainAfterAFailureRepeatsTheSameRequestAndClearsTheError() async {
        var cursors: [Int?] = []
        var attempt = 0
        let state = makeState { context in
            cursors.append(context.cursor)
            attempt += 1
            if attempt == 1 { throw Boom(id: 1) }
            return self.page(0, 30, 75)
        }

        state.loadMore()
        await wait(until: { state.error != nil && !state.loading })
        state.loadMore()
        await wait(until: { state.options.count == 30 && !state.loading })

        XCTAssertEqual(cursors, [nil, nil])
        XCTAssertNil(state.error)
    }

    func testRemovesAnOptionRepeatedAcrossABatchBoundary() async {
        let state = makeState { context in
            if context.cursor == nil {
                return .page(options: self.options(0..<3), nextCursor: 3)
            }
            return .page(options: self.options(2..<5), nextCursor: nil)
        }

        state.loadMore()
        await wait(until: { state.options.count == 3 && !state.loading })
        state.loadMore()
        await wait(until: { state.options.count == 5 && !state.loading })

        XCTAssertEqual(state.options.map(\.value), ["user-1", "user-2", "user-3", "user-4", "user-5"])
    }

    func testAResultFromBeforeAResetIsDroppedAndDoesNotEndTheNewLoad() async {
        let staleGate = Gate()
        let freshGate = Gate()
        var call = 0
        let state = makeState { _ in
            call += 1
            if call == 1 {
                await staleGate.wait()
                return self.page(0, 3, 10)
            }
            await freshGate.wait()
            return .page(options: self.options(100..<103), nextCursor: nil)
        }

        state.loadMore()
        await wait(until: { staleGate.isWaiting })
        state.reset()
        await wait(until: { freshGate.isWaiting })
        staleGate.open()
        await settle()

        XCTAssertTrue(state.options.isEmpty)
        XCTAssertTrue(state.loading)

        freshGate.open()
        await wait(until: { state.options.count == 3 && !state.loading })

        XCTAssertEqual(state.options.map(\.value), ["user-101", "user-102", "user-103"])
        XCTAssertFalse(state.hasMore)
    }

    func testAFailureFromBeforeAResetIsNotReported() async {
        let staleGate = Gate()
        var reported = 0
        var call = 0
        let state = makeState(onError: { _ in reported += 1 }) { _ in
            call += 1
            if call == 1 {
                await staleGate.wait()
                throw Boom(id: 1)
            }
            return self.page(0, 3, 3)
        }

        state.loadMore()
        await wait(until: { staleGate.isWaiting })
        state.reset()
        await wait(until: { state.options.count == 3 && !state.loading })
        staleGate.open()
        await settle()

        XCTAssertEqual(reported, 0)
        XCTAssertNil(state.error)
        XCTAssertEqual(state.options.count, 3)
        XCTAssertFalse(state.loading)
    }

    func testResetGoesBackToTheInitialOptionsAndTheFirstCursor() async {
        var cursors: [Int?] = []
        let state = makeState(initialOptions: options(0..<1)) { context in
            cursors.append(context.cursor)
            return self.page(context.cursor ?? 0, 2, 4)
        }

        state.loadMore()
        await wait(until: { state.options.count == 2 && !state.loading })
        state.reset()
        await wait(until: { state.options.count == 2 && !state.loading && cursors.count == 2 })

        XCTAssertEqual(cursors, [nil, nil])
    }

    func testResetLoadsAgainRightAwayWhenLoadingHadBeenRequested() async {
        var calls = 0
        let state = makeState { _ in
            calls += 1
            return self.page(0, 3, 3)
        }

        state.loadMore()
        await wait(until: { !state.loading && state.options.count == 3 })
        state.reset()
        await wait(until: { calls == 2 && !state.loading })

        XCTAssertEqual(state.options.count, 3)
    }

    func testResetDoesNotLoadWhenNothingWasRequested() async {
        var calls = 0
        let state = makeState(initialOptions: options(0..<1)) { _ in
            calls += 1
            return nil
        }

        state.reset()
        await settle()

        XCTAssertEqual(calls, 0)
        XCTAssertEqual(state.options.count, 1)
    }

    func testABatchThatAddsNothingNewKeepsLoadingUpToTheLimitThenWaits() async {
        var calls = 0
        let state = makeState(initialOptions: options(0..<1)) { context in
            calls += 1
            return .page(options: self.options(0..<1), nextCursor: (context.cursor ?? 0) + 1)
        }

        state.loadMore()
        await wait(until: { !state.loading })

        XCTAssertEqual(calls, SelectConstants.maxEmptyContinuations + 1)
        XCTAssertTrue(state.hasMore)

        state.loadMore()
        await wait(until: { calls == 2 * (SelectConstants.maxEmptyContinuations + 1) && !state.loading })
    }

    func testStopsContinuingAsSoonAsABatchAddsSomething() async {
        var calls = 0
        let state = makeState { context in
            calls += 1
            let cursor = context.cursor ?? 0
            if cursor < 2 { return .page(options: [], nextCursor: cursor + 1) }
            return .page(options: self.options(0..<2), nextCursor: cursor + 1)
        }

        state.loadMore()
        await wait(until: { !state.loading && state.options.count == 2 })

        XCTAssertEqual(calls, 3)
    }

    func testACursorThatDoesNotMoveEndsTheList() async {
        let state = makeState(initialOptions: options(0..<1)) { _ in
            .page(options: self.options(0..<1), nextCursor: 5)
        }

        state.loadMore()
        await wait(until: { !state.loading && !state.hasMore })

        XCTAssertFalse(state.hasMore)
    }

    func testAPlainListEndsWhenItAddsNothingNew() async {
        var calls = 0
        let state = makeState { _ in
            calls += 1
            return calls == 1 ? .list(self.options(0..<2)) : .list(self.options(0..<2))
        }

        state.loadMore()
        await wait(until: { !state.loading && state.options.count == 2 && state.hasMore })
        state.loadMore()
        await wait(until: { !state.loading && !state.hasMore })

        XCTAssertEqual(calls, 2)
    }

    func testAMissingBatchCountsAsEmptyAndEndsTheList() async {
        let state = makeState { _ in nil }

        state.loadMore()
        await wait(until: { !state.loading && !state.hasMore })

        XCTAssertTrue(state.options.isEmpty)
    }

    func testUpdateGivesTheNextRequestTheNewLoaderWithoutRestartingTheList() async {
        var which: [String] = []
        let state = makeState { context in
            which.append("old")
            return self.page(context.cursor ?? 0, 2, 6)
        }

        state.loadMore()
        await wait(until: { !state.loading && state.options.count == 2 })
        state.update(load: { context in
            which.append("new")
            return self.page(context.cursor ?? 0, 2, 6)
        })
        state.loadMore()
        await wait(until: { !state.loading && state.options.count == 4 })

        XCTAssertEqual(which, ["old", "new"])
    }

    func testReleasingTheStateCancelsARunningLoad() async {
        var cancelled = false
        weak var weakState: InfiniteOptionsState<Int>?
        do {
            let state = makeState { _ in
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    cancelled = true
                }
                return nil
            }
            weakState = state
            state.loadMore()
            await wait(until: { state.loading })
            await settle()
        }

        await wait(until: { weakState == nil })
        await wait(until: { cancelled })
    }

    func testTwoStatesDoNotShareACursor() async {
        let first = makeState { context in self.page(context.cursor ?? 0, 2, 6) }
        let second = makeState { context in self.page(context.cursor ?? 0, 2, 6) }

        first.loadMore()
        await wait(until: { !first.loading && first.options.count == 2 })
        first.loadMore()
        await wait(until: { !first.loading && first.options.count == 4 })
        second.loadMore()
        await wait(until: { !second.loading && second.options.count == 2 })

        XCTAssertEqual(second.options.map(\.value), ["user-1", "user-2"])
    }
}
