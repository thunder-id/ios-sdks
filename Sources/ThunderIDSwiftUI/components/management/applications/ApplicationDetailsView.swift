// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// An application's details, loaded through the management API. Set `editable` to let the signed-in
/// user edit the general fields and OAuth basics, `deletable` to let them delete the application, and
/// `secretRegenerable` to let them issue a new client secret; all are off by default, and deleting and
/// regenerating ask for confirmation first. A new secret is shown once. Applications are guarded by the
/// root `system` permission (the server defines no application-specific one), so turn the actions on
/// only for a user who holds it; a refused request shows the translated forbidden message.
/// `administrationMode` chooses how deleting and regenerating the secret run (`.native` by default).
/// Set `lifecycleActions` to let them suspend and unsuspend the application: each action runs through
/// its administration flow and is offered only when the status allows it and the server configures its
/// flow. The configured flows are read only while it is on.
public struct ApplicationDetails<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let applicationId: String
    let editable: Bool
    let deletable: Bool
    let secretRegenerable: Bool
    let administrationMode: AdministrationMode
    let lifecycleActions: Bool
    let onDeleted: (() -> Void)?
    let actions: AnyView?
    let content: ((ApplicationDetailsState) -> Content)?

    init(
        applicationId: String,
        editable: Bool = false,
        deletable: Bool = false,
        secretRegenerable: Bool = false,
        administrationMode: AdministrationMode = .native,
        lifecycleActions: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((ApplicationDetailsState) -> Content)?
    ) {
        self.applicationId = applicationId
        self.editable = editable
        self.deletable = deletable
        self.secretRegenerable = secretRegenerable
        self.administrationMode = administrationMode
        self.lifecycleActions = lifecycleActions
        self.onDeleted = onDeleted
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameters:
    ///   - administrationMode: How deleting and regenerating the secret run. See ``AdministrationMode``.
    ///   - lifecycleActions: Whether to offer suspending and unsuspending. Off by default.
    ///   - content: Renders custom UI in place of the default view. See ``BaseApplicationDetails``.
    public init(
        applicationId: String,
        editable: Bool = false,
        deletable: Bool = false,
        secretRegenerable: Bool = false,
        administrationMode: AdministrationMode = .native,
        lifecycleActions: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (ApplicationDetailsState) -> Content
    ) {
        self.init(
            applicationId: applicationId,
            editable: editable,
            deletable: deletable,
            secretRegenerable: secretRegenerable,
            administrationMode: administrationMode,
            lifecycleActions: lifecycleActions,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        ApplicationDetailsHost(state: thunderState, props: self).id(applicationId)
    }
}

public extension ApplicationDetails where Content == EmptyView {
    init(
        applicationId: String,
        editable: Bool = false,
        deletable: Bool = false,
        secretRegenerable: Bool = false,
        administrationMode: AdministrationMode = .native,
        lifecycleActions: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            applicationId: applicationId,
            editable: editable,
            deletable: deletable,
            secretRegenerable: secretRegenerable,
            administrationMode: administrationMode,
            lifecycleActions: lifecycleActions,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: nil
        )
    }
}

private struct ApplicationDetailsHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var application: ResourceQuery<Application>
    @StateObject private var deletion: ResourceMutation<String, Void>
    @StateObject private var update: ResourceMutation<(id: String, request: ApplicationRequest), Application>
    @StateObject private var regeneration: ResourceMutation<String, RegenerateClientSecretResult>
    @StateObject private var lifecycleFlows: ResourceQuery<[AdministrationFlowConfigKey: String]>
    @StateObject private var lifecycle: ResourceMutation<AccountLifecycleInput, AccountLifecycleResult>
    @State private var clientSecret: String?
    let props: ApplicationDetails<Content>

    init(state: ThunderIDState, props: ApplicationDetails<Content>) {
        _application = StateObject(wrappedValue: state.applicationQuery(id: props.applicationId))
        _deletion = StateObject(
            wrappedValue: state.deleteApplicationMutation(administrationMode: props.administrationMode)
        )
        _update = StateObject(wrappedValue: state.updateApplicationMutation())
        _regeneration = StateObject(
            wrappedValue: state.regenerateClientSecretMutation(administrationMode: props.administrationMode)
        )
        _lifecycleFlows = StateObject(wrappedValue: state.accountLifecycleFlowsQuery(kind: .application))
        _lifecycle = StateObject(wrappedValue: state.accountLifecycleMutation(kind: .application))
        self.props = props
    }

    var body: some View {
        BaseApplicationDetails(
            application: application.data,
            isLoading: application.isLoading,
            error: errorMessage,
            isDeleting: deletion.isLoading,
            isUpdating: update.isLoading,
            isRegeneratingSecret: regeneration.isLoading,
            clientSecret: clientSecret,
            onSecretDone: { clientSecret = nil },
            onDelete: props.deletable ? delete : nil,
            onUpdate: props.editable && application.data != nil ? save : nil,
            onRegenerateSecret: props.secretRegenerable ? regenerate : nil,
            isRunningLifecycleAction: lifecycle.isLoading,
            lifecycleActions: availableLifecycleActions,
            onLifecycleAction: props.lifecycleActions ? runLifecycleAction : nil,
            actions: props.actions,
            renderContent: props.content
        )
        .task { await application.refetch() }
        .task(id: props.lifecycleActions) {
            if props.lifecycleActions { await lifecycleFlows.refetch() }
        }
    }

    private var availableLifecycleActions: [AccountLifecycleAction] {
        guard props.lifecycleActions, let flows = lifecycleFlows.data else { return [] }
        return AccountLifecycleAction.available(
            for: .application,
            status: application.data?.status?.accessStatus,
            configuredFlows: flows
        )
    }

    private func runLifecycleAction(_ action: AccountLifecycleAction, operatorNote: String?) {
        let input = AccountLifecycleInput(subject: props.applicationId, action: action, operatorNote: operatorNote)
        Task { await lifecycle.mutate(input) }
    }

    private var errorMessage: String? {
        i18n.managementErrorMessage(application.error, fallbackKey: "admin.applications.details.error")
            ?? i18n.managementErrorMessage(deletion.error, fallbackKey: "admin.applications.details.delete.error")
            ?? i18n.managementErrorMessage(update.error, fallbackKey: "admin.applications.details.edit.error")
            ?? i18n.managementErrorMessage(regeneration.error, fallbackKey: "admin.applications.details.secret.error")
            ?? i18n.managementErrorMessage(lifecycle.error, fallbackKey: "admin.common.lifecycle.error")
            ?? i18n.managementErrorMessage(lifecycleFlows.error, fallbackKey: "admin.common.lifecycle.load_error")
    }

    private func delete() {
        Task {
            if await deletion.mutate(props.applicationId) != nil {
                props.onDeleted?()
            }
        }
    }

    private func save(_ edit: ApplicationEdit) {
        guard let current = application.data else { return }
        let request = current.request.applying(edit)
        Task { await update.mutate((id: props.applicationId, request: request)) }
    }

    private func regenerate() {
        Task {
            if let result = await regeneration.mutate(props.applicationId) {
                clientSecret = result.clientSecret
                await application.refetch()
            }
        }
    }
}
