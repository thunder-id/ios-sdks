// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A project's overview (handle, display name, description, created), rendered from the data it is
/// given. Editing the display name and description is offered only when `onUpdate` is set, and deleting
/// only when `onDelete` is set; a delete asks for confirmation first.
public struct BaseProjectDetails<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let project: Project?
    let isLoading: Bool
    let error: String?
    let isUpdating: Bool
    let isDeleting: Bool
    let onUpdate: ((UpdateProjectRequest) -> Void)?
    let onDelete: (() -> Void)?
    let actions: AnyView?
    let content: ((ProjectDetailsState) -> Content)?

    @State private var isEditing = false
    @State private var displayName = ""
    @State private var projectDescription = ""

    init(
        project: Project?,
        isLoading: Bool = false,
        error: String? = nil,
        isUpdating: Bool = false,
        isDeleting: Bool = false,
        onUpdate: ((UpdateProjectRequest) -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((ProjectDetailsState) -> Content)?
    ) {
        self.project = project
        self.isLoading = isLoading
        self.error = error
        self.isUpdating = isUpdating
        self.isDeleting = isDeleting
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view, from the project, the loading
    ///   and error state, and the update and delete actions.
    public init(
        project: Project?,
        isLoading: Bool = false,
        error: String? = nil,
        isUpdating: Bool = false,
        isDeleting: Bool = false,
        onUpdate: ((UpdateProjectRequest) -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (ProjectDetailsState) -> Content
    ) {
        self.init(
            project: project,
            isLoading: isLoading,
            error: error,
            isUpdating: isUpdating,
            isDeleting: isDeleting,
            onUpdate: onUpdate,
            onDelete: onDelete,
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

    private var renderState: ProjectDetailsState {
        ProjectDetailsState(
            project: project,
            isLoading: isLoading,
            error: error,
            isUpdating: isUpdating,
            isDeleting: isDeleting,
            onUpdate: project != nil ? onUpdate : nil,
            onDelete: project != nil ? onDelete : nil
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        if let project {
            details(project)
        } else {
            AdminSection(identifier: "admin-project-details") {
                if isLoading {
                    AdminLoadingRow(label: i18n.resolve("admin.common.loading"))
                } else {
                    AdminErrorBanner(message: error ?? i18n.resolve("admin.common.errors.not_found"))
                }
            }
        }
    }

    private func details(_ project: Project) -> some View {
        AdminSection(
            identifier: "admin-project-details",
            title: project.displayName,
            description: project.description,
            actions: { headerActions(project) },
            content: {
                if let error {
                    AdminErrorBanner(message: error)
                }
                if isEditing {
                    editForm(project)
                } else {
                    AdminPanel(title: i18n.resolve("admin.projects.details.overview")) {
                        AdminDetailList(items: [
                            (i18n.resolve("admin.projects.fields.handle"), project.handle),
                            (i18n.resolve("admin.projects.fields.display_name"), project.displayName),
                            (i18n.resolve("admin.projects.fields.description"), project.description ?? ""),
                            (i18n.resolve("admin.projects.details.created"), AdminHandle.date(project.createdAt))
                        ])
                    }
                }
            }
        )
    }

    private func editForm(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AdminTextField(
                label: i18n.resolve("admin.projects.fields.display_name"),
                name: "displayName",
                isRequired: true,
                text: $displayName
            )
            AdminTextField(
                label: i18n.resolve("admin.projects.fields.description"),
                name: "description",
                text: $projectDescription
            )
            AdminFormActions(
                i18n: i18n,
                submitLabel: i18n.resolve("admin.projects.details.edit.save"),
                isSubmitting: isUpdating,
                canSubmit: AdminHandle.optional(displayName) != nil,
                onCancel: { isEditing = false },
                onSubmit: {
                    guard let name = AdminHandle.optional(displayName) else { return }
                    onUpdate?(
                        UpdateProjectRequest(
                            displayName: name,
                            description: AdminHandle.optional(projectDescription),
                            handle: project.handle
                        )
                    )
                    isEditing = false
                }
            )
        }
    }

    private func headerActions(_ project: Project) -> some View {
        HStack(spacing: 8) {
            actions
            if onUpdate != nil, !isEditing {
                Button(i18n.resolve("admin.projects.details.edit.action")) {
                    displayName = project.displayName
                    projectDescription = project.description ?? ""
                    isEditing = true
                }
                .accessibilityIdentifier("admin-project-details-edit")
            }
            if let onDelete {
                AdminConfirmButton(
                    i18n: i18n,
                    title: i18n.resolve("admin.projects.details.delete.action"),
                    confirmText: i18n.resolve("admin.projects.details.delete.confirm", ["name": project.displayName]),
                    isLoading: isDeleting,
                    identifier: "admin-project-details-delete",
                    onConfirm: onDelete
                )
            }
        }
    }
}

public extension BaseProjectDetails where Content == EmptyView {
    init(
        project: Project?,
        isLoading: Bool = false,
        error: String? = nil,
        isUpdating: Bool = false,
        isDeleting: Bool = false,
        onUpdate: ((UpdateProjectRequest) -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            project: project,
            isLoading: isLoading,
            error: error,
            isUpdating: isUpdating,
            isDeleting: isDeleting,
            onUpdate: onUpdate,
            onDelete: onDelete,
            actions: actions,
            renderContent: nil
        )
    }
}

/// A project's details, loaded through the management API. Set `editable` to let the signed-in user
/// change the display name and description, and `deletable` to let them delete the project; both are
/// off by default, and a delete asks for confirmation first. Only the Control Plane serves projects.
public struct ProjectDetails<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let projectId: String
    let editable: Bool
    let deletable: Bool
    let onDeleted: (() -> Void)?
    let actions: AnyView?
    let content: ((ProjectDetailsState) -> Content)?

    init(
        projectId: String,
        editable: Bool = false,
        deletable: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((ProjectDetailsState) -> Content)?
    ) {
        self.projectId = projectId
        self.editable = editable
        self.deletable = deletable
        self.onDeleted = onDeleted
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view. See ``BaseProjectDetails``.
    public init(
        projectId: String,
        editable: Bool = false,
        deletable: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (ProjectDetailsState) -> Content
    ) {
        self.init(
            projectId: projectId,
            editable: editable,
            deletable: deletable,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        ProjectDetailsHost(state: thunderState, props: self).id(projectId)
    }
}

public extension ProjectDetails where Content == EmptyView {
    init(
        projectId: String,
        editable: Bool = false,
        deletable: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            projectId: projectId,
            editable: editable,
            deletable: deletable,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: nil
        )
    }
}

private struct ProjectDetailsHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var project: ResourceQuery<Project>
    @StateObject private var update: ResourceMutation<(id: String, request: UpdateProjectRequest), Project>
    @StateObject private var deletion: ResourceMutation<String, Void>
    let props: ProjectDetails<Content>

    init(state: ThunderIDState, props: ProjectDetails<Content>) {
        _project = StateObject(wrappedValue: state.projectQuery(id: props.projectId))
        _update = StateObject(wrappedValue: state.updateProjectMutation())
        _deletion = StateObject(wrappedValue: state.deleteProjectMutation())
        self.props = props
    }

    var body: some View {
        BaseProjectDetails(
            project: project.data,
            isLoading: project.isLoading,
            error: errorMessage,
            isUpdating: update.isLoading,
            isDeleting: deletion.isLoading,
            onUpdate: props.editable ? save : nil,
            onDelete: props.deletable ? delete : nil,
            actions: props.actions,
            renderContent: props.content
        )
        .task { await project.refetch() }
    }

    private var errorMessage: String? {
        i18n.managementErrorMessage(project.error, fallbackKey: "admin.projects.details.error")
            ?? i18n.managementErrorMessage(
                update.error,
                fallbackKey: "admin.projects.details.edit.error",
                codeKeys: AdminHierarchyErrors.projectKeys
            )
            ?? i18n.managementErrorMessage(deletion.error, fallbackKey: "admin.projects.details.delete.error")
    }

    private func save(_ request: UpdateProjectRequest) {
        Task { await update.mutate((id: props.projectId, request: request)) }
    }

    private func delete() {
        Task {
            if await deletion.mutate(props.projectId) != nil {
                props.onDeleted?()
            }
        }
    }
}
