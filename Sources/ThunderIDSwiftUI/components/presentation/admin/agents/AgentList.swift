// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A page of agents, rendered from the data it is given. Pair it with
/// ``ThunderIDState/agentsQuery(limit:offset:fetcher:)`` or any other source; ``AgentList`` does that for you.
public struct BaseAgentList<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let agents: [BasicAgent]
    let isLoading: Bool
    let error: String?
    let title: String?
    let description: String?
    let limit: Int
    let offset: Int
    let totalResults: Int?
    let selectedAgentId: String?
    let onPageChange: ((Int) -> Void)?
    let onSelect: ((BasicAgent) -> Void)?
    let search: AdminSearch?
    let searchAttributes: [AdminOption]
    let onSearch: ((AdminSearch?) -> Void)?
    let actions: AnyView?
    let content: ((AdminListState<BasicAgent>) -> Content)?

    init(
        agents: [BasicAgent],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedAgentId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((BasicAgent) -> Void)? = nil,
        search: AdminSearch? = nil,
        searchAttributes: [AdminOption] = [],
        onSearch: ((AdminSearch?) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((AdminListState<BasicAgent>) -> Content)?
    ) {
        self.agents = agents
        self.isLoading = isLoading
        self.error = error
        self.title = title
        self.description = description
        self.limit = limit
        self.offset = offset
        self.totalResults = totalResults
        self.selectedAgentId = selectedAgentId
        self.onPageChange = onPageChange
        self.onSelect = onSelect
        self.search = search
        self.searchAttributes = searchAttributes
        self.onSearch = onSearch
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default list, from the agents, the loading and error
    ///   state, and the pagination and selection handlers.
    public init(
        agents: [BasicAgent],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedAgentId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((BasicAgent) -> Void)? = nil,
        search: AdminSearch? = nil,
        searchAttributes: [AdminOption] = [],
        onSearch: ((AdminSearch?) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AdminListState<BasicAgent>) -> Content
    ) {
        self.init(
            agents: agents,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedAgentId: selectedAgentId,
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

    private var renderState: AdminListState<BasicAgent> {
        AdminListState(
            rows: agents,
            isLoading: isLoading,
            error: error,
            limit: limit,
            offset: offset,
            totalResults: totalResults ?? agents.count,
            selectedId: selectedAgentId,
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
            identifier: "admin-agent-list",
            title: title ?? i18n.resolve("admin.agents.list.title"),
            description: description,
            actions: { actions },
            content: {
                if let onSearch, !searchAttributes.isEmpty {
                    AdminSearchBar(
                        i18n: i18n,
                        identifier: "admin-agent-list",
                        attributes: searchAttributes,
                        search: search,
                        onSearch: onSearch
                    )
                }
                AdminTable(
                    identifier: "admin-agent-list",
                    rows: agents,
                    rowId: \.id,
                    isLoading: isLoading,
                    error: error,
                    emptyText: search.map { i18n.resolve("admin.common.search.no_results", ["value": $0.value]) }
                        ?? i18n.resolve("admin.agents.list.empty"),
                    selectedId: selectedAgentId,
                    onSelect: onSelect,
                    pagination: onPageChange.map {
                        AdminPagination(
                            i18n: i18n,
                            limit: limit,
                            offset: offset,
                            total: totalResults ?? agents.count,
                            onChange: $0
                        )
                    },
                    row: { agent in
                        AdminRowLabel(
                            title: agent.name,
                            details: [agent.type, agent.clientId ?? "", agent.ouHandle ?? agent.ouId]
                        )
                    },
                    i18n: i18n
                )
            }
        )
    }
}

public extension BaseAgentList where Content == EmptyView {
    init(
        agents: [BasicAgent],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedAgentId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((BasicAgent) -> Void)? = nil,
        search: AdminSearch? = nil,
        searchAttributes: [AdminOption] = [],
        onSearch: ((AdminSearch?) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            agents: agents,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedAgentId: selectedAgentId,
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

/// A paginated list of the agents the signed-in user can see. Selecting a row calls `onSelect`;
/// the application decides where that leads.
public struct AgentList<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    let limit: Int
    let title: String?
    let description: String?
    let selectedAgentId: String?
    let onSelect: ((BasicAgent) -> Void)?
    let searchable: Bool
    let searchAttributes: [AdminOption]?
    let actions: AnyView?
    @State private var offset = 0
    @State private var search: AdminSearch?

    let content: ((AdminListState<BasicAgent>) -> Content)?

    init(
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedAgentId: String? = nil,
        onSelect: ((BasicAgent) -> Void)? = nil,
        searchable: Bool = true,
        searchAttributes: [AdminOption]? = nil,
        actions: AnyView? = nil,
        renderContent: ((AdminListState<BasicAgent>) -> Content)?
    ) {
        self.limit = limit
        self.title = title
        self.description = description
        self.selectedAgentId = selectedAgentId
        self.onSelect = onSelect
        self.searchable = searchable
        self.searchAttributes = searchAttributes
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default list. See ``BaseAgentList``.
    public init(
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedAgentId: String? = nil,
        onSelect: ((BasicAgent) -> Void)? = nil,
        searchable: Bool = true,
        searchAttributes: [AdminOption]? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AdminListState<BasicAgent>) -> Content
    ) {
        self.init(
            limit: limit,
            title: title,
            description: description,
            selectedAgentId: selectedAgentId,
            onSelect: onSelect,
            searchable: searchable,
            searchAttributes: searchAttributes,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        let state = thunderState
        let activeFilter = search.flatMap {
            ManagementFilter.equality(attribute: $0.attribute, value: $0.value)
        }
        AdminQueryReader(state.agentsQuery(limit: limit, offset: offset, filter: activeFilter)) { query in
            BaseAgentList(
                agents: query.data?.agents ?? [],
                isLoading: query.isLoading,
                error: i18n.managementErrorMessage(query.error, fallbackKey: "admin.agents.list.error"),
                title: title,
                description: description,
                limit: limit,
                offset: offset,
                totalResults: query.data?.totalResults,
                selectedAgentId: selectedAgentId,
                onPageChange: { offset = $0 },
                onSelect: onSelect,
                search: search,
                searchAttributes: searchAttributes ?? defaultSearchAttributes,
                onSearch: searchable
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
        [AdminOption(label: i18n.resolve("admin.agents.list.search.name"), value: "name")]
    }
}
public extension AgentList where Content == EmptyView {
    init(
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedAgentId: String? = nil,
        onSelect: ((BasicAgent) -> Void)? = nil,
        searchable: Bool = true,
        searchAttributes: [AdminOption]? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            limit: limit,
            title: title,
            description: description,
            selectedAgentId: selectedAgentId,
            onSelect: onSelect,
            searchable: searchable,
            searchAttributes: searchAttributes,
            actions: actions,
            renderContent: nil
        )
    }
}
