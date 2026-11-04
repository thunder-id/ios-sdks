// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A page of organization units, rendered from the data it is given. Pair it with
/// ``ThunderIDState/organizationUnitsQuery(parentId:limit:offset:fetcher:)`` or any other source;
/// ``OrganizationUnitList`` does that for you.
public struct BaseOrganizationUnitList<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let units: [OrganizationUnitSummary]
    let isLoading: Bool
    let error: String?
    let title: String?
    let description: String?
    let limit: Int
    let offset: Int
    let totalResults: Int?
    let selectedUnitId: String?
    let onPageChange: ((Int) -> Void)?
    let onSelect: ((OrganizationUnitSummary) -> Void)?
    let actions: AnyView?
    let content: ((AdminListState<OrganizationUnitSummary>) -> Content)?

    init(
        units: [OrganizationUnitSummary],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedUnitId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((OrganizationUnitSummary) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((AdminListState<OrganizationUnitSummary>) -> Content)?
    ) {
        self.units = units
        self.isLoading = isLoading
        self.error = error
        self.title = title
        self.description = description
        self.limit = limit
        self.offset = offset
        self.totalResults = totalResults
        self.selectedUnitId = selectedUnitId
        self.onPageChange = onPageChange
        self.onSelect = onSelect
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default list, from the units, the loading and
    ///   error state, and the pagination and selection handlers.
    public init(
        units: [OrganizationUnitSummary],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedUnitId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((OrganizationUnitSummary) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AdminListState<OrganizationUnitSummary>) -> Content
    ) {
        self.init(
            units: units,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedUnitId: selectedUnitId,
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

    private var renderState: AdminListState<OrganizationUnitSummary> {
        AdminListState(
            rows: units,
            isLoading: isLoading,
            error: error,
            limit: limit,
            offset: offset,
            totalResults: totalResults ?? units.count,
            selectedId: selectedUnitId,
            onPageChange: onPageChange,
            onSelect: onSelect,
            search: nil,
            searchAttributes: [],
            onSearch: nil
        )
    }

    private var defaultBody: some View {
        AdminSection(
            identifier: "admin-organization-unit-list",
            title: title ?? i18n.resolve("admin.organization_units.list.title"),
            description: description,
            actions: { actions },
            content: {
                AdminTable(
                    identifier: "admin-organization-unit-list",
                    rows: units,
                    rowId: \.id,
                    isLoading: isLoading,
                    error: error,
                    emptyText: i18n.resolve("admin.organization_units.list.empty"),
                    selectedId: selectedUnitId,
                    onSelect: onSelect,
                    pagination: onPageChange.map {
                        AdminPagination(
                            i18n: i18n,
                            limit: limit,
                            offset: offset,
                            total: totalResults ?? units.count,
                            onChange: $0
                        )
                    },
                    row: { unit in AdminRowLabel(title: unit.name, details: [unit.handle, unit.description ?? ""]) },
                    i18n: i18n
                )
            }
        )
    }
}

public extension BaseOrganizationUnitList where Content == EmptyView {
    init(
        units: [OrganizationUnitSummary],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedUnitId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((OrganizationUnitSummary) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            units: units,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedUnitId: selectedUnitId,
            onPageChange: onPageChange,
            onSelect: onSelect,
            actions: actions,
            renderContent: nil
        )
    }
}

/// A paginated list of organization units: the root units, or the units directly beneath `parentId`.
/// Selecting a row calls `onSelect`; the application decides where that leads.
public struct OrganizationUnitList<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    let parentId: String?
    let limit: Int
    let title: String?
    let description: String?
    let selectedUnitId: String?
    let onSelect: ((OrganizationUnitSummary) -> Void)?
    let actions: AnyView?
    let content: ((AdminListState<OrganizationUnitSummary>) -> Content)?
    @State private var offset = 0

    init(
        parentId: String? = nil,
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedUnitId: String? = nil,
        onSelect: ((OrganizationUnitSummary) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((AdminListState<OrganizationUnitSummary>) -> Content)?
    ) {
        self.parentId = parentId
        self.limit = limit
        self.title = title
        self.description = description
        self.selectedUnitId = selectedUnitId
        self.onSelect = onSelect
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameters:
    ///   - parentId: Lists the units directly beneath this one instead of the root units.
    ///   - content: Renders custom UI in place of the default list. See ``BaseOrganizationUnitList``.
    public init(
        parentId: String? = nil,
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedUnitId: String? = nil,
        onSelect: ((OrganizationUnitSummary) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AdminListState<OrganizationUnitSummary>) -> Content
    ) {
        self.init(
            parentId: parentId,
            limit: limit,
            title: title,
            description: description,
            selectedUnitId: selectedUnitId,
            onSelect: onSelect,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        let state = thunderState
        AdminQueryReader(state.organizationUnitsQuery(parentId: parentId, limit: limit, offset: offset)) { query in
            BaseOrganizationUnitList(
                units: query.data?.organizationUnits ?? [],
                isLoading: query.isLoading,
                error: i18n.managementErrorMessage(query.error, fallbackKey: "admin.organization_units.list.error"),
                title: title,
                description: description,
                limit: limit,
                offset: offset,
                totalResults: query.data?.totalResults,
                selectedUnitId: selectedUnitId,
                onPageChange: { offset = $0 },
                onSelect: onSelect,
                actions: actions,
                renderContent: content
            )
        }
        .id("\(parentId ?? "")|\(offset)|\(limit)")
    }
}

public extension OrganizationUnitList where Content == EmptyView {
    init(
        parentId: String? = nil,
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedUnitId: String? = nil,
        onSelect: ((OrganizationUnitSummary) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            parentId: parentId,
            limit: limit,
            title: title,
            description: description,
            selectedUnitId: selectedUnitId,
            onSelect: onSelect,
            actions: actions,
            renderContent: nil
        )
    }
}
