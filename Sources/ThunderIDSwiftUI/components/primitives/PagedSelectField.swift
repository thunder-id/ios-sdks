// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// The i18n keys a ``PagedSelectField`` shows for its placeholder, empty list, and load failure,
/// so a specialised picker can use its own wording.
public struct PagedSelectMessages {
    public let placeholder: String
    public let empty: String
    public let loadError: String

    public init(
        placeholder: String = "pagedSelect.placeholder",
        empty: String = "pagedSelect.empty",
        loadError: String = "pagedSelect.loadError"
    ) {
        self.placeholder = placeholder
        self.empty = empty
        self.loadError = loadError
    }
}

/// Single-choice picker whose options load a page at a time from `fetch`, submitting the chosen
/// option's value. Specialised pickers (users, ...) wrap it with their own loader and wording.
///
/// A loader that returns raw `items` needs a `mapping`; without one it must return ready-made
/// `options`.
public struct PagedSelectField<Item>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n

    private let name: String
    @Binding private var value: String
    private let label: String
    private let placeholder: String?
    private let error: String?
    private let messages: PagedSelectMessages
    private let pageSize: Int
    private let filter: String?
    private let fetch: FetchPagedOptions<Item>
    private let convert: ([Item]) -> [PagedSelectOption]

    @StateObject private var state: PagedSelectState<Item>
    @State private var isPresented = false

    public init(
        name: String,
        value: Binding<String>,
        fetch: @escaping FetchPagedOptions<Item>,
        mapping: PagedSelectOptionMapping<Item>? = nil,
        label: String,
        placeholder: String? = nil,
        error: String? = nil,
        pageSize: Int = 30,
        filter: String? = nil,
        messages: PagedSelectMessages = PagedSelectMessages()
    ) {
        self.init(
            name: name,
            value: value,
            fetch: fetch,
            convert: { items in mapping.map { toPagedSelectOptions(items, mapping: $0) } ?? [] },
            label: label,
            placeholder: placeholder,
            error: error,
            pageSize: pageSize,
            filter: filter,
            messages: messages
        )
    }

    init(
        name: String,
        value: Binding<String>,
        fetch: @escaping FetchPagedOptions<Item>,
        convert: @escaping ([Item]) -> [PagedSelectOption],
        label: String,
        placeholder: String? = nil,
        error: String? = nil,
        pageSize: Int = 30,
        filter: String? = nil,
        messages: PagedSelectMessages = PagedSelectMessages()
    ) {
        self.name = name
        _value = value
        self.label = label
        self.placeholder = placeholder
        self.error = error
        self.messages = messages
        self.pageSize = pageSize
        self.filter = filter
        self.fetch = fetch
        self.convert = convert
        _state = StateObject(wrappedValue: PagedSelectState(
            pageSize: pageSize,
            filter: filter,
            fetch: fetch,
            convert: convert
        ))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                Text(label).font(.subheadline).foregroundColor(.secondary)
            }
            Button {
                configureState()
                isPresented = true
                state.loadInitial()
            } label: {
                HStack {
                    Text(selectedLabel ?? placeholder ?? i18n.resolve(messages.placeholder))
                        .foregroundColor(selectedLabel == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Color.fieldBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fieldBorder, lineWidth: 1))
            }
            .accessibilityIdentifier("thunderid-field-\(name)")
            .sheet(isPresented: $isPresented, onDismiss: { state.reset() }, content: {
                PagedSelectListView(state: state, i18n: i18n, messages: messages) { option in
                    state.select(option)
                    value = option.value
                    isPresented = false
                }
            })
            .task(id: QueryKey(pageSize: pageSize, filter: filter)) {
                if configureState(), isPresented {
                    state.loadInitial()
                }
            }
            if let error {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
    }

    private var selectedLabel: String? {
        guard !value.isEmpty else { return nil }
        return state.label(forValue: value) ?? value
    }

    /// Hands the state this render's inputs, so a changed filter or page size restarts the list
    /// and a changed loader or mapping applies to the next request.
    @discardableResult
    private func configureState() -> Bool {
        state.configure(pageSize: pageSize, filter: filter, fetch: fetch, convert: convert)
    }
}

/// The inputs that make already-loaded pages stale when they change.
private struct QueryKey: Hashable {
    let pageSize: Int
    let filter: String?
}

/// The picker's option list, presented in a sheet. A separate view so ``PagedSelectField`` does
/// not need to know the list's own layout.
private struct PagedSelectListView<Item>: View {
    @ObservedObject var state: PagedSelectState<Item>
    let i18n: ThunderIDI18n
    let messages: PagedSelectMessages
    let onSelect: (PagedSelectOption) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(state.options) { option in
                    Button {
                        guard !option.disabled else { return }
                        onSelect(option)
                    } label: {
                        Text(option.label).foregroundColor(option.disabled ? .secondary : .primary)
                    }
                    .disabled(option.disabled)
                    .accessibilityIdentifier("thunderid-option-\(option.value)")
                    .onAppear {
                        if option.id == state.options.last?.id {
                            state.loadMore()
                        }
                    }
                }

                if state.isLoading || state.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

                // Paging depends on the server having more pages, not on how many options survived
                // mapping, so an empty mapped page still offers the next one.
                if let failure = state.failure {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(failure.message ?? i18n.resolve(messages.loadError))
                            .foregroundColor(.red)
                        Button(i18n.resolve("pagedSelect.retry")) { state.retry() }
                    }
                } else if state.hasLoaded, !state.hasMore, state.options.isEmpty {
                    Text(i18n.resolve(messages.empty)).foregroundColor(.secondary)
                } else if state.hasLoaded, state.hasMore, !state.isLoadingMore {
                    Button(i18n.resolve("pagedSelect.loadMore")) { state.loadMore() }
                }
            }
            .listStyle(.plain)
        }
    }
}

private extension Color {
    static var fieldBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var fieldBorder: Color {
        #if canImport(UIKit)
        Color(uiColor: .separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }
}
