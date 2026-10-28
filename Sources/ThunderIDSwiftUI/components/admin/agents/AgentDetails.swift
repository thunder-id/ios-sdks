// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// An agent's overview, access status, groups and roles, rendered from the data it is given. Deleting
/// is offered only when `onDelete` is set, and never for a read-only agent. The account lifecycle
/// actions in `lifecycleActions` (suspend, unsuspend, unlock) are offered only when `onLifecycleAction`
/// is set; they change only runtime state, so they apply to read-only agents too. Suspending and
/// unsuspending ask for confirmation first, and a suspension takes an optional operator note.
public struct BaseAgentDetails<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let agent: Agent?
    let groups: [MembershipGroup]
    let roles: [String]
    let isLoading: Bool
    let error: String?
    let isDeleting: Bool
    let onDelete: (() -> Void)?
    let isRunningLifecycleAction: Bool
    let lifecycleActions: [AccountLifecycleAction]
    let onLifecycleAction: ((AccountLifecycleAction, String?) -> Void)?
    let actions: AnyView?
    let content: ((AgentDetailsState) -> Content)?

    init(
        agent: Agent?,
        groups: [MembershipGroup] = [],
        roles: [String] = [],
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        onDelete: (() -> Void)? = nil,
        isRunningLifecycleAction: Bool = false,
        lifecycleActions: [AccountLifecycleAction] = [],
        onLifecycleAction: ((AccountLifecycleAction, String?) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((AgentDetailsState) -> Content)?
    ) {
        self.agent = agent
        self.groups = groups
        self.roles = roles
        self.isLoading = isLoading
        self.error = error
        self.isDeleting = isDeleting
        self.onDelete = onDelete
        self.isRunningLifecycleAction = isRunningLifecycleAction
        self.lifecycleActions = lifecycleActions
        self.onLifecycleAction = onLifecycleAction
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view, from the agent, its groups and roles,
    ///   the loading and error state, and the delete and lifecycle actions.
    public init(
        agent: Agent?,
        groups: [MembershipGroup] = [],
        roles: [String] = [],
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        onDelete: (() -> Void)? = nil,
        isRunningLifecycleAction: Bool = false,
        lifecycleActions: [AccountLifecycleAction] = [],
        onLifecycleAction: ((AccountLifecycleAction, String?) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AgentDetailsState) -> Content
    ) {
        self.init(
            agent: agent,
            groups: groups,
            roles: roles,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            onDelete: onDelete,
            isRunningLifecycleAction: isRunningLifecycleAction,
            lifecycleActions: lifecycleActions,
            onLifecycleAction: onLifecycleAction,
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

    private var renderState: AgentDetailsState {
        AgentDetailsState(
            agent: agent,
            groups: groups,
            roles: roles,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            onDelete: agent != nil && agent?.isReadOnly != true ? onDelete : nil,
            isRunningLifecycleAction: isRunningLifecycleAction,
            lifecycleActions: onLifecycleAction != nil && agent != nil ? lifecycleActions : [],
            onLifecycleAction: agent != nil ? onLifecycleAction : nil
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        if let agent {
            details(agent)
        } else {
            AdminSection(identifier: "admin-agent-details") {
                if isLoading {
                    AdminLoadingRow(label: i18n.resolve("admin.common.loading"))
                } else {
                    AdminErrorBanner(message: error ?? i18n.resolve("admin.common.errors.not_found"))
                }
            }
        }
    }

    private func details(_ agent: Agent) -> some View {
        var overview: [(label: String, value: String)] = [
            (i18n.resolve("admin.agents.details.type"), agent.type),
            (i18n.resolve("admin.agents.details.owner"), agent.owner ?? i18n.resolve("admin.agents.details.no_owner")),
            (i18n.resolve("admin.common.columns.organization_unit"), agent.ouHandle ?? agent.ouId)
        ]
        if let status = agent.status {
            overview.append((i18n.resolve("admin.common.columns.status"), i18n.accessStatusLabel(status.value)))
        }
        if let clientId = agent.clientId {
            overview.append((i18n.resolve("admin.agents.list.columns.client_id"), clientId))
        }
        return AdminSection(
            identifier: "admin-agent-details",
            title: agent.name,
            description: agent.description,
            actions: { headerActions(agent) },
            content: {
                if let error {
                    AdminErrorBanner(message: error)
                }
                AdminPanel(title: i18n.resolve("admin.agents.details.overview")) {
                    AdminDetailList(items: overview)
                }
                AdminPanel(title: i18n.resolve("admin.agents.details.groups")) {
                    AdminChipList(
                        label: i18n.resolve("admin.agents.details.groups"),
                        emptyText: i18n.resolve("admin.agents.details.no_groups"),
                        items: groups.map { ($0.id, $0.name) }
                    )
                }
                AdminPanel(title: i18n.resolve("admin.agents.details.roles")) {
                    AdminChipList(
                        label: i18n.resolve("admin.agents.details.roles"),
                        emptyText: i18n.resolve("admin.agents.details.no_roles"),
                        items: roles.map { ($0, $0) }
                    )
                }
            }
        )
    }

    private func headerActions(_ agent: Agent) -> some View {
        HStack(spacing: 8) {
            actions
            if let onLifecycleAction {
                AccountLifecycleButtons(
                    i18n: i18n,
                    actions: lifecycleActions,
                    collectsOperatorNote: true,
                    isRunning: isRunningLifecycleAction,
                    name: agent.name,
                    identifier: "admin-agent-details-lifecycle",
                    onAction: onLifecycleAction
                )
            }
            if let onDelete, agent.isReadOnly != true {
                AdminConfirmButton(
                    i18n: i18n,
                    title: i18n.resolve("admin.agents.details.delete.action"),
                    confirmText: i18n.resolve("admin.agents.details.delete.confirm", ["name": agent.name]),
                    isLoading: isDeleting,
                    identifier: "admin-agent-details-delete",
                    onConfirm: onDelete
                )
            }
        }
    }
}

public extension BaseAgentDetails where Content == EmptyView {
    init(
        agent: Agent?,
        groups: [MembershipGroup] = [],
        roles: [String] = [],
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        onDelete: (() -> Void)? = nil,
        isRunningLifecycleAction: Bool = false,
        lifecycleActions: [AccountLifecycleAction] = [],
        onLifecycleAction: ((AccountLifecycleAction, String?) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            agent: agent,
            groups: groups,
            roles: roles,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            onDelete: onDelete,
            isRunningLifecycleAction: isRunningLifecycleAction,
            lifecycleActions: lifecycleActions,
            onLifecycleAction: onLifecycleAction,
            actions: actions,
            renderContent: nil
        )
    }
}

/// An agent's details, loaded through the management API. Set `deletable` to let the signed-in
/// user delete the agent; it is off by default, and a delete asks for confirmation first. Set
/// `lifecycleActions` to let them suspend, unsuspend and unlock the agent: each action runs through its
/// administration flow and is offered only when the agent's status allows it and the server configures
/// its flow. The configured flows are read only while it is on, which needs a token that may read the
/// server configuration. The agent API has no flow-backed delete, so there is no `administrationMode`.
public struct AgentDetails<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let agentId: String
    let deletable: Bool
    let lifecycleActions: Bool
    let onDeleted: (() -> Void)?
    let actions: AnyView?
    let content: ((AgentDetailsState) -> Content)?

    init(
        agentId: String,
        deletable: Bool = false,
        lifecycleActions: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((AgentDetailsState) -> Content)?
    ) {
        self.agentId = agentId
        self.deletable = deletable
        self.lifecycleActions = lifecycleActions
        self.onDeleted = onDeleted
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameters:
    ///   - lifecycleActions: Whether to offer the account lifecycle actions. Off by default.
    ///   - content: Renders custom UI in place of the default view. See ``BaseAgentDetails``.
    public init(
        agentId: String,
        deletable: Bool = false,
        lifecycleActions: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (AgentDetailsState) -> Content
    ) {
        self.init(
            agentId: agentId,
            deletable: deletable,
            lifecycleActions: lifecycleActions,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        AgentDetailsHost(state: thunderState, props: self).id(agentId)
    }
}

public extension AgentDetails where Content == EmptyView {
    init(
        agentId: String,
        deletable: Bool = false,
        lifecycleActions: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            agentId: agentId,
            deletable: deletable,
            lifecycleActions: lifecycleActions,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: nil
        )
    }
}

private struct AgentDetailsHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var agent: ResourceQuery<Agent>
    @StateObject private var groups: ResourceQuery<MembershipGroupListResponse>
    @StateObject private var roles: ResourceQuery<AgentRoleListResponse>
    @StateObject private var deletion: ResourceMutation<String, Void>
    @StateObject private var lifecycleFlows: ResourceQuery<[AdministrationFlowConfigKey: String]>
    @StateObject private var lifecycle: ResourceMutation<AccountLifecycleInput, AccountLifecycleResult>
    let props: AgentDetails<Content>

    init(state: ThunderIDState, props: AgentDetails<Content>) {
        _agent = StateObject(wrappedValue: state.agentQuery(id: props.agentId))
        _groups = StateObject(wrappedValue: state.agentGroupsQuery(agentId: props.agentId, limit: 100))
        _roles = StateObject(wrappedValue: state.agentRolesQuery(agentId: props.agentId, limit: 100))
        _deletion = StateObject(wrappedValue: state.deleteAgentMutation())
        _lifecycleFlows = StateObject(wrappedValue: state.accountLifecycleFlowsQuery(kind: .agent))
        _lifecycle = StateObject(wrappedValue: state.accountLifecycleMutation(kind: .agent))
        self.props = props
    }

    var body: some View {
        BaseAgentDetails(
            agent: agent.data,
            groups: groups.data?.groups ?? [],
            roles: roles.data?.roles ?? [],
            isLoading: agent.isLoading,
            error: i18n.managementErrorMessage(agent.error, fallbackKey: "admin.agents.details.error")
                ?? i18n.managementErrorMessage(deletion.error, fallbackKey: "admin.agents.details.delete.error")
                ?? i18n.managementErrorMessage(lifecycle.error, fallbackKey: "admin.common.lifecycle.error")
                ?? i18n.managementErrorMessage(lifecycleFlows.error, fallbackKey: "admin.common.lifecycle.load_error"),
            isDeleting: deletion.isLoading,
            onDelete: props.deletable ? delete : nil,
            isRunningLifecycleAction: lifecycle.isLoading,
            lifecycleActions: availableLifecycleActions,
            onLifecycleAction: props.lifecycleActions ? runLifecycleAction : nil,
            actions: props.actions,
            renderContent: props.content
        )
        .task {
            async let loadAgent: Void = { _ = await agent.refetch() }()
            async let loadGroups: Void = { _ = await groups.refetch() }()
            async let loadRoles: Void = { _ = await roles.refetch() }()
            _ = await (loadAgent, loadGroups, loadRoles)
        }
        .task(id: props.lifecycleActions) {
            if props.lifecycleActions { await lifecycleFlows.refetch() }
        }
    }

    private var availableLifecycleActions: [AccountLifecycleAction] {
        guard props.lifecycleActions, let flows = lifecycleFlows.data else { return [] }
        return AccountLifecycleAction.available(for: .agent, status: agent.data?.status?.value, configuredFlows: flows)
    }

    private func runLifecycleAction(_ action: AccountLifecycleAction, operatorNote: String?) {
        let input = AccountLifecycleInput(subject: props.agentId, action: action, operatorNote: operatorNote)
        Task { await lifecycle.mutate(input) }
    }

    private func delete() {
        Task {
            if await deletion.mutate(props.agentId) != nil {
                props.onDeleted?()
            }
        }
    }
}
