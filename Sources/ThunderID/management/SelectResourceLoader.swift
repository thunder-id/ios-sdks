// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let selectLogger = Logger(subsystem: "dev.thunderid.sdk", category: "Select")

/// Tells whether a failed read is worth trying once more: a server error, or no response at all
/// (a network failure or a timeout). Every other failure, including a client error, is final.
public func isRetryableSelectError(_ error: Error) -> Bool {
    guard let error = error as? ThunderIDError else { return false }
    switch error.code {
    case .serverError, .networkError, .requestTimeout:
        return true
    default:
        return false
    }
}

/// Runs a read operation and, when it fails with a retryable error, runs it once more after a short
/// pause. Cancelling the task cancels the pause and skips the retry. Only use it for operations that
/// are safe to repeat.
public func withSelectRetry<Result>(
    delayNanoseconds: UInt64 = SelectConstants.retryDelayNanoseconds,
    shouldRetry: (Error) -> Bool = isRetryableSelectError,
    operation: () async throws -> Result
) async throws -> Result {
    do {
        return try await operation()
    } catch {
        if Task.isCancelled || !shouldRetry(error) { throw error }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        if Task.isCancelled { throw error }
        return try await operation()
    }
}

/// What is known about a failed page load. It carries no text from the failure itself, which is
/// whatever the server or a proxy replied and can hold data the SDK does not control.
public struct SelectLoadFailure: Equatable {
    public let resource: String
    /// The SDK error code, or `unknown` for any other failure.
    public let code: String
    public let attempts: Int
    public let limit: Int
    public let offset: Int
    public let durationMilliseconds: Int
}

/// Logs the final failure of a page load once. For one picker, the first failure of each error code
/// is logged as an error and repeats at debug level, so repeated attempts against a failing list do
/// not flood the log.
public final class SelectFailureLogger {
    public typealias Sink = (_ failure: SelectLoadFailure, _ isRepeat: Bool) -> Void

    private let lock = NSLock()
    private var loggedCodes = Set<String>()
    private let sink: Sink

    public init(sink: @escaping Sink = SelectFailureLogger.writeToSystemLog) {
        self.sink = sink
    }

    public func log(_ failure: SelectLoadFailure) {
        lock.lock()
        let isRepeat = !loggedCodes.insert(failure.code).inserted
        lock.unlock()
        sink(failure, isRepeat)
    }

    public static func writeToSystemLog(_ failure: SelectLoadFailure, isRepeat: Bool) {
        let resource = failure.resource
        let code = failure.code
        let attempts = failure.attempts
        let offset = failure.offset
        let limit = failure.limit
        let duration = failure.durationMilliseconds
        if isRepeat {
            selectLogger.debug("""
                Failed to load \(resource, privacy: .public) again. code=\(code, privacy: .public) \
                attempts=\(attempts) offset=\(offset) limit=\(limit) durationMs=\(duration)
                """)
        } else {
            selectLogger.error("""
                Failed to load \(resource, privacy: .public). code=\(code, privacy: .public) \
                attempts=\(attempts) offset=\(offset) limit=\(limit) durationMs=\(duration)
                """)
        }
    }
}

/// Runs one page request of a resource list. A server error or a failure with no response is retried
/// once, a client error is not. The final failure is logged once, with the call context, and
/// rethrown unchanged. Cancellation is not a failure and is not logged.
public func loadSelectPageWithRetryAndLog<Result>(
    resource: String,
    limit: Int,
    offset: Int,
    logger: SelectFailureLogger,
    retryDelayNanoseconds: UInt64 = SelectConstants.retryDelayNanoseconds,
    operation: () async throws -> Result
) async throws -> Result {
    let startedAt = Date()
    var attempts = 0
    do {
        return try await withSelectRetry(delayNanoseconds: retryDelayNanoseconds) {
            attempts += 1
            return try await operation()
        }
    } catch {
        if !Task.isCancelled {
            logger.log(SelectLoadFailure(
                resource: resource,
                code: (error as? ThunderIDError)?.code.rawValue ?? "unknown",
                attempts: attempts,
                limit: limit,
                offset: offset,
                durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000)
            ))
        }
        throw error
    }
}

/// Builds the loader a select picker gives to its options helper. The loader asks the page function
/// for one page at the cursor offset, retries a server or network failure once, converts the items
/// to options and returns them with the offset of the next page.
public struct ResourceOptionsLoader<Item> {
    /// What is being loaded, such as `users`. Named in the failure log.
    public let resource: String
    public let pageSize: Int
    public let filter: String?
    public let fetchPage: FetchSelectPage<Item>
    /// Converts the raw items of a page that came without ready-made options.
    public let convert: ([Item]) -> [SelectOption]
    public let logger: SelectFailureLogger
    public let retryDelayNanoseconds: UInt64

    public init(
        resource: String,
        pageSize: Int = SelectConstants.defaultPageSize,
        filter: String? = nil,
        logger: SelectFailureLogger = SelectFailureLogger(),
        retryDelayNanoseconds: UInt64 = SelectConstants.retryDelayNanoseconds,
        fetchPage: @escaping FetchSelectPage<Item>,
        convert: @escaping ([Item]) -> [SelectOption] = { _ in [] }
    ) {
        self.resource = resource
        self.pageSize = resolvePageSize(pageSize)
        self.filter = filter
        self.logger = logger
        self.retryDelayNanoseconds = retryDelayNanoseconds
        self.fetchPage = fetchPage
        self.convert = convert
    }

    public func load(cursor: Int?) async throws -> SelectOptionsBatch<Int> {
        let offset = cursor ?? 0
        let request = SelectPageRequest(limit: pageSize, offset: offset, filter: filter)
        let fetchPage = fetchPage
        let page = try await loadSelectPageWithRetryAndLog(
            resource: resource,
            limit: pageSize,
            offset: offset,
            logger: logger,
            retryDelayNanoseconds: retryDelayNanoseconds
        ) {
            try await fetchPage(request)
        }
        return .page(
            options: page.options ?? convert(page.items ?? []),
            nextCursor: isAdvancingPageOffset(offset, page.nextOffset) ? page.nextOffset : nil
        )
    }
}
