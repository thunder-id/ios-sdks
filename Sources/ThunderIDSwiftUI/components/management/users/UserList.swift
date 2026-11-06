// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A page of users, rendered from the data it is given. Pair it with
/// ``ThunderIDState/usersQuery(limit:offset:filter:fetcher:)`` or any other source; ``UserList`` does that for you.
public struct BaseUserList<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let users: [ManagedUser]
    let isLoading: Bool
    let error: String?
    let title: String?
    let description: String?
    let limit: Int
    let offset: Int
    let totalResults: Int?
    let selectedUserId: String?
    let onPageChange: ((Int) -> Void)?
    let onSelect: ((ManagedUser) -> Void)?
    let search: AdminSearch?
    let searchAttributes: [AdminOption]
    let onSearch: ((AdminSearch?) -> Void)?
    let actions: AnyView?
    let content: ((AdminListState<ManagedUser>) -> Content)?

    init(
        users: [ManagedUser],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedUserId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((ManagedUser) -> Void)? = nil,
        search: AdminSearch? = nil,
        searchAttributes: [AdminOption] = [],
        onSearch: ((AdminSearch?) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((AdminListState<ManagedUser>) -> Content)?
    ) {
        self.users = users
        self.isLoading = isLoading
        self.error = error
        self.title = title
        self.description = description
        self.limit = limit
        self.offset = offset
        self.totalResults = totalResults
        self.selectedUserId = selectedUserId
        self.onPageChange = onPageChange
        self.onSelect = onSelect
        self.search = search
        self.searchAttributes = searchAttributes
        self.onSearch = onSearch
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default list, from the users, the loading and error
    ///   state, and the pagination and selection handlers.
    public init(
        users: [ManagedUser],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedUserId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((ManagedUser) -> Void)? = nil,
        search: AdminSearch? = nil,
        searchAttributes: [AdminOption] = [],
        onSearch: ((AdminSearch?) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AdminListState<ManagedUser>) -> Content
    ) {
        self.init(
            users: users,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedUserId: selectedUserId,
            onPageChange: onPageChange,
            onSelect: onSelect,
            search: search,
            searchAttributes: searchAttributes,
            onSearch: onSearch,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        if let content {
            content(renderState)
        } else {
            defaultBody
        }
    }

    private var renderState: AdminListState<ManagedUser> {
        AdminListState(
            rows: users,
            isLoading: isLoading,
            error: error,
            limit: limit,
            offset: offset,
            totalResults: totalResults ?? users.count,
            selectedId: selectedUserId,
            onPageChange: onPageChange,
            onSelect: onSelect,
            search: search,
            searchAttributes: searchAttributes,
            onSearch: onSearch
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        AdminSection(
            identifier: "admin-user-list",
            title: title ?? i18n.resolve("admin.users.list.title"),
            description: description,
            actions: { actions },
            content: {
                if let onSearch, !searchAttributes.isEmpty {
                    AdminSearchBar(
                        i18n: i18n,
                        identifier: "admin-user-list",
                        attributes: searchAttributes,
                        search: search,
                        onSearch: onSearch
                    )
                }
                AdminTable(
                    identifier: "admin-user-list",
                    rows: users,
                    rowId: \.id,
                    isLoading: isLoading,
                    error: error,
                    emptyText: search.map { i18n.resolve("admin.common.search.no_results", ["value": $0.value]) }
                        ?? i18n.resolve("admin.users.list.empty"),
                    selectedId: selectedUserId,
                    onSelect: onSelect,
                    pagination: onPageChange.map {
                        AdminPagination(
                            i18n: i18n,
                            limit: limit,
                            offset: offset,
                            total: totalResults ?? users.count,
                            onChange: $0
                        )
                    },
                    row: { user in
                        HStack(spacing: 12) {
                            AdminAvatar(name: user.resolvedName, size: 28)
                            AdminRowLabel(title: user.resolvedName, details: [user.type, user.ouHandle ?? user.ouId])
                        }
                    },
                    i18n: i18n
                )
            }
        )
    }
}

public extension BaseUserList where Content == EmptyView {
    init(
        users: [ManagedUser],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedUserId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((ManagedUser) -> Void)? = nil,
        search: AdminSearch? = nil,
        searchAttributes: [AdminOption] = [],
        onSearch: ((AdminSearch?) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            users: users,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedUserId: selectedUserId,
            onPageChange: onPageChange,
            onSelect: onSelect,
            search: search,
            searchAttributes: searchAttributes,
            onSearch: onSearch,
            actions: actions,
            renderContent: nil
        )
    }
}

/// A paginated list of the users the signed-in user can see. Selecting a row calls `onSelect`;
/// the application decides where that leads.
public struct UserList<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    let filter: String?
    let limit: Int
    let title: String?
    let description: String?
    let selectedUserId: String?
    let onSelect: ((ManagedUser) -> Void)?
    let searchable: Bool
    let searchAttributes: [AdminOption]?
    let actions: AnyView?
    @State private var offset = 0
    @State private var search: AdminSearch?

    let content: ((AdminListState<ManagedUser>) -> Content)?

    init(
        filter: String? = nil,
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedUserId: String? = nil,
        onSelect: ((ManagedUser) -> Void)? = nil,
        searchable: Bool = true,
        searchAttributes: [AdminOption]? = nil,
        actions: AnyView? = nil,
        renderContent: ((AdminListState<ManagedUser>) -> Content)?
    ) {
        self.filter = filter
        self.limit = limit
        self.title = title
        self.description = description
        self.selectedUserId = selectedUserId
        self.onSelect = onSelect
        self.searchable = searchable
        self.searchAttributes = searchAttributes
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default list. See ``BaseUserList``.
    public init(
        filter: String? = nil,
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedUserId: String? = nil,
        onSelect: ((ManagedUser) -> Void)? = nil,
        searchable: Bool = true,
        searchAttributes: [AdminOption]? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AdminListState<ManagedUser>) -> Content
    ) {
        self.init(
            filter: filter,
            limit: limit,
            title: title,
            description: description,
            selectedUserId: selectedUserId,
            onSelect: onSelect,
            searchable: searchable,
            searchAttributes: searchAttributes,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        let state = thunderState
        let activeFilter = filter
            ?? search.flatMap { ManagementFilter.equality(attribute: $0.attribute, value: $0.value) }
        AdminQueryReader(state.usersQuery(limit: limit, offset: offset, filter: activeFilter)) { query in
            BaseUserList(
                users: query.data?.users ?? [],
                isLoading: query.isLoading,
                error: i18n.managementErrorMessage(query.error, fallbackKey: "admin.users.list.error"),
                title: title,
                description: description,
                limit: limit,
                offset: offset,
                totalResults: query.data?.totalResults,
                selectedUserId: selectedUserId,
                onPageChange: { offset = $0 },
                onSelect: onSelect,
                search: search,
                searchAttributes: searchAttributes ?? defaultSearchAttributes,
                onSearch: searchable && filter == nil
                    ? { next in
                        search = next
                        offset = 0
                    }
                    : nil,
                actions: actions,
                renderContent: content
            )
        }
        .id("\(offset)|\(limit)|\(activeFilter ?? "")")
    }

    private var defaultSearchAttributes: [AdminOption] {
        [
            AdminOption(label: i18n.resolve("admin.users.list.search.username"), value: "username"),
            AdminOption(label: i18n.resolve("admin.users.list.search.email"), value: "email")
        ]
    }
}
public extension UserList where Content == EmptyView {
    init(
        filter: String? = nil,
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedUserId: String? = nil,
        onSelect: ((ManagedUser) -> Void)? = nil,
        searchable: Bool = true,
        searchAttributes: [AdminOption]? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            filter: filter,
            limit: limit,
            title: title,
            description: description,
            selectedUserId: selectedUserId,
            onSelect: onSelect,
            searchable: searchable,
            searchAttributes: searchAttributes,
            actions: actions,
            renderContent: nil
        )
    }
}
