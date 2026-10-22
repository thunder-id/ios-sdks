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

/// A user's attributes and groups, rendered from the data it is given. Editing and deleting are
/// offered only when `onUpdate` and `onDelete` are set, and never for a read-only user.
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
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view, from the user, their visible attributes
    ///   and groups, the loading and error state, and the delete and update actions.
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
            onUpdate: isWritable ? onUpdate : nil
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
            actions: {
                HStack(spacing: 8) {
                    actions
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
            },
            content: {
                if let error {
                    AdminErrorBanner(message: error)
                }
                HStack(spacing: 12) {
                    AdminAvatar(name: name, size: 48)
                    Text(user.ouHandle ?? user.ouId).foregroundColor(.secondary)
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
            actions: actions,
            renderContent: nil
        )
    }
}

/// A user's details, loaded through the management API. Set `editable` to let the signed-in user
/// edit text attributes and `deletable` to let them delete the user; both are off by default, and a
/// delete asks for confirmation first.
public struct UserDetails<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let userId: String
    let editable: Bool
    let deletable: Bool
    let hiddenAttributes: Set<String>
    let onDeleted: (() -> Void)?
    let actions: AnyView?
    let content: ((UserDetailsState) -> Content)?

    init(
        userId: String,
        editable: Bool = false,
        deletable: Bool = false,
        hiddenAttributes: Set<String> = ["password"],
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((UserDetailsState) -> Content)?
    ) {
        self.userId = userId
        self.editable = editable
        self.deletable = deletable
        self.hiddenAttributes = hiddenAttributes
        self.onDeleted = onDeleted
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view. See ``BaseUserDetails``.
    public init(
        userId: String,
        editable: Bool = false,
        deletable: Bool = false,
        hiddenAttributes: Set<String> = ["password"],
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (UserDetailsState) -> Content
    ) {
        self.init(
            userId: userId,
            editable: editable,
            deletable: deletable,
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
        hiddenAttributes: Set<String> = ["password"],
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            userId: userId,
            editable: editable,
            deletable: deletable,
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
    let props: UserDetails<Content>

    init(state: ThunderIDState, props: UserDetails<Content>) {
        _user = StateObject(wrappedValue: state.userQuery(id: props.userId))
        _groups = StateObject(wrappedValue: state.userGroupsQuery(userId: props.userId, limit: 100))
        _deletion = StateObject(wrappedValue: state.deleteUserMutation())
        _update = StateObject(wrappedValue: state.updateUserMutation())
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
                ?? i18n.managementErrorMessage(update.error, fallbackKey: "admin.users.details.edit.error"),
            isDeleting: deletion.isLoading,
            isUpdating: update.isLoading,
            onDelete: props.deletable ? delete : nil,
            onUpdate: props.editable && user.data != nil ? save : nil,
            actions: props.actions,
            renderContent: props.content
        )
        .task {
            async let loadUser: Void = { _ = await user.refetch() }()
            async let loadGroups: Void = { _ = await groups.refetch() }()
            _ = await (loadUser, loadGroups)
        }
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
