// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// What restarts the list of a ``ResourceSelectField``: the page size and the filter.
private struct SelectListQuery: Hashable {
    let pageSize: Int
    let filter: String?
}

/// The part the `USER_SELECT`, `AUTH_FLOW_SELECT` and `USER_TYPE_SELECT` pickers share: a ``SelectField``
/// that loads one resource page by page.
///
/// The first page loads when the field appears, and the loaded options are kept while the sheet is closed.
/// A different page size or filter starts the list again from the beginning. A failed load is retried once
/// when that makes sense, logged once, and handed to `onError`; the field itself shows no error.
struct ResourceSelectField<Item>: View {
    let name: String
    let value: Binding<String>
    let label: String
    let placeholder: String?
    let error: String?
    let isRequired: Bool
    let isDisabled: Bool
    let emptyText: String?
    let selectedOption: SelectOption?
    let messages: SelectMessages
    /// What is loaded, in the words of the failure log, such as `users`.
    let resource: String
    let pageSize: Int
    let filter: String?
    let fetchPage: FetchSelectPage<Item>
    let convert: ([Item]) -> [SelectOption]
    let onError: ((Error) -> Void)?

    @StateObject private var options = InfiniteOptionsState<Int> { _ in nil }
    @State private var failureLogger = SelectFailureLogger()
    @State private var loadedQuery: SelectListQuery?

    private var query: SelectListQuery {
        SelectListQuery(pageSize: resolvePageSize(pageSize), filter: filter)
    }

    var body: some View {
        SelectField(
            name: name,
            value: value,
            options: options.options,
            label: label,
            placeholder: placeholder,
            error: error,
            required: isRequired,
            disabled: isDisabled,
            loading: options.loading,
            onLoadMore: options.hasMore ? loadMore : nil,
            emptyText: emptyText,
            selectedOption: selectedOption,
            messages: messages
        )
        .task(id: query) {
            configure()
            if let loadedQuery, loadedQuery != query { options.reset() }
            loadedQuery = query
            options.loadMore()
        }
    }

    private func loadMore() {
        configure()
        options.loadMore()
    }

    /// Gives the list the current loader, so a request made now reads the current page function.
    private func configure() {
        let loader = ResourceOptionsLoader(
            resource: resource,
            pageSize: query.pageSize,
            filter: query.filter,
            logger: failureLogger,
            fetchPage: fetchPage,
            convert: convert
        )
        options.update(load: { context in try await loader.load(cursor: context.cursor) }, onError: onError)
    }
}
