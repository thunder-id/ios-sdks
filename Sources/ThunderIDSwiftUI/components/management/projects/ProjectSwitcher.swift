// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Projects rendered from the data it is given, with the current one marked. Choosing another calls
/// `onSelect`; `onClear`, when set, offers to clear the choice.
public struct BaseProjectSwitcher<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let renderState: ProjectSwitcherState
    let content: ((ProjectSwitcherState) -> Content)?

    init(state: ProjectSwitcherState, renderContent: ((ProjectSwitcherState) -> Content)?) {
        self.renderState = state
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view, from the projects, the current
    ///   one, the loading and error state, the paging, `onSelect` and `onClear`.
    public init(
        projects: [Project],
        currentId: String?,
        isLoading: Bool = false,
        error: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onClear: (() -> Void)? = nil,
        onSelect: @escaping (Project) -> Void,
        @ViewBuilder content: @escaping (ProjectSwitcherState) -> Content
    ) {
        self.init(
            state: ProjectSwitcherState(
                projects: projects,
                currentId: currentId,
                isLoading: isLoading,
                error: error,
                limit: limit,
                offset: offset,
                totalResults: totalResults ?? projects.count,
                onPageChange: onPageChange,
                onSelect: onSelect,
                onClear: onClear
            ),
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

    private var defaultBody: some View {
        let state = renderState
        return AdminSection(
            identifier: "admin-project-switcher",
            title: i18n.resolve("admin.projects.list.title"),
            actions: {
                if let onClear = state.onClear, state.currentId != nil {
                    Button(i18n.resolve("admin.projects.switcher.clear"), action: onClear)
                        .accessibilityIdentifier("admin-project-switcher-clear")
                }
            },
            content: {
                AdminTable(
                    identifier: "admin-project-switcher",
                    rows: state.projects,
                    rowId: \.id,
                    isLoading: state.isLoading,
                    error: state.error,
                    emptyText: i18n.resolve("admin.projects.list.empty"),
                    selectedId: state.currentId,
                    onSelect: state.onSelect,
                    pagination: state.onPageChange.map {
                        AdminPagination(
                            i18n: i18n,
                            limit: state.limit,
                            offset: state.offset,
                            total: state.totalResults,
                            onChange: $0
                        )
                    },
                    row: { project in row(project, isCurrent: project.id == state.currentId) },
                    i18n: i18n
                )
            }
        )
    }

    private func row(_ project: Project, isCurrent: Bool) -> some View {
        HStack {
            AdminRowLabel(title: project.displayName, details: [project.handle])
            Spacer(minLength: 8)
            if isCurrent {
                Text(i18n.resolve("admin.projects.switcher.current"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: "checkmark").accessibilityHidden(true)
            }
        }
    }
}

public extension BaseProjectSwitcher where Content == EmptyView {
    init(
        projects: [Project],
        currentId: String?,
        isLoading: Bool = false,
        error: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onClear: (() -> Void)? = nil,
        onSelect: @escaping (Project) -> Void
    ) {
        self.init(
            state: ProjectSwitcherState(
                projects: projects,
                currentId: currentId,
                isLoading: isLoading,
                error: error,
                limit: limit,
                offset: offset,
                totalResults: totalResults ?? projects.count,
                onPageChange: onPageChange,
                onSelect: onSelect,
                onClear: onClear
            ),
            renderContent: nil
        )
    }
}

/// Lists the projects and lets the user pick the current one. This is client-side context, not a
/// sign-in: choosing a project sets ``ThunderIDState/currentProject`` (kept per vendor for the next
/// launch), then calls `onSelect`. A project is not an organization unit: only applications and agents
/// take one. ``ApplicationList`` and ``AgentList`` list the current project's applications and agents,
/// and ``ApplicationCreate`` and ``AgentCreate`` given no organization unit create in it. Other lists and
/// creates are not affected. Only the Control Plane serves projects.
public struct ProjectSwitcher<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    let limit: Int
    let onSelect: ((Project) -> Void)?
    let content: ((ProjectSwitcherState) -> Content)?
    @State private var offset = 0

    init(limit: Int = 20, onSelect: ((Project) -> Void)? = nil, renderContent: ((ProjectSwitcherState) -> Content)?) {
        self.limit = limit
        self.onSelect = onSelect
        self.content = renderContent
    }

    /// - Parameters:
    ///   - onSelect: Called with the project once it is the current one.
    ///   - content: Renders custom UI in place of the default view. See ``BaseProjectSwitcher``.
    public init(
        limit: Int = 20,
        onSelect: ((Project) -> Void)? = nil,
        @ViewBuilder content: @escaping (ProjectSwitcherState) -> Content
    ) {
        self.init(limit: limit, onSelect: onSelect, renderContent: content)
    }

    public var body: some View {
        let state = thunderState
        AdminQueryReader(state.projectsQuery(limit: limit, offset: offset)) { query in
            BaseProjectSwitcher(
                state: ProjectSwitcherState(
                    projects: query.data?.projects ?? [],
                    currentId: state.currentProject?.id,
                    isLoading: query.isLoading,
                    error: i18n.managementErrorMessage(query.error, fallbackKey: "admin.projects.list.error"),
                    limit: limit,
                    offset: offset,
                    totalResults: query.data?.totalResults ?? query.data?.projects.count ?? 0,
                    onPageChange: { offset = $0 },
                    onSelect: { project in
                        state.setCurrentProject(project)
                        onSelect?(project)
                    },
                    onClear: { state.setCurrentProject(nil) }
                ),
                renderContent: content
            )
        }
        .id("\(offset)|\(limit)")
    }
}

public extension ProjectSwitcher where Content == EmptyView {
    init(limit: Int = 20, onSelect: ((Project) -> Void)? = nil) {
        self.init(limit: limit, onSelect: onSelect, renderContent: nil)
    }
}
