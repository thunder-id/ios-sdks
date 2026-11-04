// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A page of applications, rendered from the data it is given. Pair it with
/// ``ThunderIDState/applicationsQuery(limit:offset:projectId:fetcher:)`` or any other source; ``ApplicationList``
/// does that for you. The applications API has no search, so the list has none.
public struct BaseApplicationList<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let applications: [BasicApplication]
    let isLoading: Bool
    let error: String?
    let title: String?
    let description: String?
    let limit: Int
    let offset: Int
    let totalResults: Int?
    let selectedApplicationId: String?
    let onPageChange: ((Int) -> Void)?
    let onSelect: ((BasicApplication) -> Void)?
    let actions: AnyView?
    let content: ((AdminListState<BasicApplication>) -> Content)?

    init(
        applications: [BasicApplication],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedApplicationId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((BasicApplication) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((AdminListState<BasicApplication>) -> Content)?
    ) {
        self.applications = applications
        self.isLoading = isLoading
        self.error = error
        self.title = title
        self.description = description
        self.limit = limit
        self.offset = offset
        self.totalResults = totalResults
        self.selectedApplicationId = selectedApplicationId
        self.onPageChange = onPageChange
        self.onSelect = onSelect
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default list, from the applications, the
    ///   loading and error state, and the pagination and selection handlers.
    public init(
        applications: [BasicApplication],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedApplicationId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((BasicApplication) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AdminListState<BasicApplication>) -> Content
    ) {
        self.init(
            applications: applications,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedApplicationId: selectedApplicationId,
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

    private var renderState: AdminListState<BasicApplication> {
        AdminListState(
            rows: applications,
            isLoading: isLoading,
            error: error,
            limit: limit,
            offset: offset,
            totalResults: totalResults ?? applications.count,
            selectedId: selectedApplicationId,
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
            identifier: "admin-application-list",
            title: title ?? i18n.resolve("admin.applications.list.title"),
            description: description,
            actions: { actions },
            content: {
                AdminTable(
                    identifier: "admin-application-list",
                    rows: applications,
                    rowId: \.id,
                    isLoading: isLoading,
                    error: error,
                    emptyText: i18n.resolve("admin.applications.list.empty"),
                    selectedId: selectedApplicationId,
                    onSelect: onSelect,
                    pagination: onPageChange.map {
                        AdminPagination(
                            i18n: i18n,
                            limit: limit,
                            offset: offset,
                            total: totalResults ?? applications.count,
                            onChange: $0
                        )
                    },
                    row: { application in
                        AdminRowLabel(
                            title: application.name,
                            details: [
                                application.clientId ?? "",
                                application.template ?? application.type ?? "",
                                i18n.applicationStatus(application.status)
                            ]
                        )
                    },
                    i18n: i18n
                )
            }
        )
    }
}

public extension BaseApplicationList where Content == EmptyView {
    init(
        applications: [BasicApplication],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        description: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        selectedApplicationId: String? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSelect: ((BasicApplication) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            applications: applications,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedApplicationId: selectedApplicationId,
            onPageChange: onPageChange,
            onSelect: onSelect,
            actions: actions,
            renderContent: nil
        )
    }
}

/// A paginated list of the applications the signed-in user can see. Selecting a row calls `onSelect`;
/// the application decides where that leads. With `projectId`, or otherwise the current project
/// (``ThunderIDState/currentProject``), it lists the applications the project's root organization unit
/// owns, followed by the applications shared into it.
///
/// The server defines no application-specific permission: applications are guarded by the root
/// `system` permission, for reading and writing alike. A request the token is not allowed to make
/// shows the translated forbidden message.
public struct ApplicationList<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    let limit: Int
    let projectId: String?
    let title: String?
    let description: String?
    let selectedApplicationId: String?
    let onSelect: ((BasicApplication) -> Void)?
    let actions: AnyView?
    @State private var offset = 0

    let content: ((AdminListState<BasicApplication>) -> Content)?

    init(
        limit: Int = 20,
        projectId: String? = nil,
        title: String? = nil,
        description: String? = nil,
        selectedApplicationId: String? = nil,
        onSelect: ((BasicApplication) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((AdminListState<BasicApplication>) -> Content)?
    ) {
        self.limit = limit
        self.projectId = projectId
        self.title = title
        self.description = description
        self.selectedApplicationId = selectedApplicationId
        self.onSelect = onSelect
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default list. See ``BaseApplicationList``.
    public init(
        limit: Int = 20,
        projectId: String? = nil,
        title: String? = nil,
        description: String? = nil,
        selectedApplicationId: String? = nil,
        onSelect: ((BasicApplication) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AdminListState<BasicApplication>) -> Content
    ) {
        self.init(
            limit: limit,
            projectId: projectId,
            title: title,
            description: description,
            selectedApplicationId: selectedApplicationId,
            onSelect: onSelect,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        let scope = projectId ?? thunderState.currentProject?.id
        AdminQueryReader(thunderState.applicationsQuery(limit: limit, offset: offset, projectId: scope)) { query in
            list(
                query.data?.applications ?? [],
                isLoading: query.isLoading,
                error: i18n.managementErrorMessage(query.error, fallbackKey: "admin.applications.list.error"),
                totalResults: query.data?.totalResults
            )
        }
        .id("\(offset)|\(limit)|\(scope ?? "")")
    }

    private func list(
        _ applications: [BasicApplication],
        isLoading: Bool,
        error: String?,
        totalResults: Int?
    ) -> BaseApplicationList<Content> {
        BaseApplicationList(
            applications: applications,
            isLoading: isLoading,
            error: error,
            title: title,
            description: description,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            selectedApplicationId: selectedApplicationId,
            onPageChange: { offset = $0 },
            onSelect: onSelect,
            actions: actions,
            renderContent: content
        )
    }
}

public extension ApplicationList where Content == EmptyView {
    init(
        limit: Int = 20,
        projectId: String? = nil,
        title: String? = nil,
        description: String? = nil,
        selectedApplicationId: String? = nil,
        onSelect: ((BasicApplication) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            limit: limit,
            projectId: projectId,
            title: title,
            description: description,
            selectedApplicationId: selectedApplicationId,
            onSelect: onSelect,
            actions: actions,
            renderContent: nil
        )
    }
}
