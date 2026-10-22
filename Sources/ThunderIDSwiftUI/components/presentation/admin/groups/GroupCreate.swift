// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// What ``BaseGroupCreate`` and ``BaseRoleCreate`` submit.
public struct NamedResourceSubmission: Equatable {
    public let name: String
    /// `nil` when left blank.
    public let description: String?
}

/// A name and description form, shared by the group and role create components.
struct NamedResourceForm<Content: View>: View {
    let i18n: ThunderIDI18n
    let identifier: String
    let keyPrefix: String
    let error: String?
    let isSubmitting: Bool
    let title: String?
    let description: String?
    let onCancel: (() -> Void)?
    let onSubmit: (NamedResourceSubmission) -> Void
    let renderContent: ((NamedResourceFormState) -> Content)?

    @State private var name = ""
    @State private var resourceDescription = ""

    var body: some View {
        if let renderContent {
            renderContent(
                NamedResourceFormState(
                    name: $name,
                    description: $resourceDescription,
                    isValid: !trimmedName.isEmpty,
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
            identifier: identifier,
            title: title ?? i18n.resolve("\(keyPrefix).title"),
            description: description
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let error {
                    AdminErrorBanner(message: error)
                }
                AdminTextField(
                    label: i18n.resolve("\(keyPrefix).fields.name"),
                    name: "name",
                    isRequired: true,
                    text: $name
                )
                AdminTextField(
                    label: i18n.resolve("\(keyPrefix).fields.description"),
                    name: "description",
                    text: $resourceDescription
                )
                AdminFormActions(
                    i18n: i18n,
                    submitLabel: i18n.resolve("\(keyPrefix).submit"),
                    isSubmitting: isSubmitting,
                    canSubmit: !trimmedName.isEmpty,
                    onCancel: onCancel,
                    onSubmit: submit
                )
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func submit() {
        guard !trimmedName.isEmpty, !isSubmitting else { return }
        let text = resourceDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        onSubmit(NamedResourceSubmission(name: trimmedName, description: text.isEmpty ? nil : text))
    }
}

/// A form for creating a group.
public struct BaseGroupCreate<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let error: String?
    let isSubmitting: Bool
    let title: String?
    let description: String?
    let onCancel: (() -> Void)?
    let onSubmit: (NamedResourceSubmission) -> Void
    let content: ((NamedResourceFormState) -> Content)?

    init(
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (NamedResourceSubmission) -> Void,
        renderContent: ((NamedResourceFormState) -> Content)?
    ) {
        self.error = error
        self.isSubmitting = isSubmitting
        self.title = title
        self.description = description
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default form, from bindings to the name and
    ///   description, the submit action and the submission state.
    public init(
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (NamedResourceSubmission) -> Void,
        @ViewBuilder content: @escaping (NamedResourceFormState) -> Content
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
        NamedResourceForm(
            i18n: i18n,
            identifier: "admin-group-create",
            keyPrefix: "admin.groups.create",
            error: error,
            isSubmitting: isSubmitting,
            title: title,
            description: description,
            onCancel: onCancel,
            onSubmit: onSubmit,
            renderContent: content
        )
    }
}

public extension BaseGroupCreate where Content == EmptyView {
    init(
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (NamedResourceSubmission) -> Void
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

/// Creates a group through the management API, in `ouId` or the signed-in user's own
/// organization unit when it is not given.
public struct GroupCreate<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let ouId: String?
    let title: String?
    let description: String?
    let onCancel: (() -> Void)?
    let onCreated: ((ManagedGroup) -> Void)?
    let content: ((NamedResourceFormState) -> Content)?

    init(
        ouId: String? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((ManagedGroup) -> Void)? = nil,
        renderContent: ((NamedResourceFormState) -> Content)?
    ) {
        self.ouId = ouId
        self.title = title
        self.description = description
        self.onCancel = onCancel
        self.onCreated = onCreated
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default form. See ``BaseGroupCreate``.
    public init(
        ouId: String? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((ManagedGroup) -> Void)? = nil,
        @ViewBuilder content: @escaping (NamedResourceFormState) -> Content
    ) {
        self.init(
            ouId: ouId,
            title: title,
            description: description,
            onCancel: onCancel,
            onCreated: onCreated,
            renderContent: content
        )
    }

    public var body: some View {
        let state = thunderState
        AdminCreateHost(state: state, ouId: ouId, mutation: state.createGroupMutation()) { host in
            BaseGroupCreate(
                error: host.errorMessage(fallbackKey: "admin.groups.create.error"),
                isSubmitting: host.isSubmitting,
                title: title,
                description: description,
                onCancel: onCancel,
                onSubmit: { submission in
                    host.submit { ouId in
                        CreateGroupRequest(name: submission.name, ouId: ouId, description: submission.description)
                    } onCreated: { onCreated?($0) }
                },
                renderContent: content
            )
        }
    }
}

public extension GroupCreate where Content == EmptyView {
    init(
        ouId: String? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((ManagedGroup) -> Void)? = nil
    ) {
        self.init(
            ouId: ouId,
            title: title,
            description: description,
            onCancel: onCancel,
            onCreated: onCreated,
            renderContent: nil
        )
    }
}
