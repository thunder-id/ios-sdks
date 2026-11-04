// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Renders an attribute value as text: scalars as-is, lists and objects as JSON.
func stringifyManagedAttribute(_ value: AnyCodable) -> String {
    switch value.value {
    case let text as String: return text
    case is NSNull: return ""
    case let flag as Bool: return flag ? "true" : "false"
    case let number as Int: return String(number)
    case let number as Double: return String(number)
    default:
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

/// A user's attributes, groups and access status, rendered from the data it is given. Editing and
/// deleting are offered only when `onUpdate` and `onDelete` are set, and never for a read-only user.
/// The account lifecycle actions in `lifecycleActions` (suspend, unsuspend, unlock) are offered only
/// when `onLifecycleAction` is set; they change only runtime state, so they apply to read-only users
/// too. Suspending and unsuspending ask for confirmation first, and a suspension takes an optional
/// operator note.
public struct BaseUserDetails<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let user: ManagedUser?
    let groups: [MembershipGroup]
    let hiddenAttributes: Set<String>
    let isLoading: Bool
    let error: String?
    let isDeleting: Bool
    let isUpdating: Bool
    let onDelete: (() -> Void)?
    let onUpdate: (([String: AnyCodable]) -> Void)?
    let isRunningLifecycleAction: Bool
    let lifecycleActions: [AccountLifecycleAction]
    let onLifecycleAction: ((AccountLifecycleAction, String?) -> Void)?
    let actions: AnyView?

    @State private var draft: [String: String]?

    let content: ((UserDetailsState) -> Content)?

    init(
        user: ManagedUser?,
        groups: [MembershipGroup] = [],
        hiddenAttributes: Set<String> = ["password"],
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        isUpdating: Bool = false,
        onDelete: (() -> Void)? = nil,
        onUpdate: (([String: AnyCodable]) -> Void)? = nil,
        isRunningLifecycleAction: Bool = false,
        lifecycleActions: [AccountLifecycleAction] = [],
        onLifecycleAction: ((AccountLifecycleAction, String?) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((UserDetailsState) -> Content)?
    ) {
        self.user = user
        self.groups = groups
        self.hiddenAttributes = hiddenAttributes
        self.isLoading = isLoading
        self.error = error
        self.isDeleting = isDeleting
        self.isUpdating = isUpdating
        self.onDelete = onDelete
        self.onUpdate = onUpdate
        self.isRunningLifecycleAction = isRunningLifecycleAction
        self.lifecycleActions = lifecycleActions
        self.onLifecycleAction = onLifecycleAction
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view, from the user, their visible attributes
    ///   and groups, the loading and error state, and the delete, update and lifecycle actions.
    public init(
        user: ManagedUser?,
        groups: [MembershipGroup] = [],
        hiddenAttributes: Set<String> = ["password"],
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        isUpdating: Bool = false,
        onDelete: (() -> Void)? = nil,
        onUpdate: (([String: AnyCodable]) -> Void)? = nil,
        isRunningLifecycleAction: Bool = false,
        lifecycleActions: [AccountLifecycleAction] = [],
        onLifecycleAction: ((AccountLifecycleAction, String?) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (UserDetailsState) -> Content
    ) {
        self.init(
            user: user,
            groups: groups,
            hiddenAttributes: hiddenAttributes,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            isUpdating: isUpdating,
            onDelete: onDelete,
            onUpdate: onUpdate,
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

    private var renderState: UserDetailsState {
        let isWritable = user != nil && user?.isReadOnly != true
        return UserDetailsState(
            user: user,
            displayName: user?.resolvedName ?? "",
            attributes: (user?.attributes ?? [:]).filter { !hiddenAttributes.contains($0.key) },
            groups: groups,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            isUpdating: isUpdating,
            onDelete: isWritable ? onDelete : nil,
            onUpdate: isWritable ? onUpdate : nil,
            isRunningLifecycleAction: isRunningLifecycleAction,
            lifecycleActions: onLifecycleAction != nil && user != nil ? lifecycleActions : [],
            onLifecycleAction: user != nil ? onLifecycleAction : nil
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        if let user {
            details(user)
        } else {
            AdminSection(identifier: "admin-user-details") {
                if isLoading {
                    AdminLoadingRow(label: i18n.resolve("admin.common.loading"))
                } else {
                    AdminErrorBanner(message: error ?? i18n.resolve("admin.common.errors.not_found"))
                }
            }
        }
    }

    private func details(_ user: ManagedUser) -> some View {
        let name = user.resolvedName
        let attributes = (user.attributes ?? [:])
            .filter { !hiddenAttributes.contains($0.key) }
            .sorted { $0.key < $1.key }
        let editable = attributes.compactMap { entry in (entry.value.value as? String).map { (entry.key, $0) } }
        return AdminSection(
            identifier: "admin-user-details",
            title: name,
            description: i18n.resolve("admin.users.details.subtitle", ["type": user.type]),
            actions: { headerActions(user, name: name) },
            content: {
                if let error {
                    AdminErrorBanner(message: error)
                }
                HStack(spacing: 12) {
                    AdminAvatar(name: name, size: 48)
                    Text(user.ouHandle ?? user.ouId).foregroundColor(.secondary)
                    AccessStatusBadge(i18n: i18n, status: user.status?.value)
                }
                AdminPanel(
                    title: i18n.resolve("admin.users.details.attributes"),
                    actions: editAction(user, editable: editable)
                ) {
                    attributeContent(user, attributes: attributes)
                }
                AdminPanel(title: i18n.resolve("admin.users.details.groups")) {
                    AdminChipList(
                        label: i18n.resolve("admin.users.details.groups"),
                        emptyText: i18n.resolve("admin.users.details.no_groups"),
                        items: groups.map { ($0.id, $0.name) }
                    )
                }
            }
        )
    }

    private func headerActions(_ user: ManagedUser, name: String) -> some View {
        HStack(spacing: 8) {
            actions
            if let onLifecycleAction {
                AccountLifecycleButtons(
                    i18n: i18n,
                    actions: lifecycleActions,
                    collectsOperatorNote: true,
                    isRunning: isRunningLifecycleAction,
                    name: name,
                    identifier: "admin-user-details-lifecycle",
                    onAction: onLifecycleAction
                )
            }
            if let onDelete, user.isReadOnly != true {
                AdminConfirmButton(
                    i18n: i18n,
                    title: i18n.resolve("admin.users.details.delete.action"),
                    confirmText: i18n.resolve("admin.users.details.delete.confirm", ["name": name]),
                    isLoading: isDeleting,
                    identifier: "admin-user-details-delete",
                    onConfirm: onDelete
                )
            }
        }
    }

    private func editAction(_ user: ManagedUser, editable: [(String, String)]) -> AnyView? {
        guard onUpdate != nil, user.isReadOnly != true, draft == nil, !editable.isEmpty else { return nil }
        return AnyView(
            Button(i18n.resolve("admin.users.details.edit.action")) {
                draft = Dictionary(uniqueKeysWithValues: editable)
            }
            .accessibilityIdentifier("admin-user-details-edit")
        )
    }

    @ViewBuilder
    private func attributeContent(_ user: ManagedUser, attributes: [(key: String, value: AnyCodable)]) -> some View {
        if let draft {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(draft.keys.sorted(), id: \.self) { name in
                    AdminTextField(
                        label: name,
                        name: name,
                        text: Binding(get: { self.draft?[name] ?? "" }, set: { self.draft?[name] = $0 })
                    )
                }
                AdminFormActions(
                    i18n: i18n,
                    submitLabel: i18n.resolve("admin.users.details.edit.save"),
                    isSubmitting: isUpdating,
                    canSubmit: true,
                    onCancel: { self.draft = nil },
                    onSubmit: {
                        let edited = draft.mapValues { AnyCodable($0) }
                        onUpdate?((user.attributes ?? [:]).merging(edited) { _, new in new })
                        self.draft = nil
                    }
                )
            }
        } else if attributes.isEmpty {
            Text(i18n.resolve("admin.users.details.no_attributes"))
                .font(.subheadline)
                .foregroundColor(.secondary)
        } else {
            AdminDetailList(items: attributes.map { ($0.key, stringifyManagedAttribute($0.value)) })
        }
    }
}

public extension BaseUserDetails where Content == EmptyView {
    init(
        user: ManagedUser?,
        groups: [MembershipGroup] = [],
        hiddenAttributes: Set<String> = ["password"],
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        isUpdating: Bool = false,
        onDelete: (() -> Void)? = nil,
        onUpdate: (([String: AnyCodable]) -> Void)? = nil,
        isRunningLifecycleAction: Bool = false,
        lifecycleActions: [AccountLifecycleAction] = [],
        onLifecycleAction: ((AccountLifecycleAction, String?) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            user: user,
            groups: groups,
            hiddenAttributes: hiddenAttributes,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            isUpdating: isUpdating,
            onDelete: onDelete,
            onUpdate: onUpdate,
            isRunningLifecycleAction: isRunningLifecycleAction,
            lifecycleActions: lifecycleActions,
            onLifecycleAction: onLifecycleAction,
            actions: actions,
            renderContent: nil
        )
    }
}

/// A user's details, loaded through the management API. Set `editable` to let the signed-in user
/// edit text attributes and `deletable` to let them delete the user; both are off by default, and a
/// delete asks for confirmation first. `administrationMode` chooses how the delete runs (`.native` by
/// default). Set `lifecycleActions` to let them suspend, unsuspend and unlock the user: each action runs
/// through its administration flow and is offered only when the user's status allows it and the server
/// configures its flow. The configured flows are read only while it is on, which needs a token that
/// may read the server configuration.
public struct UserDetails<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let userId: String
    let editable: Bool
    let deletable: Bool
    let administrationMode: AdministrationMode
    let lifecycleActions: Bool
    let hiddenAttributes: Set<String>
    let onDeleted: (() -> Void)?
    let actions: AnyView?
    let content: ((UserDetailsState) -> Content)?

    init(
        userId: String,
        editable: Bool = false,
        deletable: Bool = false,
        administrationMode: AdministrationMode = .native,
        lifecycleActions: Bool = false,
        hiddenAttributes: Set<String> = ["password"],
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((UserDetailsState) -> Content)?
    ) {
        self.userId = userId
        self.editable = editable
        self.deletable = deletable
        self.administrationMode = administrationMode
        self.lifecycleActions = lifecycleActions
        self.hiddenAttributes = hiddenAttributes
        self.onDeleted = onDeleted
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameters:
    ///   - administrationMode: How the delete runs. See ``AdministrationMode``.
    ///   - lifecycleActions: Whether to offer the account lifecycle actions. Off by default.
    ///   - content: Renders custom UI in place of the default view. See ``BaseUserDetails``.
    public init(
        userId: String,
        editable: Bool = false,
        deletable: Bool = false,
        administrationMode: AdministrationMode = .native,
        lifecycleActions: Bool = false,
        hiddenAttributes: Set<String> = ["password"],
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (UserDetailsState) -> Content
    ) {
        self.init(
            userId: userId,
            editable: editable,
            deletable: deletable,
            administrationMode: administrationMode,
            lifecycleActions: lifecycleActions,
            hiddenAttributes: hiddenAttributes,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        UserDetailsHost(state: thunderState, props: self).id(userId)
    }
}

public extension UserDetails where Content == EmptyView {
    init(
        userId: String,
        editable: Bool = false,
        deletable: Bool = false,
        administrationMode: AdministrationMode = .native,
        lifecycleActions: Bool = false,
        hiddenAttributes: Set<String> = ["password"],
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            userId: userId,
            editable: editable,
            deletable: deletable,
            administrationMode: administrationMode,
            lifecycleActions: lifecycleActions,
            hiddenAttributes: hiddenAttributes,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: nil
        )
    }
}

private struct UserDetailsHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var user: ResourceQuery<ManagedUser>
    @StateObject private var groups: ResourceQuery<MembershipGroupListResponse>
    @StateObject private var deletion: ResourceMutation<String, Void>
    @StateObject private var update: ResourceMutation<(id: String, request: UpdateManagedUserRequest), ManagedUser>
    @StateObject private var lifecycleFlows: ResourceQuery<[AdministrationFlowConfigKey: String]>
    @StateObject private var lifecycle: ResourceMutation<AccountLifecycleInput, AccountLifecycleResult>
    let props: UserDetails<Content>

    init(state: ThunderIDState, props: UserDetails<Content>) {
        _user = StateObject(wrappedValue: state.userQuery(id: props.userId))
        _groups = StateObject(wrappedValue: state.userGroupsQuery(userId: props.userId, limit: 100))
        _deletion = StateObject(
            wrappedValue: state.deleteUserMutation(administrationMode: props.administrationMode)
        )
        _update = StateObject(wrappedValue: state.updateUserMutation())
        _lifecycleFlows = StateObject(wrappedValue: state.accountLifecycleFlowsQuery(kind: .user))
        _lifecycle = StateObject(wrappedValue: state.accountLifecycleMutation(kind: .user))
        self.props = props
    }

    var body: some View {
        BaseUserDetails(
            user: user.data,
            groups: groups.data?.groups ?? [],
            hiddenAttributes: props.hiddenAttributes,
            isLoading: user.isLoading,
            error: i18n.managementErrorMessage(user.error, fallbackKey: "admin.users.details.error")
                ?? i18n.managementErrorMessage(deletion.error, fallbackKey: "admin.users.details.delete.error")
                ?? i18n.managementErrorMessage(update.error, fallbackKey: "admin.users.details.edit.error")
                ?? i18n.managementErrorMessage(lifecycle.error, fallbackKey: "admin.common.lifecycle.error")
                ?? i18n.managementErrorMessage(lifecycleFlows.error, fallbackKey: "admin.common.lifecycle.load_error"),
            isDeleting: deletion.isLoading,
            isUpdating: update.isLoading,
            onDelete: props.deletable ? delete : nil,
            onUpdate: props.editable && user.data != nil ? save : nil,
            isRunningLifecycleAction: lifecycle.isLoading,
            lifecycleActions: availableLifecycleActions,
            onLifecycleAction: props.lifecycleActions ? runLifecycleAction : nil,
            actions: props.actions,
            renderContent: props.content
        )
        .task {
            async let loadUser: Void = { _ = await user.refetch() }()
            async let loadGroups: Void = { _ = await groups.refetch() }()
            _ = await (loadUser, loadGroups)
        }
        .task(id: props.lifecycleActions) {
            if props.lifecycleActions { await lifecycleFlows.refetch() }
        }
    }

    private var availableLifecycleActions: [AccountLifecycleAction] {
        guard props.lifecycleActions, let flows = lifecycleFlows.data else { return [] }
        return AccountLifecycleAction.available(for: .user, status: user.data?.status?.value, configuredFlows: flows)
    }

    private func runLifecycleAction(_ action: AccountLifecycleAction, operatorNote: String?) {
        let input = AccountLifecycleInput(subject: props.userId, action: action, operatorNote: operatorNote)
        Task { await lifecycle.mutate(input) }
    }

    private func delete() {
        Task {
            if await deletion.mutate(props.userId) != nil {
                props.onDeleted?()
            }
        }
    }

    private func save(_ attributes: [String: AnyCodable]) {
        guard let current = user.data else { return }
        let request = UpdateManagedUserRequest(ouId: current.ouId, type: current.type, attributes: attributes)
        Task { await update.mutate((id: props.userId, request: request)) }
    }
}
