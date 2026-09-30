// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// Loads options page by page from a `FetchPagedOptions` loader: lazy first page, incremental
/// paging, de-duplication, and a generation guard that drops a result from a superseded load (a
/// new field, filter, or loader) — the same generation-guard shape `ResourceQuery` uses for
/// management resources. Renders nothing itself, so any design system can use it.
@MainActor
public final class PagedSelectState<Item>: ObservableObject {
    @Published public private(set) var options: [PagedSelectOption] = []
    @Published public private(set) var hasMore = true
    @Published public private(set) var hasLoaded = false
    @Published public private(set) var isLoading = false
    @Published public private(set) var isLoadingMore = false
    @Published public private(set) var failure: PagedSelectFailure?
    /// The option chosen through ``select(_:)``. Survives ``reset()``, so its label stays available
    /// after the loaded pages are discarded.
    @Published public private(set) var selected: PagedSelectOption?

    private var pageSize: Int
    private var filter: String?
    private var fetch: FetchPagedOptions<Item>
    private var convert: ([Item]) -> [PagedSelectOption]

    private var generation = 0
    private var isInFlight = false
    private var nextOffset: Int? = 0
    private var failedOffset = 0

    public init(
        pageSize: Int = 30,
        filter: String? = nil,
        fetch: @escaping FetchPagedOptions<Item>,
        convert: @escaping ([Item]) -> [PagedSelectOption]
    ) {
        self.pageSize = pageSize
        self.filter = filter
        self.fetch = fetch
        self.convert = convert
    }

    /// Loads page 0, once. A later call is a no-op until ``reset()`` starts a fresh generation.
    public func loadInitial() {
        guard !hasLoaded, !isInFlight else { return }
        start(offset: 0)
    }

    /// Loads the page after the last one loaded. A no-op while a load is in flight or the list is exhausted.
    public func loadMore() {
        guard let nextOffset, hasLoaded, !isInFlight else { return }
        start(offset: nextOffset)
    }

    /// Retries the page that most recently failed.
    public func retry() {
        guard failure != nil, !isInFlight else { return }
        start(offset: failedOffset)
    }

    /// Discards loaded/in-flight state so the next ``loadInitial()`` starts a fresh page 0. Call
    /// on dismiss/close so reopening after a scope change (a different field or filter) does not
    /// show a stale list, and superseded in-flight results are dropped by the generation guard.
    /// The ``selected`` option is kept.
    public func reset() {
        generation += 1
        isInFlight = false
        nextOffset = 0
        failedOffset = 0
        options = []
        hasMore = true
        hasLoaded = false
        isLoading = false
        isLoadingMore = false
        failure = nil
    }

    /// Records `option` as the chosen one.
    public func select(_ option: PagedSelectOption) {
        selected = option
    }

    /// The label to show for `value`: the selected option's, else a loaded option's, else `nil`.
    public func label(forValue value: String) -> String? {
        if let selected, selected.value == value { return selected.label }
        return options.first { $0.value == value }?.label
    }

    /// Applies the current inputs. The loader and conversion are used from the next request on;
    /// a changed page size or filter also calls ``reset()``, since pages already loaded belong to
    /// the old query. Returns whether it reset, so a caller with an open list can load again.
    @discardableResult
    public func configure(
        pageSize: Int,
        filter: String?,
        fetch: @escaping FetchPagedOptions<Item>,
        convert: @escaping ([Item]) -> [PagedSelectOption]
    ) -> Bool {
        self.fetch = fetch
        self.convert = convert
        guard pageSize != self.pageSize || filter != self.filter else { return false }
        self.pageSize = pageSize
        self.filter = filter
        reset()
        return true
    }

    /// Reserves the load before scheduling it, so a second call made before the task runs is
    /// rejected by the callers' `isInFlight` guard.
    private func start(offset: Int) {
        isInFlight = true
        if offset == 0 {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        failure = nil

        let generation = generation
        let request = PagedSelectRequest(limit: pageSize, offset: offset, filter: filter)
        let fetch = fetch
        let convert = convert
        Task { await load(request, generation: generation, fetch: fetch, convert: convert) }
    }

    private func load(
        _ request: PagedSelectRequest,
        generation: Int,
        fetch: FetchPagedOptions<Item>,
        convert: ([Item]) -> [PagedSelectOption]
    ) async {
        let isFirstPage = request.offset == 0

        do {
            let page = try await fetch(request)
            guard generation == self.generation else { return }
            let incoming = page.options ?? convert(page.items ?? [])
            options = dedupePagedSelectOptions(isFirstPage ? [] : options, incoming)
            nextOffset = isAdvancingPageOffset(request.offset, page.nextOffset) ? page.nextOffset : nil
            hasMore = nextOffset != nil
            hasLoaded = true
        } catch {
            guard generation == self.generation else { return }
            failedOffset = request.offset
            failure = mapPagedSelectError(error)
        }

        isInFlight = false
        isLoading = false
        isLoadingMore = false
    }
}
