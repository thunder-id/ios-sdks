// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A form for creating an organization unit: its name, handle, description and parent. With `parentId`
/// the parent is fixed; otherwise it is picked from `parents`, starting at `defaultParentId`, and may be
/// left empty for a root unit.
public struct BaseOrganizationUnitCreate<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let parentId: String?
    let parents: [AdminOption]
    let error: String?
    let isSubmitting: Bool
    let title: String?
    let description: String?
    let onCancel: (() -> Void)?
    let onSubmit: (OrganizationUnitRequest) -> Void
    let content: ((OrganizationUnitFormState) -> Content)?

    @State private var name = ""
    @State private var handle = ""
    @State private var unitDescription = ""
    @State private var parent: String

    init(
        parentId: String? = nil,
        defaultParentId: String? = nil,
        parents: [AdminOption] = [],
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (OrganizationUnitRequest) -> Void,
        renderContent: ((OrganizationUnitFormState) -> Content)?
    ) {
        self.parentId = parentId
        self.parents = parents
        self.error = error
        self.isSubmitting = isSubmitting
        self.title = title
        self.description = description
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        self.content = renderContent
        _parent = State(initialValue: parentId ?? defaultParentId ?? "")
    }

    /// - Parameter content: Renders custom UI in place of the default form, from bindings to the name,
    ///   handle, description and parent, the parents to choose from, the submit action and the submission
    ///   state.
    public init(
        parentId: String? = nil,
        defaultParentId: String? = nil,
        parents: [AdminOption] = [],
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (OrganizationUnitRequest) -> Void,
        @ViewBuilder content: @escaping (OrganizationUnitFormState) -> Content
    ) {
        self.init(
            parentId: parentId,
            defaultParentId: defaultParentId,
            parents: parents,
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
                OrganizationUnitFormState(
                    name: $name,
                    handle: $handle,
                    description: $unitDescription,
                    parentId: parentId == nil ? $parent : .constant(parentId ?? ""),
                    parents: parentId == nil ? parents : [],
                    isParentFixed: parentId != nil,
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
            identifier: "admin-organization-unit-create",
            title: title ?? i18n.resolve("admin.organization_units.create.title"),
            description: description
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let error {
                    AdminErrorBanner(message: error)
                }
                AdminTextField(
                    label: i18n.resolve("admin.organization_units.fields.name"),
                    name: "name",
                    isRequired: true,
                    text: $name
                )
                AdminTextField(
                    label: i18n.resolve("admin.organization_units.fields.handle"),
                    name: "handle",
                    isRequired: true,
                    text: $handle
                )
                AdminTextField(
                    label: i18n.resolve("admin.organization_units.fields.description"),
                    name: "description",
                    text: $unitDescription
                )
                if parentId == nil {
                    AdminPicker(
                        label: i18n.resolve("admin.organization_units.fields.parent"),
                        name: "parent",
                        options: parentOptions,
                        placeholder: i18n.resolve("admin.organization_units.fields.no_parent"),
                        selection: $parent
                    )
                }
                AdminFormActions(
                    i18n: i18n,
                    submitLabel: i18n.resolve("admin.organization_units.create.submit"),
                    isSubmitting: isSubmitting,
                    canSubmit: isValid,
                    onCancel: onCancel,
                    onSubmit: submit
                )
            }
        }
    }

    /// The given parents, plus the chosen one when it is not among them, so the picker can show it.
    private var parentOptions: [AdminOption] {
        guard !parent.isEmpty, !parents.contains(where: { $0.value == parent }) else { return parents }
        return [AdminOption(label: parent, value: parent)] + parents
    }

    private var trimmedHandle: String { handle.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool { AdminHandle.isValid(trimmedHandle) && AdminHandle.optional(name) != nil }

    private func submit() {
        guard isValid, !isSubmitting, let unitName = AdminHandle.optional(name) else { return }
        var fields = OrganizationUnitFields()
        fields.description = AdminHandle.optional(unitDescription)
        onSubmit(
            OrganizationUnitRequest(
                handle: trimmedHandle,
                name: unitName,
                parent: parentId ?? (parent.isEmpty ? nil : parent),
                fields: fields
            )
        )
    }
}

public extension BaseOrganizationUnitCreate where Content == EmptyView {
    init(
        parentId: String? = nil,
        defaultParentId: String? = nil,
        parents: [AdminOption] = [],
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (OrganizationUnitRequest) -> Void
    ) {
        self.init(
            parentId: parentId,
            defaultParentId: defaultParentId,
            parents: parents,
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

/// Creates an organization unit through the management API, beneath `parentId` when it is given.
/// Otherwise the parent is picked from the root units, starting at the current project's root unit when
/// one is selected (see ``ProjectSwitcher``), and may be left empty for a new root.
public struct OrganizationUnitCreate<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let parentId: String?
    let title: String?
    let description: String?
    let onCancel: (() -> Void)?
    let onCreated: ((OrganizationUnit) -> Void)?
    let content: ((OrganizationUnitFormState) -> Content)?

    init(
        parentId: String? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((OrganizationUnit) -> Void)? = nil,
        renderContent: ((OrganizationUnitFormState) -> Content)?
    ) {
        self.parentId = parentId
        self.title = title
        self.description = description
        self.onCancel = onCancel
        self.onCreated = onCreated
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default form. See ``BaseOrganizationUnitCreate``.
    public init(
        parentId: String? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((OrganizationUnit) -> Void)? = nil,
        @ViewBuilder content: @escaping (OrganizationUnitFormState) -> Content
    ) {
        self.init(
            parentId: parentId,
            title: title,
            description: description,
            onCancel: onCancel,
            onCreated: onCreated,
            renderContent: content
        )
    }

    public var body: some View {
        OrganizationUnitCreateHost(state: thunderState, props: self)
    }
}

public extension OrganizationUnitCreate where Content == EmptyView {
    init(
        parentId: String? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((OrganizationUnit) -> Void)? = nil
    ) {
        self.init(
            parentId: parentId,
            title: title,
            description: description,
            onCancel: onCancel,
            onCreated: onCreated,
            renderContent: nil
        )
    }
}

private struct OrganizationUnitCreateHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var mutation: ResourceMutation<OrganizationUnitRequest, OrganizationUnit>
    @StateObject private var roots: ResourceQuery<OrganizationUnitListResponse>
    let props: OrganizationUnitCreate<Content>

    init(state: ThunderIDState, props: OrganizationUnitCreate<Content>) {
        _mutation = StateObject(wrappedValue: state.createOrganizationUnitMutation())
        _roots = StateObject(wrappedValue: state.organizationUnitsQuery(limit: 100))
        self.props = props
    }

    var body: some View {
        BaseOrganizationUnitCreate(
            parentId: props.parentId,
            parents: (roots.data?.organizationUnits ?? []).map { AdminOption(label: $0.name, value: $0.id) },
            error: i18n.managementErrorMessage(
                mutation.error,
                fallbackKey: "admin.organization_units.create.error",
                codeKeys: AdminHierarchyErrors.organizationUnitKeys
            ),
            isSubmitting: mutation.isLoading,
            title: props.title,
            description: props.description,
            onCancel: props.onCancel,
            onSubmit: { request in
                Task {
                    if let unit = await mutation.mutate(request) { props.onCreated?(unit) }
                }
            },
            renderContent: props.content
        )
        .task {
            if props.parentId == nil { await roots.refetch() }
        }
    }
}
