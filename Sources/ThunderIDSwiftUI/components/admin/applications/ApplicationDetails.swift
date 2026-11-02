// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// What ``BaseApplicationDetails`` hands its `content` closure.
public struct ApplicationDetailsState {
    public let application: Application?
    public let isLoading: Bool
    /// A translated message, or `nil` when there is nothing to report.
    public let error: String?
    public let isDeleting: Bool
    public let isUpdating: Bool
    public let isRegeneratingSecret: Bool
    /// A client secret just issued. Show it once, then call `onSecretDone`.
    public let clientSecret: String?
    public let onSecretDone: (() -> Void)?
    /// Deletes the application. Ask for confirmation first. `nil` when deletion is not allowed,
    /// including for read-only applications.
    public let onDelete: (() -> Void)?
    /// Saves the edited fields. `nil` when editing is not allowed, including for read-only applications.
    public let onUpdate: ((ApplicationEdit) -> Void)?
    /// Issues a new client secret. Ask for confirmation first. `nil` when it is not allowed, for a
    /// read-only application, or for one with no confidential OAuth client.
    public let onRegenerateSecret: (() -> Void)?
    public let isRunningLifecycleAction: Bool
    /// The account lifecycle actions offered for the application, most expected first. Empty when none
    /// is allowed.
    public let lifecycleActions: [AccountLifecycleAction]
    /// Runs an account lifecycle action. An application's suspension takes no operator note, so the
    /// note is `nil`. Ask for confirmation before suspending or unsuspending. `nil` when no lifecycle
    /// action is allowed.
    public let onLifecycleAction: ((AccountLifecycleAction, String?) -> Void)?
}

/// An application's overview and OAuth settings, rendered from the data it is given. Editing, deleting
/// and regenerating the client secret are offered only when their callbacks are set, and never for a
/// read-only application; deleting and regenerating ask for confirmation first. The account lifecycle
/// actions in `lifecycleActions` (suspend and unsuspend; applications are never locked) are offered only
/// when `onLifecycleAction` is set, for read-only applications too, and ask for confirmation first.
public struct BaseApplicationDetails<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let application: Application?
    let isLoading: Bool
    let error: String?
    let isDeleting: Bool
    let isUpdating: Bool
    let isRegeneratingSecret: Bool
    let clientSecret: String?
    let onSecretDone: (() -> Void)?
    let onDelete: (() -> Void)?
    let onUpdate: ((ApplicationEdit) -> Void)?
    let onRegenerateSecret: (() -> Void)?
    let isRunningLifecycleAction: Bool
    let lifecycleActions: [AccountLifecycleAction]
    let onLifecycleAction: ((AccountLifecycleAction, String?) -> Void)?
    let actions: AnyView?
    let content: ((ApplicationDetailsState) -> Content)?

    @State private var isEditing = false

    init(
        application: Application?,
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        isUpdating: Bool = false,
        isRegeneratingSecret: Bool = false,
        clientSecret: String? = nil,
        onSecretDone: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onUpdate: ((ApplicationEdit) -> Void)? = nil,
        onRegenerateSecret: (() -> Void)? = nil,
        isRunningLifecycleAction: Bool = false,
        lifecycleActions: [AccountLifecycleAction] = [],
        onLifecycleAction: ((AccountLifecycleAction, String?) -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((ApplicationDetailsState) -> Content)?
    ) {
        self.application = application
        self.isLoading = isLoading
        self.error = error
        self.isDeleting = isDeleting
        self.isUpdating = isUpdating
        self.isRegeneratingSecret = isRegeneratingSecret
        self.clientSecret = clientSecret
        self.onSecretDone = onSecretDone
        self.onDelete = onDelete
        self.onUpdate = onUpdate
        self.onRegenerateSecret = onRegenerateSecret
        self.isRunningLifecycleAction = isRunningLifecycleAction
        self.lifecycleActions = lifecycleActions
        self.onLifecycleAction = onLifecycleAction
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view, from the application, the
    ///   loading and error state, the issued client secret, and the actions the app allows, including the
    ///   lifecycle actions.
    public init(
        application: Application?,
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        isUpdating: Bool = false,
        isRegeneratingSecret: Bool = false,
        clientSecret: String? = nil,
        onSecretDone: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onUpdate: ((ApplicationEdit) -> Void)? = nil,
        onRegenerateSecret: (() -> Void)? = nil,
        isRunningLifecycleAction: Bool = false,
        lifecycleActions: [AccountLifecycleAction] = [],
        onLifecycleAction: ((AccountLifecycleAction, String?) -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (ApplicationDetailsState) -> Content
    ) {
        self.init(
            application: application,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            isUpdating: isUpdating,
            isRegeneratingSecret: isRegeneratingSecret,
            clientSecret: clientSecret,
            onSecretDone: onSecretDone,
            onDelete: onDelete,
            onUpdate: onUpdate,
            onRegenerateSecret: onRegenerateSecret,
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

    private var isWritable: Bool { application != nil && application?.isReadOnly != true }

    /// Only a confidential OAuth client has a secret to regenerate.
    private var hasSecret: Bool {
        guard let config = application?.oauthConfig else { return false }
        return config.publicClient != true
    }

    var renderState: ApplicationDetailsState {
        ApplicationDetailsState(
            application: application,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            isUpdating: isUpdating,
            isRegeneratingSecret: isRegeneratingSecret,
            clientSecret: clientSecret,
            onSecretDone: onSecretDone,
            onDelete: isWritable ? onDelete : nil,
            onUpdate: isWritable ? onUpdate : nil,
            onRegenerateSecret: isWritable && hasSecret ? onRegenerateSecret : nil,
            isRunningLifecycleAction: isRunningLifecycleAction,
            lifecycleActions: onLifecycleAction != nil && application != nil ? lifecycleActions : [],
            onLifecycleAction: application != nil ? onLifecycleAction : nil
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        if let application {
            details(application, state: renderState)
        } else {
            AdminSection(identifier: "admin-application-details") {
                if isLoading {
                    AdminLoadingRow(label: i18n.resolve("admin.common.loading"))
                } else {
                    AdminErrorBanner(message: error ?? i18n.resolve("admin.common.errors.not_found"))
                }
            }
        }
    }

    private func details(_ application: Application, state: ApplicationDetailsState) -> some View {
        AdminSection(
            identifier: "admin-application-details",
            title: application.name,
            description: application.description,
            actions: { headerActions(application, state: state) },
            content: {
                if let error {
                    AdminErrorBanner(message: error)
                }
                if let clientSecret {
                    ApplicationSecretNotice(i18n: i18n, secret: clientSecret) { onSecretDone?() }
                }
                if isEditing, let onUpdate = state.onUpdate {
                    AdminPanel(title: i18n.resolve("admin.applications.details.overview")) {
                        ApplicationEditForm(
                            i18n: i18n,
                            edit: ApplicationEdit(application),
                            hasOAuth: application.oauthConfig != nil,
                            publicClient: application.oauthConfig?.publicClient == true,
                            isUpdating: isUpdating,
                            onCancel: { isEditing = false },
                            onSave: { edit in
                                onUpdate(edit)
                                isEditing = false
                            }
                        )
                    }
                } else {
                    ApplicationOverview(i18n: i18n, application: application)
                }
            }
        )
    }

    private func headerActions(_ application: Application, state: ApplicationDetailsState) -> some View {
        HStack(spacing: 8) {
            actions
            if state.onUpdate != nil, !isEditing {
                Button(i18n.resolve("admin.applications.details.edit.action")) { isEditing = true }
                    .accessibilityIdentifier("admin-application-details-edit")
            }
            if let run = state.onLifecycleAction {
                AccountLifecycleButtons(
                    i18n: i18n,
                    actions: state.lifecycleActions,
                    isRunning: isRunningLifecycleAction,
                    name: application.name,
                    identifier: "admin-application-details-lifecycle",
                    onAction: run
                )
            }
            if let regenerate = state.onRegenerateSecret {
                AdminConfirmButton(
                    i18n: i18n,
                    title: i18n.resolve("admin.applications.details.secret.action"),
                    confirmText: i18n.resolve("admin.applications.details.secret.confirm", ["name": application.name]),
                    isLoading: isRegeneratingSecret,
                    identifier: "admin-application-details-secret",
                    onConfirm: regenerate
                )
            }
            if let delete = state.onDelete {
                AdminConfirmButton(
                    i18n: i18n,
                    title: i18n.resolve("admin.applications.details.delete.action"),
                    confirmText: i18n.resolve("admin.applications.details.delete.confirm", ["name": application.name]),
                    isLoading: isDeleting,
                    identifier: "admin-application-details-delete",
                    onConfirm: delete
                )
            }
        }
    }
}

public extension BaseApplicationDetails where Content == EmptyView {
    init(
        application: Application?,
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        isUpdating: Bool = false,
        isRegeneratingSecret: Bool = false,
        clientSecret: String? = nil,
        onSecretDone: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onUpdate: ((ApplicationEdit) -> Void)? = nil,
        onRegenerateSecret: (() -> Void)? = nil,
        isRunningLifecycleAction: Bool = false,
        lifecycleActions: [AccountLifecycleAction] = [],
        onLifecycleAction: ((AccountLifecycleAction, String?) -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            application: application,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            isUpdating: isUpdating,
            isRegeneratingSecret: isRegeneratingSecret,
            clientSecret: clientSecret,
            onSecretDone: onSecretDone,
            onDelete: onDelete,
            onUpdate: onUpdate,
            onRegenerateSecret: onRegenerateSecret,
            isRunningLifecycleAction: isRunningLifecycleAction,
            lifecycleActions: lifecycleActions,
            onLifecycleAction: onLifecycleAction,
            actions: actions,
            renderContent: nil
        )
    }
}

/// The overview and OAuth panels of an application.
struct ApplicationOverview: View {
    let i18n: ThunderIDI18n
    let application: Application

    var body: some View {
        let notSet = i18n.resolve("admin.applications.details.not_set")
        let config = application.oauthConfig
        var overview: [(label: String, value: String)] = [
            (i18n.resolve("admin.applications.details.type"), application.template ?? application.type ?? notSet),
            (i18n.resolve("admin.common.columns.organization_unit"), application.ouId ?? notSet),
            (i18n.resolve("admin.applications.fields.url"), application.url ?? notSet)
        ]
        if let status = application.status {
            overview.append((i18n.resolve("admin.applications.list.columns.status"), i18n.applicationStatus(status)))
        }
        return VStack(alignment: .leading, spacing: 12) {
            AdminPanel(title: i18n.resolve("admin.applications.details.overview")) {
                AdminDetailList(items: overview)
            }
            if let config {
                AdminPanel(title: i18n.resolve("admin.applications.details.oauth")) {
                    AdminDetailList(items: [
                        (i18n.resolve("admin.applications.list.columns.client_id"), config.clientId ?? notSet),
                        (
                            i18n.resolve("admin.applications.details.public_client"),
                            i18n.resolve(config.publicClient == true
                                ? "admin.applications.details.yes"
                                : "admin.applications.details.no")
                        )
                    ])
                    AdminChipList(
                        label: i18n.resolve("admin.applications.fields.grant_types"),
                        emptyText: i18n.resolve("admin.applications.details.no_grant_types"),
                        items: config.grantTypes.map { ($0, i18n.grantTypeLabel($0)) }
                    )
                    AdminChipList(
                        label: i18n.resolve("admin.applications.fields.redirect_uris"),
                        emptyText: i18n.resolve("admin.applications.details.no_redirect_uris"),
                        items: (config.redirectUris ?? []).map { ($0, $0) }
                    )
                }
            }
        }
    }
}
