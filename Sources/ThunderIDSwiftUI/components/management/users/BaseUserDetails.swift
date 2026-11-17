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
/// operator note. With `onSendVerification`, a user's unverified email offers a verification link; the
/// status shows only when the server reports the user's verified attributes.
public struct BaseUserDetails<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let user: ManagedUser?
    let groups: [MembershipGroup]
    let userSchema: EntityTypeSchema?
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
    let isSendingVerification: Bool
    let sentVerification: UserAttributeVerificationResult?
    let onSendVerification: ((String) -> Void)?
    let actions: AnyView?

    @State private var draft: [String: String]?
    @State private var sendingAttribute: String?

    let content: ((UserDetailsState) -> Content)?

    init(
        user: ManagedUser?,
        groups: [MembershipGroup] = [],
        userSchema: EntityTypeSchema? = nil,
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
        isSendingVerification: Bool = false,
        sentVerification: UserAttributeVerificationResult? = nil,
        onSendVerification: ((String) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((UserDetailsState) -> Content)?
    ) {
        self.user = user
        self.groups = groups
        self.userSchema = userSchema
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
        self.isSendingVerification = isSendingVerification
        self.sentVerification = sentVerification
        self.onSendVerification = onSendVerification
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view, from the user, their visible attributes
    ///   and groups, their verification status, the loading and error state, and the allowed actions.
    public init(
        user: ManagedUser?,
        groups: [MembershipGroup] = [],
        userSchema: EntityTypeSchema? = nil,
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
        isSendingVerification: Bool = false,
        sentVerification: UserAttributeVerificationResult? = nil,
        onSendVerification: ((String) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (UserDetailsState) -> Content
    ) {
        self.init(
            user: user,
            groups: groups,
            userSchema: userSchema,
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
            isSendingVerification: isSendingVerification,
            sentVerification: sentVerification,
            onSendVerification: onSendVerification,
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
            onLifecycleAction: user != nil ? onLifecycleAction : nil,
            verifiableAttributes: verifiableAttributes,
            verifiedAttributes: user?.verifiedAttributes,
            sendableAttributes: sendableAttributes,
            onSendVerification: sendAction,
            isSendingVerification: isSendingVerification,
            sentVerification: sentVerification
        )
    }

    private var verifiableAttributes: [String] {
        guard let user, let records = user.verifiedAttributes else { return [] }
        let names = (user.attributes ?? [:]).compactMap { name, attribute -> String? in
            guard !hiddenAttributes.contains(name), userSchema?[name]?.credential != true,
                  let value = attribute.value as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let type = userSchema?[name]?.type.lowercased()
            return records[name] != nil || type.map(AttributeVerification.verifiableAttributeTypes.contains) == true
                ? name : nil
        }
        return names.sorted()
    }

    private var sendableAttributes: Set<String> {
        guard let user, user.isReadOnly != true, onSendVerification != nil else { return [] }
        return Set(verifiableAttributes.filter {
            userSchema?[$0]?.type.lowercased() == "email" && user.verifiedAttributes?[$0] == nil
        })
    }

    private var sendAction: ((String) -> Void)? {
        let eligible = sendableAttributes
        guard !eligible.isEmpty, !isUpdating, !isSendingVerification, let onSendVerification else { return nil }
        return { name in
            guard eligible.contains(name) else { return }
            sendingAttribute = name
            onSendVerification(name)
        }
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
                } else if let sentVerification, sentVerification.emailSent == false {
                    AdminErrorBanner(message: i18n.resolve("admin.users.details.verification.error"))
                } else if let sentVerification {
                    AdminSuccessNotice(message: i18n.verificationSentMessage(sentVerification))
                        .accessibilityIdentifier("admin-user-details-verification-sent")
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
            .disabled(isSendingVerification || isUpdating)
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
            let verifiable = verifiableAttributes
            VStack(alignment: .leading, spacing: 6) {
                ForEach(attributes, id: \.key) { entry in
                    if verifiable.contains(entry.key) {
                        verifiableRow(user, name: entry.key, value: stringifyManagedAttribute(entry.value))
                    } else {
                        AdminDetailList(items: [(entry.key, stringifyManagedAttribute(entry.value))])
                    }
                    if entry.key != attributes.last?.key {
                        Divider()
                    }
                }
            }
        }
    }

    private func verifiableRow(_ user: ManagedUser, name: String, value: String) -> some View {
        UserAttributeVerificationRow(
            i18n: i18n,
            name: name,
            value: value,
            isVerified: user.verifiedAttributes?[name] != nil,
            isSending: isSendingVerification && sendingAttribute == name,
            isUpdating: isUpdating || isSendingVerification,
            onSend: sendableAttributes.contains(name) ? { sendAction?(name) } : nil
        )
    }
}

public extension BaseUserDetails where Content == EmptyView {
    init(
        user: ManagedUser?,
        groups: [MembershipGroup] = [],
        userSchema: EntityTypeSchema? = nil,
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
        isSendingVerification: Bool = false,
        sentVerification: UserAttributeVerificationResult? = nil,
        onSendVerification: ((String) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            user: user,
            groups: groups,
            userSchema: userSchema,
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
            isSendingVerification: isSendingVerification,
            sentVerification: sentVerification,
            onSendVerification: onSendVerification,
            actions: actions,
            renderContent: nil
        )
    }
}
