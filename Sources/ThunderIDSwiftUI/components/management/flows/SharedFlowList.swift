// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Which of an organization unit's flows ``SharedFlowList`` lists.
public enum SharedFlowOwnership: String, CaseIterable {
    /// The flows the unit owns and the ones shared with it.
    case all
    /// The flows the unit owns.
    case owned
    /// The flows shared with the unit.
    case shared
}

/// One page of flows narrowed to an ownership. The server reports the ownership of each flow, so a narrowed
/// list reads the first page of at most ``fetchLimit`` flows and pages through the matches here.
struct SharedFlowPage {
    static let fetchLimit = 100

    let flows: [ManagedFlow]
    let totalResults: Int?

    init(response: ManagedFlowListResponse?, ownership: SharedFlowOwnership, limit: Int, offset: Int) {
        guard ownership != .all else {
            flows = response?.flows ?? []
            totalResults = response?.totalResults
            return
        }
        let owned = ownership == .owned
        let matching = (response?.flows ?? []).filter { $0.isOwnedByOU == owned }
        flows = Array(matching.dropFirst(offset).prefix(limit))
        totalResults = matching.count
    }
}

/// A page of flows with their handle and type, rendered from the data it is given. Pair it with
/// ``ThunderIDState/flowsQuery(flowType:ouId:limit:offset:fetcher:)`` or any other source; ``SharedFlowList``
/// does that for you.
public struct BaseSharedFlowList<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let flows: [ManagedFlow]
    let isLoading: Bool
    let error: String?
    let title: String?
    let description: String?
    let limit: Int
    let offset: Int
    let totalResults: Int?
    let selectedFlowId: String?
    let onPageChange: ((Int) -> Void)?
    let onSelect: ((ManagedFlow) -> Void)?
    let actions: AnyView?
    let content: ((AdminListState<ManagedFlow>) -> Content)?

    init(
        flows: [ManagedFlow],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedFlowId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((ManagedFlow) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((AdminListState<ManagedFlow>) -> Content)?
    ) {
        self.flows = flows
        self.isLoading = isLoading
        self.error = error
        self.title = title
        self.description = description
        self.limit = limit
        self.offset = offset
        self.totalResults = totalResults
        self.selectedFlowId = selectedFlowId
        self.onPageChange = onPageChange
        self.onSelect = onSelect
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default list, from the flows, the loading and
    ///   error state, and the pagination and selection handlers.
    public init(
        flows: [ManagedFlow],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedFlowId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((ManagedFlow) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AdminListState<ManagedFlow>) -> Content
    ) {
        self.init(
            flows: flows,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedFlowId: selectedFlowId,
            onPageChange: onPageChange,
            onSelect: onSelect,
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

    private var renderState: AdminListState<ManagedFlow> {
        AdminListState(
            rows: flows,
            isLoading: isLoading,
            error: error,
            limit: limit,
            offset: offset,
            totalResults: totalResults ?? flows.count,
            selectedId: selectedFlowId,
            onPageChange: onPageChange,
            onSelect: onSelect,
            search: nil,
            searchAttributes: [],
            onSearch: nil
        )
    }

    private var defaultBody: some View {
        AdminSection(
            identifier: "admin-shared-flow-list",
            title: title ?? i18n.resolve("admin.flows.list.title"),
            description: description,
            actions: { actions },
            content: {
                AdminTable(
                    identifier: "admin-shared-flow-list",
                    rows: flows,
                    rowId: \.id,
                    isLoading: isLoading,
                    error: error,
                    emptyText: i18n.resolve("admin.flows.list.empty"),
                    selectedId: selectedFlowId,
                    onSelect: onSelect,
                    pagination: onPageChange.map {
                        AdminPagination(
                            i18n: i18n,
                            limit: limit,
                            offset: offset,
                            total: totalResults ?? flows.count,
                            onChange: $0
                        )
                    },
                    row: { flow in
                        AdminRowLabel(
                            title: flow.name ?? flow.handle,
                            details: [flow.name == nil ? "" : flow.handle, flow.flowType]
                        )
                    },
                    i18n: i18n
                )
            }
        )
    }
}

public extension BaseSharedFlowList where Content == EmptyView {
    init(
        flows: [ManagedFlow],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedFlowId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((ManagedFlow) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            flows: flows,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedFlowId: selectedFlowId,
            onPageChange: onPageChange,
            onSelect: onSelect,
            actions: actions,
            renderContent: nil
        )
    }
}

/// The flows shared with an organization unit, or the ones it owns, or both, a page at a time. Choosing a
/// flow calls `onSelect`, so the application decides what to open, for example ``FlowVariablesForm`` for it.
public struct SharedFlowList<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    let ouId: String
    let ownership: SharedFlowOwnership
    let flowType: String?
    let limit: Int
    let title: String?
    let description: String?
    let selectedFlowId: String?
    let onSelect: ((ManagedFlow) -> Void)?
    let actions: AnyView?
    let content: ((AdminListState<ManagedFlow>) -> Content)?
    @State private var offset = 0

    init(
        ouId: String,
        ownership: SharedFlowOwnership = .shared,
        flowType: String? = nil,
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedFlowId: String? = nil,
        onSelect: ((ManagedFlow) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((AdminListState<ManagedFlow>) -> Content)?
    ) {
        self.ouId = ouId
        self.ownership = ownership
        self.flowType = flowType
        self.limit = limit
        self.title = title
        self.description = description
        self.selectedFlowId = selectedFlowId
        self.onSelect = onSelect
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameters:
    ///   - ouId: The organization unit to list the flows of.
    ///   - ownership: Which of its flows to list. The shared ones by default; `.all` pages on the server.
    ///   - flowType: Only flows of this type, such as `AUTHENTICATION`.
    ///   - content: Renders custom UI in place of the default list. See ``BaseSharedFlowList``.
    public init(
        ouId: String,
        ownership: SharedFlowOwnership = .shared,
        flowType: String? = nil,
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedFlowId: String? = nil,
        onSelect: ((ManagedFlow) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AdminListState<ManagedFlow>) -> Content
    ) {
        self.init(
            ouId: ouId,
            ownership: ownership,
            flowType: flowType,
            limit: limit,
            title: title,
            description: description,
            selectedFlowId: selectedFlowId,
            onSelect: onSelect,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        let state = thunderState
        let narrowed = ownership != .all
        let fetchLimit = narrowed ? SharedFlowPage.fetchLimit : limit
        let fetchOffset = narrowed ? 0 : offset
        AdminQueryReader(
            state.flowsQuery(flowType: flowType, ouId: ouId, limit: fetchLimit, offset: fetchOffset)
        ) { query in
            let page = SharedFlowPage(response: query.data, ownership: ownership, limit: limit, offset: offset)
            BaseSharedFlowList(
                flows: page.flows,
                isLoading: query.isLoading,
                error: i18n.managementErrorMessage(query.error, fallbackKey: "admin.flows.list.error"),
                title: title,
                description: description,
                limit: limit,
                offset: offset,
                totalResults: page.totalResults,
                selectedFlowId: selectedFlowId,
                onPageChange: { offset = $0 },
                onSelect: onSelect,
                actions: actions,
                renderContent: content
            )
        }
        .id("\(ouId)|\(flowType ?? "")|\(ownership.rawValue)|\(fetchOffset)|\(fetchLimit)")
    }
}

public extension SharedFlowList where Content == EmptyView {
    init(
        ouId: String,
        ownership: SharedFlowOwnership = .shared,
        flowType: String? = nil,
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedFlowId: String? = nil,
        onSelect: ((ManagedFlow) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            ouId: ouId,
            ownership: ownership,
            flowType: flowType,
            limit: limit,
            title: title,
            description: description,
            selectedFlowId: selectedFlowId,
            onSelect: onSelect,
            actions: actions,
            renderContent: nil
        )
    }
}
