// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// The handle rule projects and organization units share: lowercase letters, numbers, hyphens and
/// underscores, starting and ending with a letter or a number.
enum AdminHandle {
    static func isValid(_ handle: String) -> Bool {
        handle.count <= 100 && handle.range(of: "^[a-z0-9]([a-z0-9_-]*[a-z0-9])?$", options: .regularExpression) != nil
    }

    /// An RFC 3339 timestamp as a medium date and short time in the current locale, or the text as given
    /// when it does not parse.
    static func date(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: text) ?? ISO8601DateFormatter().date(from: text)
        return date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? text
    }

    /// `nil` for blank text, otherwise the trimmed text.
    static func optional(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The server's error codes a project or organization unit write maps to its own message.
enum AdminHierarchyErrors {
    /// Project create and update: `PRJ-1006` the id and `PRJ-1012` the handle is already used, and
    /// `PRJ-1007` the handle cannot be changed.
    static let projectKeys = [
        "PRJ-1006": "admin.projects.errors.id_conflict",
        "PRJ-1012": "admin.projects.errors.handle_conflict",
        "PRJ-1007": "admin.projects.errors.handle_immutable"
    ]

    /// Organization unit create and update: `OU-1004` the name and `OU-1008` the handle is already used,
    /// and `OU-1012` the unit is a declarative resource that cannot be modified.
    static let organizationUnitKeys = [
        "OU-1004": "admin.organization_units.errors.name_conflict",
        "OU-1008": "admin.organization_units.errors.handle_conflict",
        "OU-1012": "admin.organization_units.errors.declarative"
    ]

    /// Organization unit delete: `OU-1006` the unit still has child units, users, groups or other
    /// resources, and `OU-1012` the unit is a declarative resource. The server never refuses a project
    /// delete, so it has no codes of its own.
    static let organizationUnitDeleteKeys = [
        "OU-1006": "admin.organization_units.details.delete.has_children",
        "OU-1012": "admin.organization_units.errors.declarative"
    ]
}

/// A form for creating a project: its handle, display name and description.
public struct BaseProjectCreate<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let error: String?
    let isSubmitting: Bool
    let title: String?
    let description: String?
    let onCancel: (() -> Void)?
    let onSubmit: (CreateProjectRequest) -> Void
    let content: ((ProjectFormState) -> Content)?

    @State private var handle = ""
    @State private var displayName = ""
    @State private var projectDescription = ""

    init(
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (CreateProjectRequest) -> Void,
        renderContent: ((ProjectFormState) -> Content)?
    ) {
        self.error = error
        self.isSubmitting = isSubmitting
        self.title = title
        self.description = description
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default form, from bindings to the handle,
    ///   display name and description, the submit action and the submission state.
    public init(
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (CreateProjectRequest) -> Void,
        @ViewBuilder content: @escaping (ProjectFormState) -> Content
    ) {
        self.init(
            error: error,
            isSubmitting: isSubmitting,
            title: title,
            description: description,
            onCancel: onCancel,
            onSubmit: onSubmit,
            renderContent: content
        )
    }

    public var body: some View {
        if let content {
            content(
                ProjectFormState(
                    handle: $handle,
                    displayName: $displayName,
                    description: $projectDescription,
                    isValid: isValid,
                    isSubmitting: isSubmitting,
                    error: error,
                    submit: submit,
                    onCancel: onCancel
                )
            )
        } else {
            form
        }
    }

    private var form: some View {
        AdminSection(
            identifier: "admin-project-create",
            title: title ?? i18n.resolve("admin.projects.create.title"),
            description: description
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let error {
                    AdminErrorBanner(message: error)
                }
                AdminTextField(
                    label: i18n.resolve("admin.projects.fields.display_name"),
                    name: "displayName",
                    isRequired: true,
                    text: $displayName
                )
                AdminTextField(
                    label: i18n.resolve("admin.projects.fields.handle"),
                    name: "handle",
                    isRequired: true,
                    text: $handle
                )
                Text(i18n.resolve("admin.projects.fields.handle_hint"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                AdminTextField(
                    label: i18n.resolve("admin.projects.fields.description"),
                    name: "description",
                    text: $projectDescription
                )
                AdminFormActions(
                    i18n: i18n,
                    submitLabel: i18n.resolve("admin.projects.create.submit"),
                    isSubmitting: isSubmitting,
                    canSubmit: isValid,
                    onCancel: onCancel,
                    onSubmit: submit
                )
            }
        }
    }

    private var trimmedHandle: String { handle.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool { AdminHandle.isValid(trimmedHandle) && AdminHandle.optional(displayName) != nil }

    private func submit() {
        guard isValid, !isSubmitting, let name = AdminHandle.optional(displayName) else { return }
        onSubmit(
            CreateProjectRequest(
                handle: trimmedHandle,
                displayName: name,
                description: AdminHandle.optional(projectDescription)
            )
        )
    }
}

public extension BaseProjectCreate where Content == EmptyView {
    init(
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (CreateProjectRequest) -> Void
    ) {
        self.init(
            error: error,
            isSubmitting: isSubmitting,
            title: title,
            description: description,
            onCancel: onCancel,
            onSubmit: onSubmit,
            renderContent: nil
        )
    }
}

/// Creates a project through the management API. Only the Control Plane serves projects.
public struct ProjectCreate<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let title: String?
    let description: String?
    let onCancel: (() -> Void)?
    let onCreated: ((Project) -> Void)?
    let content: ((ProjectFormState) -> Content)?

    init(
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((Project) -> Void)? = nil,
        renderContent: ((ProjectFormState) -> Content)?
    ) {
        self.title = title
        self.description = description
        self.onCancel = onCancel
        self.onCreated = onCreated
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default form. See ``BaseProjectCreate``.
    public init(
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((Project) -> Void)? = nil,
        @ViewBuilder content: @escaping (ProjectFormState) -> Content
    ) {
        self.init(
            title: title,
            description: description,
            onCancel: onCancel,
            onCreated: onCreated,
            renderContent: content
        )
    }

    public var body: some View {
        ProjectCreateHost(state: thunderState, props: self)
    }
}

public extension ProjectCreate where Content == EmptyView {
    init(
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((Project) -> Void)? = nil
    ) {
        self.init(title: title, description: description, onCancel: onCancel, onCreated: onCreated, renderContent: nil)
    }
}

private struct ProjectCreateHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var mutation: ResourceMutation<CreateProjectRequest, Project>
    let props: ProjectCreate<Content>

    init(state: ThunderIDState, props: ProjectCreate<Content>) {
        _mutation = StateObject(wrappedValue: state.createProjectMutation())
        self.props = props
    }

    var body: some View {
        BaseProjectCreate(
            error: i18n.managementErrorMessage(
                mutation.error,
                fallbackKey: "admin.projects.create.error",
                codeKeys: AdminHierarchyErrors.projectKeys
            ),
            isSubmitting: mutation.isLoading,
            title: props.title,
            description: props.description,
            onCancel: props.onCancel,
            onSubmit: { request in
                Task {
                    if let project = await mutation.mutate(request) { props.onCreated?(project) }
                }
            },
            renderContent: props.content
        )
    }
}
