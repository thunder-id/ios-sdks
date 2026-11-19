// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// What ``BasePersonalAgentList`` hands its `content` closure, so the agents can be shown with any UI.
public struct PersonalAgentListState {
    public let agents: [BasicAgent]
    public let isLoading: Bool
    /// A translated message, or `nil` when there is nothing to report.
    public let error: String?
    public let limit: Int
    public let offset: Int
    /// The total on the server, or the number of agents given when it is unknown.
    public let totalResults: Int
    public let selectedId: String?
    /// Shows the page that starts at the given offset. `nil` when the list is not paginated.
    public let onPageChange: ((Int) -> Void)?
    /// Chooses an agent. `nil` when agents are not selectable.
    public let onSelect: ((BasicAgent) -> Void)?
    /// Why the last suspend-all request failed, already translated.
    public let actionError: String?
    public let isSuspendingAll: Bool
    /// Suspends every personal agent of the signed-in user. Ask for confirmation first. `nil` when not
    /// allowed, or when there are none.
    public let onSuspendAll: (() -> Void)?
    /// How many agents the last suspend-all request suspended, until another page is shown.
    public let suspendedCount: Int?
}

/// The signed-in user's personal agents with their client and status, rendered from the data it is given.
/// Suspending them all is offered only when `onSuspendAll` is set, and asks for confirmation first.
/// ``PersonalAgentList`` loads the data for you.
public struct BasePersonalAgentList<Content: View>: View {
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
    let actionError: String?
    let isSuspendingAll: Bool
    let onSuspendAll: (() -> Void)?
    let suspendedCount: Int?
    let actions: AnyView?
    let content: ((PersonalAgentListState) -> Content)?

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
        actionError: String? = nil,
        isSuspendingAll: Bool = false,
        onSuspendAll: (() -> Void)? = nil,
        suspendedCount: Int? = nil,
        actions: AnyView? = nil,
        renderContent: ((PersonalAgentListState) -> Content)?
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
        self.actionError = actionError
        self.isSuspendingAll = isSuspendingAll
        self.onSuspendAll = onSuspendAll
        self.suspendedCount = suspendedCount
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default list, from the agents, the loading and
    ///   error state, the pagination and selection handlers, and the suspend-all action when it is allowed.
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
        actionError: String? = nil,
        isSuspendingAll: Bool = false,
        onSuspendAll: (() -> Void)? = nil,
        suspendedCount: Int? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (PersonalAgentListState) -> Content
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
            actionError: actionError,
            isSuspendingAll: isSuspendingAll,
            onSuspendAll: onSuspendAll,
            suspendedCount: suspendedCount,
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

    private var canSuspendAll: Bool { onSuspendAll != nil && !agents.isEmpty }

    private var renderState: PersonalAgentListState {
        PersonalAgentListState(
            agents: agents,
            isLoading: isLoading,
            error: error,
            limit: limit,
            offset: offset,
            totalResults: totalResults ?? agents.count,
            selectedId: selectedAgentId,
            onPageChange: onPageChange,
            onSelect: onSelect,
            actionError: actionError,
            isSuspendingAll: isSuspendingAll,
            onSuspendAll: canSuspendAll ? onSuspendAll : nil,
            suspendedCount: suspendedCount
        )
    }

    private var defaultBody: some View {
        AdminSection(
            identifier: "personal-agent-list",
            title: title ?? i18n.resolve("user.agents.title"),
            description: description ?? i18n.resolve("user.agents.description"),
            actions: {
                HStack(spacing: 8) {
                    actions
                    if let onSuspendAll, canSuspendAll {
                        AdminConfirmButton(
                            i18n: i18n,
                            title: i18n.resolve("user.agents.suspend_all.action"),
                            confirmText: i18n.resolve("user.agents.suspend_all.confirm"),
                            isLoading: isSuspendingAll,
                            identifier: "personal-agent-list-suspend-all",
                            onConfirm: onSuspendAll
                        )
                    }
                }
            },
            content: {
                if let actionError {
                    AdminErrorBanner(message: actionError)
                }
                if let suspendedCount {
                    FlowNoticeBanner(
                        message: i18n.resolve("user.agents.suspend_all.done", ["count": String(suspendedCount)])
                    )
                    .accessibilityIdentifier("personal-agent-list-suspended")
                }
                table
            }
        )
    }

    private var table: some View {
        AdminTable(
            identifier: "personal-agent-list",
            rows: agents,
            rowId: \.id,
            isLoading: isLoading,
            error: error,
            emptyText: i18n.resolve("user.agents.list.empty"),
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
                HStack(alignment: .center, spacing: 8) {
                    AdminRowLabel(title: agent.resolvedName, details: [agent.clientId ?? ""])
                    Spacer(minLength: 8)
                    AccessStatusBadge(i18n: i18n, status: agent.status?.value)
                }
            },
            i18n: i18n
        )
    }
}

public extension BasePersonalAgentList where Content == EmptyView {
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
        actionError: String? = nil,
        isSuspendingAll: Bool = false,
        onSuspendAll: (() -> Void)? = nil,
        suspendedCount: Int? = nil,
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
            actionError: actionError,
            isSuspendingAll: isSuspendingAll,
            onSuspendAll: onSuspendAll,
            suspendedCount: suspendedCount,
            actions: actions,
            renderContent: nil
        )
    }
}

/// The signed-in user's personal agents, a page at a time, through `/users/me/agents`. Pair it with
/// ``PersonalAgentDetails`` to show the agent the user chooses. Set `suspendable` to let the user suspend
/// all their personal agents at once; it is off by default, and asks for confirmation first.
public struct PersonalAgentList<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let limit: Int
    let title: String?
    let description: String?
    let selectedAgentId: String?
    let onSelect: ((BasicAgent) -> Void)?
    let suspendable: Bool
    let actions: AnyView?
    let content: ((PersonalAgentListState) -> Content)?
    @State private var offset = 0

    init(
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedAgentId: String? = nil,
        onSelect: ((BasicAgent) -> Void)? = nil,
        suspendable: Bool = false,
        actions: AnyView? = nil,
        renderContent: ((PersonalAgentListState) -> Content)?
    ) {
        self.limit = limit
        self.title = title
        self.description = description
        self.selectedAgentId = selectedAgentId
        self.onSelect = onSelect
        self.suspendable = suspendable
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default list. See ``BasePersonalAgentList``.
    public init(
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedAgentId: String? = nil,
        onSelect: ((BasicAgent) -> Void)? = nil,
        suspendable: Bool = false,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (PersonalAgentListState) -> Content
    ) {
        self.init(
            limit: limit,
            title: title,
            description: description,
            selectedAgentId: selectedAgentId,
            onSelect: onSelect,
            suspendable: suspendable,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        PersonalAgentListHost(state: thunderState, props: self, offset: $offset)
            .id("\(offset)|\(limit)")
    }
}

public extension PersonalAgentList where Content == EmptyView {
    init(
        limit: Int = 20,
        title: String? = nil,
        description: String? = nil,
        selectedAgentId: String? = nil,
        onSelect: ((BasicAgent) -> Void)? = nil,
        suspendable: Bool = false,
        actions: AnyView? = nil
    ) {
        self.init(
            limit: limit,
            title: title,
            description: description,
            selectedAgentId: selectedAgentId,
            onSelect: onSelect,
            suspendable: suspendable,
            actions: actions,
            renderContent: nil
        )
    }
}

private struct PersonalAgentListHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var agents: ResourceQuery<AgentListResponse>
    @StateObject private var suspendAll: ResourceMutation<Void, SuspendAllMeAgentsResponse>
    let props: PersonalAgentList<Content>
    @Binding var offset: Int

    init(state: ThunderIDState, props: PersonalAgentList<Content>, offset: Binding<Int>) {
        _agents = StateObject(
            wrappedValue: state.meAgentsQuery(kind: .personal, limit: props.limit, offset: offset.wrappedValue)
        )
        _suspendAll = StateObject(wrappedValue: state.suspendAllMeAgentsMutation())
        self.props = props
        _offset = offset
    }

    var body: some View {
        BasePersonalAgentList(
            agents: agents.data?.agents ?? [],
            isLoading: agents.isLoading,
            error: i18n.managementErrorMessage(agents.error, fallbackKey: "user.agents.list.error"),
            title: props.title,
            description: props.description,
            limit: props.limit,
            offset: offset,
            totalResults: agents.data?.totalResults,
            selectedAgentId: props.selectedAgentId,
            onPageChange: { offset = $0 },
            onSelect: props.onSelect,
            actionError: i18n.managementErrorMessage(suspendAll.error, fallbackKey: "user.agents.action.error"),
            isSuspendingAll: suspendAll.isLoading,
            onSuspendAll: props.suspendable ? { Task { await suspendAll.mutate(()) } } : nil,
            suspendedCount: suspendAll.data?.suspendedCount,
            actions: props.actions,
            renderContent: props.content
        )
        .task { await agents.refetch() }
    }
}
