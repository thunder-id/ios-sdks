// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A page of roles, rendered from the data it is given. Pair it with
/// ``ThunderIDState/rolesQuery(limit:offset:fetcher:)`` or any other source; ``RoleList`` does that for you.
public struct BaseRoleList<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let roles: [RoleSummary]
    let isLoading: Bool
    let error: String?
    let title: String?
    let description: String?
    let limit: Int
    let offset: Int
    let totalResults: Int?
    let selectedRoleId: String?
    let onPageChange: ((Int) -> Void)?
    let onSelect: ((RoleSummary) -> Void)?
    let actions: AnyView?
    let content: ((AdminListState<RoleSummary>) -> Content)?

    init(
        roles: [RoleSummary],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedRoleId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((RoleSummary) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((AdminListState<RoleSummary>) -> Content)?
    ) {
        self.roles = roles
        self.isLoading = isLoading
        self.error = error
        self.title = title
        self.description = description
        self.limit = limit
        self.offset = offset
        self.totalResults = totalResults
        self.selectedRoleId = selectedRoleId
        self.onPageChange = onPageChange
        self.onSelect = onSelect
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default list, from the roles, the loading and error
    ///   state, and the pagination and selection handlers.
    public init(
        roles: [RoleSummary],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedRoleId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((RoleSummary) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AdminListState<RoleSummary>) -> Content
    ) {
        self.init(
            roles: roles,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedRoleId: selectedRoleId,
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

    private var renderState: AdminListState<RoleSummary> {
        AdminListState(
            rows: roles,
            isLoading: isLoading,
            error: error,
            limit: limit,
            offset: offset,
            totalResults: totalResults ?? roles.count,
            selectedId: selectedRoleId,
            onPageChange: onPageChange,
            onSelect: onSelect,
            search: nil,
            searchAttributes: [],
            onSearch: nil
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        AdminSection(
            identifier: "admin-role-list",
            title: title ?? i18n.resolve("admin.roles.list.title"),
            description: description,
            actions: { actions },
            content: {
                AdminTable(
                    identifier: "admin-role-list",
                    rows: roles,
                    rowId: \.id,
                    isLoading: isLoading,
                    error: error,
                    emptyText: i18n.resolve("admin.roles.list.empty"),
                    selectedId: selectedRoleId,
                    onSelect: onSelect,
                    pagination: onPageChange.map {
                        AdminPagination(
                            i18n: i18n,
                            limit: limit,
                            offset: offset,
                            total: totalResults ?? roles.count,
                            onChange: $0
                        )
                    },
                    row: { role in
                        AdminRowLabel(
                            title: role.name,
                            details: [role.description ?? "", role.ouHandle ?? role.ouId]
                        )
                    },
                    i18n: i18n
                )
            }
        )
    }
}

public extension BaseRoleList where Content == EmptyView {
    init(
        roles: [RoleSummary],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedRoleId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((RoleSummary) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            roles: roles,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedRoleId: selectedRoleId,
            onPageChange: onPageChange,
            onSelect: onSelect,
            actions: actions,
            renderContent: nil
        )
    }
}

/// A paginated list of the roles the signed-in user can see. Selecting a row calls `onSelect`;
/// the application decides where that leads.
public struct RoleList<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    let limit: Int
    let title: String?
    let description: String?
    let selectedRoleId: String?
    let onSelect: ((RoleSummary) -> Void)?
    let actions: AnyView?
    @State private var offset = 0

    let content: ((AdminListState<RoleSummary>) -> Content)?

    init(
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedRoleId: String? = nil,
        onSelect: ((RoleSummary) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((AdminListState<RoleSummary>) -> Content)?
    ) {
        self.limit = limit
        self.title = title
        self.description = description
        self.selectedRoleId = selectedRoleId
        self.onSelect = onSelect
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default list. See ``BaseRoleList``.
    public init(
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedRoleId: String? = nil,
        onSelect: ((RoleSummary) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AdminListState<RoleSummary>) -> Content
    ) {
        self.init(
            limit: limit,
            title: title,
            description: description,
            selectedRoleId: selectedRoleId,
            onSelect: onSelect,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        let state = thunderState
        AdminQueryReader(state.rolesQuery(limit: limit, offset: offset)) { query in
            BaseRoleList(
                roles: query.data?.roles ?? [],
                isLoading: query.isLoading,
                error: i18n.managementErrorMessage(query.error, fallbackKey: "admin.roles.list.error"),
                title: title,
                description: description,
                limit: limit,
                offset: offset,
                totalResults: query.data?.totalResults,
                selectedRoleId: selectedRoleId,
                onPageChange: { offset = $0 },
                onSelect: onSelect,
                actions: actions,
                renderContent: content
            )
        }
        .id("\(offset)|\(limit)")
    }
}

public extension RoleList where Content == EmptyView {
    init(
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedRoleId: String? = nil,
        onSelect: ((RoleSummary) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            limit: limit,
            title: title,
            description: description,
            selectedRoleId: selectedRoleId,
            onSelect: onSelect,
            actions: actions,
            renderContent: nil
        )
    }
}
