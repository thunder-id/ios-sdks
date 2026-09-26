// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderIDSwiftUI
import XCTest

@MainActor
final class ResourceQueryTests: XCTestCase {
    private struct Failure: Error {}

    func testRefetchPublishesDataAndErrors() async {
        var shouldFail = false
        let query = ResourceQuery(key: ["users"], invalidator: ResourceInvalidator()) {
            if shouldFail { throw Failure() }
            return 42
        }

        await query.refetch()
        XCTAssertEqual(query.data, 42)
        XCTAssertNil(query.error)
        XCTAssertFalse(query.isLoading)

        shouldFail = true
        await query.refetch()
        XCTAssertTrue(query.error is Failure)
        XCTAssertEqual(query.data, 42)
    }

    func testMutationRefetchesLoadedQueriesMatchingItsKeys() async throws {
        let invalidator = ResourceInvalidator()
        var listFetches = 0
        var otherFetches = 0
        let list = ResourceQuery(key: ["applications", "limit=10"], invalidator: invalidator) {
            listFetches += 1
            return listFetches
        }
        let other = ResourceQuery(key: ["agents"], invalidator: invalidator) {
            otherFetches += 1
            return otherFetches
        }
        await list.refetch()
        await other.refetch()

        let mutation = ResourceMutation<String, String>(
            invalidator: invalidator,
            invalidatedKeys: { _ in [["applications"]] },
            perform: { "created \($0)" }
        )
        let output = await mutation.mutate("app")

        XCTAssertEqual(output, "created app")
        for _ in 0..<20 where listFetches < 2 {
            await Task.yield()
        }
        XCTAssertEqual(listFetches, 2)
        XCTAssertEqual(otherFetches, 1)
    }

    func testQueryThatNeverLoadedIgnoresInvalidation() async {
        let invalidator = ResourceInvalidator()
        var fetches = 0
        let query = ResourceQuery(key: ["users"], invalidator: invalidator) {
            fetches += 1
            return fetches
        }

        invalidator.invalidate(["users"])
        await Task.yield()

        XCTAssertEqual(fetches, 0)
        XCTAssertNil(query.data)
    }

    func testMutateNeverThrowsButMutateThrowingDoes() async {
        let mutation = ResourceMutation<Int, Int>(
            invalidator: ResourceInvalidator(),
            invalidatedKeys: { _ in [] },
            perform: { _ in throw Failure() }
        )

        let result = await mutation.mutate(1)
        XCTAssertNil(result)
        XCTAssertTrue(mutation.error is Failure)

        do {
            try await mutation.mutateThrowing(1)
            XCTFail("Expected a failure")
        } catch {
            XCTAssertTrue(error is Failure)
        }

        mutation.reset()
        XCTAssertNil(mutation.error)
    }
}
