// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// What ``BasePersonalAgentDetails`` hands its `content` closure, so the agent can be shown with any UI. An
/// action is `nil` when the app has not turned it on, or when it does not apply to the agent.
public struct PersonalAgentDetailsState {
    public let agent: Agent?
    /// The agent's OAuth settings. `nil` when it has no OAuth client.
    public let oauth: OAuth2Config?
    public let isLoading: Bool
    /// A translated message, or `nil` when there is nothing to report.
    public let error: String?
    public let isUpdating: Bool
    public let isDeleting: Bool
    public let isChangingSuspension: Bool
    /// Replaces the editable part of the agent, and returns whether it was saved. ``PersonalAgentFormValues``
    /// builds the request.
    public let onUpdate: ((UpdateMeAgentRequest) async -> Bool)?
    /// Deletes the agent. Ask for confirmation first.
    public let onDelete: (() -> Void)?
    /// Places the owner's suspension on the agent. Offered unless the owner already holds it suspended.
    public let onSuspend: (() -> Void)?
    /// Lifts the owner's suspension of the agent. Offered only while the owner holds it suspended.
    public let onUnsuspend: (() -> Void)?
}

/// One of the signed-in user's personal agents with the actions its owner can take, rendered from the data it
/// is given. Editing, deleting and the owner's suspension are each offered only when their handler is set;
/// editing and deleting never for a read-only agent. Suspending and deleting ask for confirmation first.
/// ``PersonalAgentDetails`` loads the data for you.
public struct BasePersonalAgentDetails<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let agent: Agent?
    let isLoading: Bool
    let error: String?
    let isUpdating: Bool
    let isDeleting: Bool
    let isChangingSuspension: Bool
    let onUpdate: ((UpdateMeAgentRequest) async -> Bool)?
    let onDelete: (() -> Void)?
    let onSuspend: (() -> Void)?
    let onUnsuspend: (() -> Void)?
    let actions: AnyView?
    let content: ((PersonalAgentDetailsState) -> Content)?
    /// The draft remembers which agent it was opened for, so switching the agent closes the form instead of
    /// saving one agent's values onto another.
    @State private var draft: PersonalAgentDraft?
    @State private var confirmation: PersonalAgentConfirmation?

    init(
        agent: Agent?,
        isLoading: Bool = false,
        error: String? = nil,
        isUpdating: Bool = false,
        isDeleting: Bool = false,
        isChangingSuspension: Bool = false,
        onUpdate: ((UpdateMeAgentRequest) async -> Bool)? = nil,
        onDelete: (() -> Void)? = nil,
        onSuspend: (() -> Void)? = nil,
        onUnsuspend: (() -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((PersonalAgentDetailsState) -> Content)?
    ) {
        self.agent = agent
        self.isLoading = isLoading
        self.error = error
        self.isUpdating = isUpdating
        self.isDeleting = isDeleting
        self.isChangingSuspension = isChangingSuspension
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onSuspend = onSuspend
        self.onUnsuspend = onUnsuspend
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameters:
    ///   - onUpdate: Saves the edited agent and returns whether it was saved. The edit form stays open with the
    ///     changes until it returns `true`.
    ///   - content: Renders custom UI in place of the default view, from the agent, its OAuth settings, the
    ///     loading and error state, and the actions the app has turned on that apply to it.
    public init(
        agent: Agent?,
        isLoading: Bool = false,
        error: String? = nil,
        isUpdating: Bool = false,
        isDeleting: Bool = false,
        isChangingSuspension: Bool = false,
        onUpdate: ((UpdateMeAgentRequest) async -> Bool)? = nil,
        onDelete: (() -> Void)? = nil,
        onSuspend: (() -> Void)? = nil,
        onUnsuspend: (() -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (PersonalAgentDetailsState) -> Content
    ) {
        self.init(
            agent: agent,
            isLoading: isLoading,
            error: error,
            isUpdating: isUpdating,
            isDeleting: isDeleting,
            isChangingSuspension: isChangingSuspension,
            onUpdate: onUpdate,
            onDelete: onDelete,
            onSuspend: onSuspend,
            onUnsuspend: onUnsuspend,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        Group {
            if let content {
                content(renderState)
            } else {
                defaultBody
            }
        }
        // Switching the agent discards the draft and any pending confirmation, so coming back to an agent
        // starts from its stored values.
        .onChange(of: agent?.id) { _ in
            draft = nil
            confirmation = nil
        }
    }

    private var isWritable: Bool { agent != nil && agent?.isReadOnly != true }
    private var suspensionAction: MeAgentSuspensionAction? {
        agent.map { MeAgentSuspensionAction.available(for: $0.status) }
    }

    private var renderState: PersonalAgentDetailsState {
        PersonalAgentDetailsState(
            agent: agent,
            oauth: agent?.oauthConfig,
            isLoading: isLoading,
            error: error,
            isUpdating: isUpdating,
            isDeleting: isDeleting,
            isChangingSuspension: isChangingSuspension,
            onUpdate: isWritable ? onUpdate : nil,
            onDelete: isWritable ? onDelete : nil,
            onSuspend: suspensionAction == .suspend ? onSuspend : nil,
            onUnsuspend: suspensionAction == .unsuspend ? onUnsuspend : nil
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        if let agent {
            details(agent)
        } else {
            AdminSection(identifier: "personal-agent-details") {
                if isLoading {
                    AdminLoadingRow(label: i18n.resolve("admin.common.loading"))
                } else {
                    AdminErrorBanner(message: error ?? i18n.resolve("admin.common.errors.not_found"))
                }
            }
        }
    }

    private func details(_ agent: Agent) -> some View {
        AdminSection(
            identifier: "personal-agent-details",
            title: agent.resolvedName,
            description: agent.description,
            actions: { headerActions(agent) },
            content: { sections(agent) }
        )
        .alert(
            confirmation.map { confirmText($0, agent: agent) } ?? "",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            presenting: confirmation
        ) { action in
            Button(i18n.resolve("admin.common.actions.cancel"), role: .cancel) {}
            Button(i18n.resolve("admin.common.actions.confirm"), role: .destructive) { confirm(action) }
                .accessibilityIdentifier("personal-agent-details-\(action.rawValue)-confirm")
        }
    }

    @ViewBuilder
    private func sections(_ agent: Agent) -> some View {
        if let error {
            AdminErrorBanner(message: error)
        }
        ForEach(PersonalAgentParts.suspensionNotices(agent, i18n: i18n), id: \.self) { notice in
            FlowNoticeBanner(message: notice)
        }
        if isWritable, let current = draft, current.agentId == agent.id, let onUpdate {
            PersonalAgentEditForm(
                i18n: i18n,
                values: Binding(get: { draft?.values ?? current.values }, set: { draft?.values = $0 }),
                isUpdating: isUpdating,
                onCancel: { draft = nil },
                onSave: { values in save(values, for: agent, with: onUpdate) }
            )
        } else {
            AdminPanel(title: i18n.resolve("user.agents.details.overview")) {
                AdminDetailList(items: PersonalAgentParts.overview(agent, i18n: i18n))
            }
            AdminPanel(title: i18n.resolve("user.agents.details.attributes")) {
                PersonalAgentParts.attributes(agent, i18n: i18n)
            }
        }
    }

    private func save(
        _ values: PersonalAgentFormValues,
        for agent: Agent,
        with onUpdate: @escaping (UpdateMeAgentRequest) async -> Bool
    ) {
        guard isWritable else { return }
        let request = values.updateRequest(for: agent)
        Task {
            // Keeps the changes until the update succeeds, so a failed save can be corrected and retried.
            if await onUpdate(request), draft?.agentId == agent.id {
                draft = nil
            }
        }
    }

    private var isEditing: Bool { draft != nil && draft?.agentId == agent?.id }
    private var canEdit: Bool { onUpdate != nil && isWritable && !isEditing }
    private var canSuspend: Bool { onSuspend != nil && suspensionAction == .suspend }
    private var canUnsuspend: Bool { onUnsuspend != nil && suspensionAction == .unsuspend }
    private var canDelete: Bool { onDelete != nil && isWritable }

    /// The app's own actions, Edit, then a menu with the owner's suspension and delete.
    private func headerActions(_ agent: Agent) -> some View {
        HStack(spacing: 12) {
            actions
            if canEdit {
                Button(i18n.resolve("user.agents.edit.action")) {
                    draft = PersonalAgentDraft(agentId: agent.id, values: PersonalAgentFormValues(agent: agent))
                }
                .accessibilityIdentifier("personal-agent-details-edit")
            }
            if canSuspend || canUnsuspend || canDelete {
                actionMenu
            }
        }
    }

    private var actionMenu: some View {
        Menu {
            if canUnsuspend, let onUnsuspend {
                Button(action: onUnsuspend) {
                    Label(i18n.resolve("user.agents.unsuspend.action"), systemImage: "play.circle")
                }
                .accessibilityIdentifier("personal-agent-details-unsuspend")
            }
            if canSuspend {
                Button { confirmation = .suspend } label: {
                    Label(i18n.resolve("user.agents.suspend.action"), systemImage: "pause.circle")
                }
                .accessibilityIdentifier("personal-agent-details-suspend")
            }
            if canDelete {
                Divider()
                Button(role: .destructive) { confirmation = .delete } label: {
                    Label(i18n.resolve("user.agents.delete.action"), systemImage: "trash")
                }
                .accessibilityIdentifier("personal-agent-details-delete")
            }
        } label: {
            if isChangingSuspension || isDeleting {
                ProgressView()
            } else {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
        .disabled(isChangingSuspension || isDeleting)
        .accessibilityLabel(i18n.resolve("user.agents.actions.menu"))
        .accessibilityIdentifier("personal-agent-details-menu")
    }

    private func confirmText(_ action: PersonalAgentConfirmation, agent: Agent) -> String {
        let key = action == .suspend ? "user.agents.suspend.confirm" : "user.agents.delete.confirm"
        return i18n.resolve(key, ["name": agent.resolvedName])
    }

    private func confirm(_ action: PersonalAgentConfirmation) {
        switch action {
        // The agent can change while the alert is open, for example to read-only, so the action is checked again.
        case .suspend: if canSuspend { onSuspend?() }
        case .delete: if canDelete { onDelete?() }
        }
    }
}

/// An action of ``BasePersonalAgentDetails`` waiting for the user to confirm it.
enum PersonalAgentConfirmation: String {
    case suspend
    case delete
}

public extension BasePersonalAgentDetails where Content == EmptyView {
    init(
        agent: Agent?,
        isLoading: Bool = false,
        error: String? = nil,
        isUpdating: Bool = false,
        isDeleting: Bool = false,
        isChangingSuspension: Bool = false,
        onUpdate: ((UpdateMeAgentRequest) async -> Bool)? = nil,
        onDelete: (() -> Void)? = nil,
        onSuspend: (() -> Void)? = nil,
        onUnsuspend: (() -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            agent: agent,
            isLoading: isLoading,
            error: error,
            isUpdating: isUpdating,
            isDeleting: isDeleting,
            isChangingSuspension: isChangingSuspension,
            onUpdate: onUpdate,
            onDelete: onDelete,
            onSuspend: onSuspend,
            onUnsuspend: onUnsuspend,
            actions: actions,
            renderContent: nil
        )
    }
}

/// One of the signed-in user's personal agents, loaded through `/users/me/agents`. Set `editable`,
/// `deletable` and `suspendable` to let the user edit the agent, delete it, and place or lift their own
/// suspension of it. Each is off by default, and deleting and suspending ask for confirmation first.
public struct PersonalAgentDetails<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let agentId: String
    let editable: Bool
    let deletable: Bool
    let suspendable: Bool
    let onDeleted: (() -> Void)?
    let actions: AnyView?
    let content: ((PersonalAgentDetailsState) -> Content)?
    /// The agent shown now, so a delete that completes after another agent was selected is not reported.
    @State private var shown = ShownPersonalAgent()

    init(
        agentId: String,
        editable: Bool = false,
        deletable: Bool = false,
        suspendable: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((PersonalAgentDetailsState) -> Content)?
    ) {
        self.agentId = agentId
        self.editable = editable
        self.deletable = deletable
        self.suspendable = suspendable
        self.onDeleted = onDeleted
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view. See ``BasePersonalAgentDetails``.
    public init(
        agentId: String,
        editable: Bool = false,
        deletable: Bool = false,
        suspendable: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (PersonalAgentDetailsState) -> Content
    ) {
        self.init(
            agentId: agentId,
            editable: editable,
            deletable: deletable,
            suspendable: suspendable,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        PersonalAgentDetailsHost(state: thunderState, props: self, shown: shown)
            .id(agentId)
            .onAppear { shown.id = agentId }
            .onChange(of: agentId) { shown.id = $0 }
    }
}

public extension PersonalAgentDetails where Content == EmptyView {
    init(
        agentId: String,
        editable: Bool = false,
        deletable: Bool = false,
        suspendable: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            agentId: agentId,
            editable: editable,
            deletable: deletable,
            suspendable: suspendable,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: nil
        )
    }
}

private struct PersonalAgentDetailsHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var agent: ResourceQuery<Agent>
    @StateObject private var update: ResourceMutation<(id: String, request: UpdateMeAgentRequest), Agent>
    @StateObject private var deletion: ResourceMutation<String, Void>
    @StateObject private var suspension: ResourceMutation<(id: String, action: MeAgentSuspensionAction), Void>
    /// Set once this view deletes its agent, so the agent shows as gone rather than as the last record read.
    @State private var isDeleted = false
    let props: PersonalAgentDetails<Content>
    let shown: ShownPersonalAgent

    init(state: ThunderIDState, props: PersonalAgentDetails<Content>, shown: ShownPersonalAgent) {
        _agent = StateObject(wrappedValue: state.meAgentQuery(id: props.agentId))
        _update = StateObject(wrappedValue: state.updateMeAgentMutation())
        _deletion = StateObject(wrappedValue: state.deleteMeAgentMutation())
        _suspension = StateObject(wrappedValue: state.meAgentSuspensionMutation())
        self.props = props
        self.shown = shown
    }

    var body: some View {
        BasePersonalAgentDetails(
            agent: isDeleted ? nil : agent.data,
            isLoading: isDeleted ? false : agent.isLoading,
            error: i18n.managementErrorMessage(agent.error, fallbackKey: "user.agents.details.error")
                ?? i18n.managementErrorMessage(
                    update.error ?? deletion.error ?? suspension.error,
                    fallbackKey: "user.agents.action.error"
                ),
            isUpdating: update.isLoading,
            isDeleting: deletion.isLoading,
            isChangingSuspension: suspension.isLoading,
            onUpdate: props.editable ? { request in await update.mutate((props.agentId, request)) != nil } : nil,
            onDelete: props.deletable ? delete : nil,
            onSuspend: props.suspendable ? { run { await suspension.mutate((props.agentId, .suspend)) } } : nil,
            onUnsuspend: props.suspendable ? { run { await suspension.mutate((props.agentId, .unsuspend)) } } : nil,
            actions: props.actions,
            renderContent: props.content
        )
        .task { await agent.refetch() }
    }

    private func run(_ operation: @escaping @MainActor () async -> Void) {
        Task { await operation() }
    }

    private func delete() {
        Task {
            if await deletion.mutate(props.agentId) != nil {
                isDeleted = true
                if shown.id == props.agentId {
                    props.onDeleted?()
                }
            }
        }
    }
}

/// Which agent ``PersonalAgentDetails`` shows now. A reference, so a request started for an earlier agent reads
/// the current one when it completes.
final class ShownPersonalAgent {
    var id: String?
}
