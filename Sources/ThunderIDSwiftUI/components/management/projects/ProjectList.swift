// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A page of projects, rendered from the data it is given. Pair it with
/// ``ThunderIDState/projectsQuery(limit:offset:fetcher:)`` or any other source; ``ProjectList`` does that
/// for you.
public struct BaseProjectList<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let projects: [Project]
    let isLoading: Bool
    let error: String?
    let title: String?
    let description: String?
    let limit: Int
    let offset: Int
    let totalResults: Int?
    let selectedProjectId: String?
    let onPageChange: ((Int) -> Void)?
    let onSelect: ((Project) -> Void)?
    let actions: AnyView?
    let content: ((AdminListState<Project>) -> Content)?

    init(
        projects: [Project],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedProjectId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((Project) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((AdminListState<Project>) -> Content)?
    ) {
        self.projects = projects
        self.isLoading = isLoading
        self.error = error
        self.title = title
        self.description = description
        self.limit = limit
        self.offset = offset
        self.totalResults = totalResults
        self.selectedProjectId = selectedProjectId
        self.onPageChange = onPageChange
        self.onSelect = onSelect
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default list, from the projects, the loading
    ///   and error state, and the pagination and selection handlers.
    public init(
        projects: [Project],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedProjectId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((Project) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AdminListState<Project>) -> Content
    ) {
        self.init(
            projects: projects,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedProjectId: selectedProjectId,
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

    private var renderState: AdminListState<Project> {
        AdminListState(
            rows: projects,
            isLoading: isLoading,
            error: error,
            limit: limit,
            offset: offset,
            totalResults: totalResults ?? projects.count,
            selectedId: selectedProjectId,
            onPageChange: onPageChange,
            onSelect: onSelect,
            search: nil,
            searchAttributes: [],
            onSearch: nil
        )
    }

    private var defaultBody: some View {
        AdminSection(
            identifier: "admin-project-list",
            title: title ?? i18n.resolve("admin.projects.list.title"),
            description: description,
            actions: { actions },
            content: {
                AdminTable(
                    identifier: "admin-project-list",
                    rows: projects,
                    rowId: \.id,
                    isLoading: isLoading,
                    error: error,
                    emptyText: i18n.resolve("admin.projects.list.empty"),
                    selectedId: selectedProjectId,
                    onSelect: onSelect,
                    pagination: onPageChange.map {
                        AdminPagination(
                            i18n: i18n,
                            limit: limit,
                            offset: offset,
                            total: totalResults ?? projects.count,
                            onChange: $0
                        )
                    },
                    row: { project in
                        AdminRowLabel(title: project.displayName, details: [project.handle, project.description ?? ""])
                    },
                    i18n: i18n
                )
            }
        )
    }
}

public extension BaseProjectList where Content == EmptyView {
    init(
        projects: [Project],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedProjectId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((Project) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            projects: projects,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedProjectId: selectedProjectId,
            onPageChange: onPageChange,
            onSelect: onSelect,
            actions: actions,
            renderContent: nil
        )
    }
}

/// A paginated list of projects. Selecting a row calls `onSelect`; the application decides where that
/// leads. Only the Control Plane serves projects.
public struct ProjectList<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    let limit: Int
    let title: String?
    let description: String?
    let selectedProjectId: String?
    let onSelect: ((Project) -> Void)?
    let actions: AnyView?
    let content: ((AdminListState<Project>) -> Content)?
    @State private var offset = 0

    init(
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedProjectId: String? = nil,
        onSelect: ((Project) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((AdminListState<Project>) -> Content)?
    ) {
        self.limit = limit
        self.title = title
        self.description = description
        self.selectedProjectId = selectedProjectId
        self.onSelect = onSelect
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default list. See ``BaseProjectList``.
    public init(
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedProjectId: String? = nil,
        onSelect: ((Project) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AdminListState<Project>) -> Content
    ) {
        self.init(
            limit: limit,
            title: title,
            description: description,
            selectedProjectId: selectedProjectId,
            onSelect: onSelect,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        let state = thunderState
        AdminQueryReader(state.projectsQuery(limit: limit, offset: offset)) { query in
            BaseProjectList(
                projects: query.data?.projects ?? [],
                isLoading: query.isLoading,
                error: i18n.managementErrorMessage(query.error, fallbackKey: "admin.projects.list.error"),
                title: title,
                description: description,
                limit: limit,
                offset: offset,
                totalResults: query.data?.totalResults,
                selectedProjectId: selectedProjectId,
                onPageChange: { offset = $0 },
                onSelect: onSelect,
                actions: actions,
                renderContent: content
            )
        }
        .id("\(offset)|\(limit)")
    }
}

public extension ProjectList where Content == EmptyView {
    init(
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedProjectId: String? = nil,
        onSelect: ((Project) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            limit: limit,
            title: title,
            description: description,
            selectedProjectId: selectedProjectId,
            onSelect: onSelect,
            actions: actions,
            renderContent: nil
        )
    }
}
