// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ThunderID

private func option(_ value: String, label: String? = nil) -> SelectOption {
    SelectOption(label: label ?? value, value: value)
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    @discardableResult
    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private final class FailureRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(failure: SelectLoadFailure, isRepeat: Bool)] = []

    func record(_ failure: SelectLoadFailure, _ isRepeat: Bool) {
        lock.lock(); defer { lock.unlock() }
        entries.append((failure, isRepeat))
    }

    var all: [(failure: SelectLoadFailure, isRepeat: Bool)] { lock.lock(); defer { lock.unlock() }; return entries }
    func logger() -> SelectFailureLogger { SelectFailureLogger { [self] failure, isRepeat in record(failure, isRepeat) } }
}

final class SelectOptionsMergeTests: XCTestCase {
    func testAListThatAddsSomethingContinues() {
        let result = mergeSelectOptionsBatch(cursor: nil as Int?, options: [option("a")], batch: .list([option("b")]))

        XCTAssertEqual(result.options.map(\.value), ["a", "b"])
        XCTAssertFalse(result.finished)
    }

    func testAListThatAddsNothingNewEndsTheData() {
        let result = mergeSelectOptionsBatch(cursor: nil as Int?, options: [option("a")], batch: .list([option("a")]))

        XCTAssertTrue(result.finished)
        XCTAssertNil(result.issue)
    }

    func testAPageWithoutACursorEndsTheDataAfterAppending() {
        let result = mergeSelectOptionsBatch(cursor: 0, options: [], batch: .page(options: [option("a")], nextCursor: nil))

        XCTAssertEqual(result.options.map(\.value), ["a"])
        XCTAssertTrue(result.finished)
        XCTAssertNil(result.cursor)
    }

    func testAPageWithACursorContinuesFromIt() {
        let result = mergeSelectOptionsBatch(cursor: 0, options: [], batch: .page(options: [option("a")], nextCursor: 30))

        XCTAssertFalse(result.finished)
        XCTAssertEqual(result.cursor, 30)
    }

    func testAPageOfDuplicatesWithAnAdvancingCursorContinues() {
        let result = mergeSelectOptionsBatch(cursor: 0, options: [option("a")], batch: .page(options: [option("a")], nextCursor: 30))

        XCTAssertFalse(result.finished)
        XCTAssertEqual(result.cursor, 30)
    }

    func testAPageOfDuplicatesWithTheSameCursorEndsTheDataAndReportsIt() {
        let result = mergeSelectOptionsBatch(cursor: 30, options: [option("a")], batch: .page(options: [option("a")], nextCursor: 30))

        XCTAssertTrue(result.finished)
        XCTAssertEqual(result.issue, .cursorStuck)
    }

    func testARepeatedOptionIsReplacedInPlaceByItsNewerCopy() {
        let existing = [option("a", label: "Old"), option("b")]
        let result = mergeSelectOptionsBatch(cursor: nil as Int?, options: existing, batch: .list([option("a", label: "New")]))

        XCTAssertEqual(result.options.map(\.label), ["New", "b"])
    }

    func testAMissingBatchCountsAsAnEmptyList() {
        let result = mergeSelectOptionsBatch(cursor: nil as Int?, options: [option("a")], batch: nil)

        XCTAssertEqual(result.options.map(\.value), ["a"])
        XCTAssertTrue(result.finished)
    }
}

final class LoadUntilOptionsGrowTests: XCTestCase {
    func testStopsAfterABatchThatGrewTheList() async throws {
        let loads = Counter()

        try await loadUntilOptionsGrow(
            loadBatch: { loads.increment() },
            applyBatch: { _ in false },
            isCurrent: { true }
        )

        XCTAssertEqual(loads.value, 1)
    }

    func testKeepsLoadingWhileBatchesAddNothingButStopsAfterAFewInARow() async throws {
        let loads = Counter()

        try await loadUntilOptionsGrow(
            loadBatch: { loads.increment() },
            applyBatch: { _ in true },
            isCurrent: { true }
        )

        XCTAssertEqual(loads.value, SelectConstants.maxEmptyContinuations + 1)
    }

    func testStopsWithoutApplyingOnceTheListWasReset() async throws {
        let applied = Counter()

        try await loadUntilOptionsGrow(
            loadBatch: { 1 },
            applyBatch: { _ in applied.increment(); return true },
            isCurrent: { false }
        )

        XCTAssertEqual(applied.value, 0)
    }

    func testPassesALoadFailureOn() async {
        struct Boom: Error {}

        do {
            try await loadUntilOptionsGrow(loadBatch: { throw Boom() }, applyBatch: { (_: Int) in false }, isCurrent: { true })
            XCTFail("expected a failure")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }
}

final class SelectRetryTests: XCTestCase {
    private func failure(_ code: ThunderIDErrorCode, _ message: String = "failed") -> ThunderIDError {
        ThunderIDError(code: code, message: message)
    }

    func testRetriesAServerErrorAndANoResponseFailure() {
        XCTAssertTrue(isRetryableSelectError(failure(.serverError)))
        XCTAssertTrue(isRetryableSelectError(failure(.networkError)))
        XCTAssertTrue(isRetryableSelectError(failure(.requestTimeout)))
    }

    func testDoesNotRetryAClientErrorOrAnUnknownFailure() {
        struct PlainError: Error {}

        XCTAssertFalse(isRetryableSelectError(failure(.forbidden)))
        XCTAssertFalse(isRetryableSelectError(failure(.notFound)))
        XCTAssertFalse(isRetryableSelectError(failure(.invalidInput)))
        XCTAssertFalse(isRetryableSelectError(failure(.authenticationFailed)))
        XCTAssertFalse(isRetryableSelectError(PlainError()))
    }

    func testARetryableFailureIsTriedOnceMoreAndCanRecover() async throws {
        let calls = Counter()

        let result: String = try await withSelectRetry(delayNanoseconds: 1_000_000) {
            if calls.increment() == 1 { throw failure(.serverError) }
            return "ok"
        }

        XCTAssertEqual(result, "ok")
        XCTAssertEqual(calls.value, 2)
    }

    func testTheSecondFailureIsTheOneThatIsThrown() async {
        let calls = Counter()

        do {
            let _: String = try await withSelectRetry(delayNanoseconds: 1_000_000) {
                throw failure(.serverError, "attempt \(calls.increment())")
            }
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual((error as? ThunderIDError)?.message, "attempt 2")
        }
    }

    func testAClientErrorIsNotRetried() async {
        let calls = Counter()

        do {
            let _: String = try await withSelectRetry(delayNanoseconds: 1_000_000) {
                calls.increment()
                throw failure(.forbidden)
            }
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual((error as? ThunderIDError)?.code, .forbidden)
        }
        XCTAssertEqual(calls.value, 1)
    }

    func testCancellingDuringThePauseSkipsTheRetry() async {
        let calls = Counter()
        let task = Task { () -> String in
            try await withSelectRetry(delayNanoseconds: 5_000_000_000) {
                calls.increment()
                throw failure(.serverError)
            }
        }

        while calls.value == 0 { await Task.yield() }
        task.cancel()
        let outcome = await task.result

        if case .success = outcome { XCTFail("expected a failure") }
        XCTAssertEqual(calls.value, 1)
    }
}

final class SelectFailureLoggerTests: XCTestCase {
    private func failure(_ code: String) -> SelectLoadFailure {
        SelectLoadFailure(resource: "users", code: code, attempts: 2, limit: 30, offset: 0, durationMilliseconds: 5)
    }

    func testTheFirstFailureOfACodeIsLoggedAndRepeatsAreMarked() {
        let recorder = FailureRecorder()
        let logger = recorder.logger()

        logger.log(failure("SERVER_ERROR"))
        logger.log(failure("SERVER_ERROR"))
        logger.log(failure("FORBIDDEN"))

        XCTAssertEqual(recorder.all.map(\.isRepeat), [false, true, false])
    }

    func testALoadThatSucceedsLogsNothing() async throws {
        let recorder = FailureRecorder()

        let result = try await loadSelectPageWithRetryAndLog(
            resource: "users", limit: 30, offset: 0, logger: recorder.logger()
        ) { "page" }

        XCTAssertEqual(result, "page")
        XCTAssertEqual(recorder.all.count, 0)
    }

    func testALoadThatRecoversOnTheRetryLogsNothing() async throws {
        let recorder = FailureRecorder()
        let calls = Counter()

        let result: String = try await loadSelectPageWithRetryAndLog(
            resource: "users", limit: 30, offset: 0, logger: recorder.logger(), retryDelayNanoseconds: 1_000_000
        ) {
            if calls.increment() == 1 { throw ThunderIDError(code: .serverError, message: "Server error: 503") }
            return "page"
        }

        XCTAssertEqual(result, "page")
        XCTAssertEqual(calls.value, 2)
        XCTAssertEqual(recorder.all.count, 0)
    }

    func testTheFinalFailureIsLoggedOnceWithTheCallContextAndRethrownUnchanged() async {
        let recorder = FailureRecorder()

        do {
            let _: String = try await loadSelectPageWithRetryAndLog(
                resource: "users", limit: 30, offset: 60, logger: recorder.logger(), retryDelayNanoseconds: 1_000_000
            ) {
                throw ThunderIDError(code: .serverError, message: "Server error: 503")
            }
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual((error as? ThunderIDError)?.message, "Server error: 503")
        }

        XCTAssertEqual(recorder.all.count, 1)
        let logged = recorder.all[0].failure
        XCTAssertEqual(logged.resource, "users")
        XCTAssertEqual(logged.code, "SERVER_ERROR")
        XCTAssertEqual(logged.attempts, 2)
        XCTAssertEqual(logged.limit, 30)
        XCTAssertEqual(logged.offset, 60)
        XCTAssertGreaterThanOrEqual(logged.durationMilliseconds, 0)
    }

    func testAClientErrorIsLoggedAfterOneAttempt() async {
        let recorder = FailureRecorder()

        let _: String? = try? await loadSelectPageWithRetryAndLog(
            resource: "auth flows", limit: 30, offset: 0, logger: recorder.logger()
        ) {
            throw ThunderIDError(code: .forbidden, message: "Forbidden")
        }

        XCTAssertEqual(recorder.all.first?.failure.code, "FORBIDDEN")
        XCTAssertEqual(recorder.all.first?.failure.attempts, 1)
    }

    func testAFailureThatIsNotAThunderIDErrorIsLoggedAsUnknownAndNotRetried() async {
        struct PlainError: Error {}
        let recorder = FailureRecorder()
        let calls = Counter()

        let _: String? = try? await loadSelectPageWithRetryAndLog(
            resource: "users", limit: 30, offset: 0, logger: recorder.logger()
        ) {
            calls.increment()
            throw PlainError()
        }

        XCTAssertEqual(recorder.all.first?.failure.code, "unknown")
        XCTAssertEqual(calls.value, 1)
    }

    func testACancelledLoadIsNotLoggedAsAFailure() async {
        let recorder = FailureRecorder()
        let started = Counter()
        let task = Task { () -> String in
            try await loadSelectPageWithRetryAndLog(
                resource: "users", limit: 30, offset: 0, logger: recorder.logger()
            ) {
                started.increment()
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return "late"
            }
        }

        while started.value == 0 { await Task.yield() }
        task.cancel()
        _ = await task.result

        XCTAssertEqual(recorder.all.count, 0)
    }
}

final class ResourceOptionsLoaderTests: XCTestCase {
    private struct Item: Equatable {
        let id: String
    }

    private func loader(
        pageSize: Int = 30,
        filter: String? = nil,
        recorder: FailureRecorder = FailureRecorder(),
        fetchPage: @escaping FetchSelectPage<Item>
    ) -> ResourceOptionsLoader<Item> {
        ResourceOptionsLoader(
            resource: "items",
            pageSize: pageSize,
            filter: filter,
            logger: recorder.logger(),
            retryDelayNanoseconds: 1_000_000,
            fetchPage: fetchPage,
            convert: { items in items.map { SelectOption(label: $0.id, value: $0.id) } }
        )
    }

    private final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [SelectPageRequest] = []
        func add(_ request: SelectPageRequest) { lock.lock(); requests.append(request); lock.unlock() }
        var all: [SelectPageRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    }

    func testAsksForTheCursorOffsetWithThePageSizeAndFilter() async throws {
        let requests = Requests()
        let loader = loader(pageSize: 25, filter: "department eq sales") { request in
            requests.add(request)
            return SelectPage(options: [], nextOffset: nil)
        }

        _ = try await loader.load(cursor: nil)
        _ = try await loader.load(cursor: 50)

        XCTAssertEqual(requests.all.map(\.offset), [0, 50])
        XCTAssertEqual(requests.all.map(\.limit), [25, 25])
        XCTAssertEqual(requests.all.map(\.filter), ["department eq sales", "department eq sales"])
    }

    func testClampsThePageSizeToWhatTheBackendServes() async throws {
        let requests = Requests()
        let big = loader(pageSize: 500) { request in
            requests.add(request)
            return SelectPage(options: [], nextOffset: nil)
        }
        let small = loader(pageSize: 0) { request in
            requests.add(request)
            return SelectPage(options: [], nextOffset: nil)
        }

        _ = try await big.load(cursor: nil)
        _ = try await small.load(cursor: nil)

        XCTAssertEqual(requests.all.map(\.limit), [100, 1])
    }

    func testConvertsRawItemsWhenThePageHasNoReadyMadeOptions() async throws {
        let loader = loader { _ in SelectPage(items: [Item(id: "a"), Item(id: "b")], nextOffset: 2) }

        guard case .page(let options, let nextCursor) = try await loader.load(cursor: nil) else {
            return XCTFail("expected a page")
        }

        XCTAssertEqual(options.map(\.value), ["a", "b"])
        XCTAssertEqual(nextCursor, 2)
    }

    func testPrefersReadyMadeOptionsOverItems() async throws {
        let loader = loader { _ in
            SelectPage(items: [Item(id: "raw")], options: [SelectOption(label: "Ready", value: "ready")], nextOffset: nil)
        }

        guard case .page(let options, _) = try await loader.load(cursor: nil) else { return XCTFail("expected a page") }

        XCTAssertEqual(options.map(\.value), ["ready"])
    }

    func testEndsTheListWhenTheNextOffsetDoesNotAdvance() async throws {
        let sameOffset = loader { request in SelectPage(options: [], nextOffset: request.offset) }
        let backwards = loader { _ in SelectPage(options: [], nextOffset: 0) }

        guard case .page(_, let first) = try await sameOffset.load(cursor: 30),
              case .page(_, let second) = try await backwards.load(cursor: 30) else { return XCTFail("expected pages") }

        XCTAssertNil(first)
        XCTAssertNil(second)
    }

    func testRetriesAServerErrorOnceWithoutLoggingIt() async throws {
        let recorder = FailureRecorder()
        let calls = Counter()
        let loader = loader(recorder: recorder) { _ in
            if calls.increment() == 1 { throw ThunderIDError(code: .serverError, message: "Server error: 503") }
            return SelectPage(options: [SelectOption(label: "A", value: "a")], nextOffset: nil)
        }

        guard case .page(let options, _) = try await loader.load(cursor: nil) else { return XCTFail("expected a page") }

        XCTAssertEqual(options.map(\.value), ["a"])
        XCTAssertEqual(recorder.all.count, 0)
    }

    func testALoadThatFailsForGoodIsLoggedOnceAndThrowsTheOriginalError() async {
        let recorder = FailureRecorder()
        let loader = loader(recorder: recorder) { _ in throw ThunderIDError(code: .forbidden, message: "Forbidden") }

        do {
            _ = try await loader.load(cursor: nil)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual((error as? ThunderIDError)?.code, .forbidden)
        }

        XCTAssertEqual(recorder.all.count, 1)
        XCTAssertEqual(recorder.all[0].failure.resource, "items")
    }
}
