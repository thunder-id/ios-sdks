// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import ThunderID

private let logger = Logger(subsystem: "dev.thunderid.sdk", category: "InfiniteOptions")

/// Keeps the option list of a ``SelectField`` that loads more options when the user asks for them.
///
/// It owns the cursor, appends each batch without duplicates, and stops at the end of the data.
/// Nothing is drawn, so it works with any list view. A failed load never changes the options: it sets
/// ``error``, calls `onError`, and leaves the cursor where it was, so asking again repeats the same
/// request.
@MainActor
public final class InfiniteOptionsState<Cursor: Equatable>: ObservableObject {
    public typealias Load = (SelectOptionsLoadContext<Cursor>) async throws -> SelectOptionsBatch<Cursor>?

    /// The options loaded so far.
    @Published public private(set) var options: [SelectOption]
    /// Whether a batch is being fetched.
    @Published public private(set) var loading = false
    /// Whether more batches may be available.
    @Published public private(set) var hasMore = true
    /// The error of the last load, cleared by the next successful one.
    @Published public private(set) var error: Error?

    private var initialOptions: [SelectOption]
    private var load: Load
    private var onError: ((Error) -> Void)?
    private var cursor: Cursor?
    private var finished = false
    private var requested = false
    private var generation = 0
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - initialOptions: Options shown before anything is loaded, and again after ``reset()``.
    ///   - load: Loads the next batch. Returning `nil` counts as an empty batch.
    ///   - onError: Called with the error of every failed load.
    public init(
        initialOptions: [SelectOption] = [],
        load: @escaping Load,
        onError: ((Error) -> Void)? = nil
    ) {
        self.initialOptions = initialOptions
        self.options = initialOptions
        self.load = load
        self.onError = onError
    }

    deinit {
        task?.cancel()
    }

    /// Replaces the loader and the error callback. A view calls this on each render so a request made
    /// later uses the current values; it does not restart the list.
    public func update(load: @escaping Load, onError: ((Error) -> Void)? = nil) {
        self.load = load
        self.onError = onError
    }

    /// Loads the next batch. Does nothing while a load is running or once the data has ended.
    public func loadMore() {
        guard !loading, !finished else { return }
        requested = true
        startLoad()
    }

    /// Goes back to the initial options and the first batch. Aborts a running load, and loads again
    /// right away if loading had already been requested.
    public func reset() {
        let shouldReload = requested
        generation += 1
        task?.cancel()
        task = nil
        cursor = nil
        finished = false
        loading = false
        options = initialOptions
        hasMore = true
        error = nil
        if shouldReload { startLoad() }
    }

    private struct Snapshot {
        let load: Load
        let context: SelectOptionsLoadContext<Cursor>
    }

    private func snapshot() -> Snapshot {
        Snapshot(load: load, context: SelectOptionsLoadContext(cursor: cursor, options: options))
    }

    private func startLoad() {
        let generation = generation
        loading = true
        // The task keeps only a weak reference between steps, so a state that went away is not held alive
        // by a request in flight and its deinit cancels the request.
        task = Task { [weak self] in
            do {
                try await loadUntilOptionsGrow(
                    loadBatch: {
                        guard let snapshot = self?.snapshot() else { throw CancellationError() }
                        return try await snapshot.load(snapshot.context)
                    },
                    applyBatch: { batch in self?.apply(batch) ?? false },
                    isCurrent: { self?.generation == generation }
                )
            } catch {
                self?.fail(error, generation: generation)
            }
            self?.finish(generation: generation)
        }
    }

    /// Adds a batch to the list. Returns `true` when it added nothing while more remain.
    private func apply(_ batch: SelectOptionsBatch<Cursor>?) -> Bool {
        let merged = mergeSelectOptionsBatch(cursor: cursor, options: options, batch: batch)
        if merged.issue == .cursorStuck {
            logger.warning("A load returned no new options and the same cursor; the list was treated as finished.")
        }
        let addedNothing = merged.options.count == options.count
        cursor = merged.cursor
        options = merged.options
        finished = merged.finished
        hasMore = !merged.finished
        error = nil
        return addedNothing && !merged.finished
    }

    private func fail(_ failure: Error, generation: Int) {
        guard generation == self.generation, !Task.isCancelled else { return }
        error = failure
        onError?(failure)
    }

    private func finish(generation: Int) {
        guard generation == self.generation else { return }
        task = nil
        loading = false
    }
}
