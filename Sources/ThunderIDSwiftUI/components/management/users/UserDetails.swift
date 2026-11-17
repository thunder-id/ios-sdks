// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A user's details, loaded through the management API. Set `editable` to let the signed-in user
/// edit text attributes and `deletable` to let them delete the user; both are off by default, and a
/// delete asks for confirmation first. `administrationMode` chooses how the delete runs (`.native` by
/// default). Set `lifecycleActions` to let them suspend, unsuspend and unlock the user: each action runs
/// through its administration flow and is offered only when the user's status allows it and the server
/// configures its flow. The configured flows are read only while it is on, which needs a token that
/// may read the server configuration. Set `attributeVerification` to let them send the user a link to
/// verify an unverified email, through the server's administrator-initiated verification flow; it is off
/// by default and needs `baseUrl` and the root `system` permission. The flow is the handle the server
/// names under `adminAttributeVerificationFlow` in its `flow` configuration, and the action is offered
/// only when that handle is set.
public struct UserDetails<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let userId: String
    let editable: Bool
    let deletable: Bool
    let administrationMode: AdministrationMode
    let lifecycleActions: Bool
    let attributeVerification: Bool
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
        attributeVerification: Bool = false,
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
        self.attributeVerification = attributeVerification
        self.hiddenAttributes = hiddenAttributes
        self.onDeleted = onDeleted
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameters:
    ///   - administrationMode: How the delete runs. See ``AdministrationMode``.
    ///   - lifecycleActions: Whether to offer the account lifecycle actions. Off by default.
    ///   - attributeVerification: Whether to offer a verification link for an unverified email, when the
    ///     server configures `adminAttributeVerificationFlow`. Off by default.
    ///   - content: Renders custom UI in place of the default view. See ``BaseUserDetails``.
    public init(
        userId: String,
        editable: Bool = false,
        deletable: Bool = false,
        administrationMode: AdministrationMode = .native,
        lifecycleActions: Bool = false,
        attributeVerification: Bool = false,
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
            attributeVerification: attributeVerification,
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
        attributeVerification: Bool = false,
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
            attributeVerification: attributeVerification,
            hiddenAttributes: hiddenAttributes,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: nil
        )
    }
}

private struct UserDetailsHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @EnvironmentObject private var state: ThunderIDState
    @State private var userType: ManagedUserTypeDetails?
    @State private var userTypeError: Error?
    @StateObject private var user: ResourceQuery<ManagedUser>
    @StateObject private var groups: ResourceQuery<MembershipGroupListResponse>
    @StateObject private var deletion: ResourceMutation<String, Void>
    @StateObject private var update: ResourceMutation<(id: String, request: UpdateManagedUserRequest), ManagedUser>
    @StateObject private var lifecycleFlows: ResourceQuery<[AdministrationFlowConfigKey: String]>
    @StateObject private var lifecycle: ResourceMutation<AccountLifecycleInput, AccountLifecycleResult>
    @StateObject private var verification: ResourceMutation<
        (id: String, attribute: String), UserAttributeVerificationResult
    >
    @StateObject private var verificationFlow: ResourceQuery<[AdministrationFlowConfigKey: String]>
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
        _verification = StateObject(wrappedValue: state.sendUserAttributeVerificationMutation())
        _verificationFlow = StateObject(wrappedValue: state.adminAttributeVerificationFlowQuery())
        self.props = props
    }

    var body: some View {
        BaseUserDetails(
            user: user.data,
            groups: groups.data?.groups ?? [],
            userSchema: userType?.handle == user.data?.type ? userType?.schema : nil,
            hiddenAttributes: props.hiddenAttributes,
            isLoading: user.isLoading,
            error: i18n.managementErrorMessage(user.error, fallbackKey: "admin.users.details.error")
                ?? i18n.managementErrorMessage(deletion.error, fallbackKey: "admin.users.details.delete.error")
                ?? i18n.managementErrorMessage(update.error, fallbackKey: "admin.users.details.edit.error")
                ?? i18n.managementErrorMessage(
                    verification.error,
                    fallbackKey: "admin.users.details.verification.error"
                )
                ?? i18n.managementErrorMessage(lifecycle.error, fallbackKey: "admin.common.lifecycle.error")
                ?? i18n.managementErrorMessage(lifecycleFlows.error, fallbackKey: "admin.common.lifecycle.load_error")
                ?? i18n.managementErrorMessage(
                    verificationFlow.error ?? userTypeError,
                    fallbackKey: "admin.users.details.verification.load_error"
                ),
            isDeleting: deletion.isLoading,
            isUpdating: update.isLoading || user.isLoading,
            onDelete: props.deletable ? delete : nil,
            onUpdate: props.editable && user.data != nil ? save : nil,
            isRunningLifecycleAction: lifecycle.isLoading,
            lifecycleActions: availableLifecycleActions,
            onLifecycleAction: props.lifecycleActions ? runLifecycleAction : nil,
            isSendingVerification: verification.isLoading,
            sentVerification: verification.data,
            onSendVerification: verificationHandle == nil ? nil : sendVerification,
            actions: props.actions,
            renderContent: props.content
        )
        .task {
            async let loadUser: Void = { _ = await user.refetch() }()
            async let loadGroups: Void = { _ = await groups.refetch() }()
            _ = await (loadUser, loadGroups)
        }
        .task(id: typeHandle) {
            userType = nil
            userTypeError = nil
            guard let typeHandle else { return }
            do {
                let result = try await state.lookupUserType(handle: typeHandle)
                if !Task.isCancelled { userType = result }
            } catch {
                if !Task.isCancelled { userTypeError = error }
            }
        }
        .task(id: props.lifecycleActions) {
            if props.lifecycleActions { await lifecycleFlows.refetch() }
        }
        .task(id: props.attributeVerification) {
            if props.attributeVerification { await verificationFlow.refetch() }
        }
    }

    private var typeHandle: String? {
        verificationUserTypeHandle(user: user.data, attributeVerification: props.attributeVerification)
    }

    private var availableLifecycleActions: [AccountLifecycleAction] {
        guard props.lifecycleActions, let flows = lifecycleFlows.data else { return [] }
        return AccountLifecycleAction.available(for: .user, status: user.data?.status?.value, configuredFlows: flows)
    }

    private func runLifecycleAction(_ action: AccountLifecycleAction, operatorNote: String?) {
        let input = AccountLifecycleInput(subject: props.userId, action: action, operatorNote: operatorNote)
        Task { await lifecycle.mutate(input) }
    }

    /// The configured verification flow handle, or `nil` when the action is off or the server sets none.
    private var verificationHandle: String? {
        adminVerificationFlowHandle(enabled: props.attributeVerification, configuredFlows: verificationFlow.data)
    }

    private func sendVerification(_ attribute: String) {
        Task {
            guard !update.isLoading, !user.isLoading, !verification.isLoading else { return }
            verification.reset()
            await verification.mutate((id: props.userId, attribute: attribute))
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
        Task {
            guard !update.isLoading, !verification.isLoading else { return }
            verification.reset()
            await update.mutate((id: props.userId, request: request))
        }
    }
}

/// The handle of the administrator-initiated verification flow to send a link through, or `nil` when the
/// action is off or the server names none.
func adminVerificationFlowHandle(
    enabled: Bool,
    configuredFlows: [AdministrationFlowConfigKey: String]?
) -> String? {
    guard enabled, let handle = configuredFlows?[.adminAttributeVerification], !handle.isEmpty else { return nil }
    return handle
}

/// The user type to read for verification status, only while the verification action is on.
func verificationUserTypeHandle(user: ManagedUser?, attributeVerification: Bool) -> String? {
    guard attributeVerification, let user, user.verifiedAttributes != nil else { return nil }
    return user.type
}
