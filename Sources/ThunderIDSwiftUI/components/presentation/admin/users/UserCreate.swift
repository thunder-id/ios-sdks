// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A user attribute collected by ``BaseUserCreate``.
public struct UserCreateField: Hashable {
    public enum Kind: String {
        case text, email, password, phone
    }

    /// The attribute name the value is stored under.
    public let name: String
    /// Defaults to the `admin.users.create.fields.<name>` translation.
    public let label: String?
    public let isRequired: Bool
    public let kind: Kind

    public init(name: String, label: String? = nil, isRequired: Bool = false, kind: Kind = .text) {
        self.name = name
        self.label = label
        self.isRequired = isRequired
        self.kind = kind
    }

    /// Username, email, first name, last name and password.
    public static let defaults: [UserCreateField] = [
        UserCreateField(name: "username", isRequired: true),
        UserCreateField(name: "email", isRequired: true, kind: .email),
        UserCreateField(name: "given_name"),
        UserCreateField(name: "family_name"),
        UserCreateField(name: "password", kind: .password)
    ]
}

/// What ``BaseUserCreate`` submits: the chosen user type and the non-empty attribute values.
public struct UserCreateSubmission: Equatable {
    public let type: String
    public let attributes: [String: String]
}

/// A form for creating a user, rendered from the user types it is given.
public struct BaseUserCreate<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let userTypes: [AdminOption]
    let fields: [UserCreateField]
    let error: String?
    let isSubmitting: Bool
    let title: String?
    let description: String?
    let onCancel: (() -> Void)?
    let onSubmit: (UserCreateSubmission) -> Void

    @State private var chosenType = ""
    @State private var values: [String: String] = [:]

    let content: ((UserCreateFormState) -> Content)?

    init(
        userTypes: [AdminOption],
        fields: [UserCreateField] = UserCreateField.defaults,
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (UserCreateSubmission) -> Void,
        renderContent: ((UserCreateFormState) -> Content)?
    ) {
        self.userTypes = userTypes
        self.fields = fields
        self.error = error
        self.isSubmitting = isSubmitting
        self.title = title
        self.description = description
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default form, from the user types, the fields,
    ///   bindings to the type and each attribute, the submit action and the submission state.
    public init(
        userTypes: [AdminOption],
        fields: [UserCreateField] = UserCreateField.defaults,
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (UserCreateSubmission) -> Void,
        @ViewBuilder content: @escaping (UserCreateFormState) -> Content
    ) {
        self.init(
            userTypes: userTypes,
            fields: fields,
            error: error,
            isSubmitting: isSubmitting,
            title: title,
            description: description,
            onCancel: onCancel,
            onSubmit: onSubmit,
            renderContent: content
        )
    }

    private var type: String { chosenType.isEmpty ? (userTypes.first?.value ?? "") : chosenType }

    private var isComplete: Bool {
        !type.isEmpty && fields.allSatisfy { !$0.isRequired || !trimmed($0.name).isEmpty }
    }

    public var body: some View {
        if let content {
            content(renderState)
        } else {
            defaultBody
        }
    }

    private var renderState: UserCreateFormState {
        UserCreateFormState(
            userTypes: userTypes,
            fields: fields,
            type: Binding(get: { type }, set: { chosenType = $0 }),
            values: values,
            isValid: isComplete,
            isSubmitting: isSubmitting,
            error: error,
            bindingFor: { name in Binding(get: { values[name] ?? "" }, set: { values[name] = $0 }) },
            submit: submit,
            onCancel: onCancel
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        AdminSection(
            identifier: "admin-user-create",
            title: title ?? i18n.resolve("admin.users.create.title"),
            description: description
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let error {
                    AdminErrorBanner(message: error)
                }
                AdminPicker(
                    label: i18n.resolve("admin.users.create.fields.type"),
                    name: "type",
                    options: userTypes,
                    selection: Binding(get: { type }, set: { chosenType = $0 })
                )
                ForEach(fields, id: \.name) { field in
                    AdminTextField(
                        label: field.label ?? i18n.resolve("admin.users.create.fields.\(field.name)"),
                        name: field.name,
                        isSecure: field.kind == .password,
                        isRequired: field.isRequired,
                        text: Binding(get: { values[field.name] ?? "" }, set: { values[field.name] = $0 })
                    )
                }
                AdminFormActions(
                    i18n: i18n,
                    submitLabel: i18n.resolve("admin.users.create.submit"),
                    isSubmitting: isSubmitting,
                    canSubmit: isComplete,
                    onCancel: onCancel,
                    onSubmit: submit
                )
            }
        }
    }

    private func trimmed(_ name: String) -> String {
        (values[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard isComplete, !isSubmitting else { return }
        let attributes = values.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        onSubmit(UserCreateSubmission(type: type, attributes: attributes))
    }
}

public extension BaseUserCreate where Content == EmptyView {
    init(
        userTypes: [AdminOption],
        fields: [UserCreateField] = UserCreateField.defaults,
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (UserCreateSubmission) -> Void
    ) {
        self.init(
            userTypes: userTypes,
            fields: fields,
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

/// Creates a user through the management API. New users go into `ouId`, or the signed-in user's
/// own organization unit when it is not given.
public struct UserCreate<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let ouId: String?
    let fields: [UserCreateField]
    let title: String?
    let description: String?
    let onCancel: (() -> Void)?
    let onCreated: ((ManagedUser) -> Void)?
    let content: ((UserCreateFormState) -> Content)?

    init(
        ouId: String? = nil,
        fields: [UserCreateField] = UserCreateField.defaults,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((ManagedUser) -> Void)? = nil,
        renderContent: ((UserCreateFormState) -> Content)?
    ) {
        self.ouId = ouId
        self.fields = fields
        self.title = title
        self.description = description
        self.onCancel = onCancel
        self.onCreated = onCreated
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default form. See ``BaseUserCreate``.
    public init(
        ouId: String? = nil,
        fields: [UserCreateField] = UserCreateField.defaults,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((ManagedUser) -> Void)? = nil,
        @ViewBuilder content: @escaping (UserCreateFormState) -> Content
    ) {
        self.init(
            ouId: ouId,
            fields: fields,
            title: title,
            description: description,
            onCancel: onCancel,
            onCreated: onCreated,
            renderContent: content
        )
    }

    public var body: some View {
        let state = thunderState
        AdminQueryReader(state.userTypesQuery(limit: 100)) { types in
            AdminCreateHost(state: state, ouId: ouId, mutation: state.createUserMutation()) { host in
                BaseUserCreate(
                    userTypes: (types.data?.types ?? []).map {
                        AdminOption(label: $0.displayName ?? $0.handle, value: $0.handle)
                    },
                    fields: fields,
                    error: host.errorMessage(fallbackKey: "admin.users.create.error"),
                    isSubmitting: host.isSubmitting,
                    title: title,
                    description: description,
                    onCancel: onCancel,
                    onSubmit: { submission in
                        host.submit { ouId in
                            CreateManagedUserRequest(
                                ouId: ouId,
                                type: submission.type,
                                attributes: submission.attributes.mapValues { AnyCodable($0) }
                            )
                        } onCreated: { onCreated?($0) }
                    },
                    renderContent: content
                )
            }
        }
    }
}

public extension UserCreate where Content == EmptyView {
    init(
        ouId: String? = nil,
        fields: [UserCreateField] = UserCreateField.defaults,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((ManagedUser) -> Void)? = nil
    ) {
        self.init(
            ouId: ouId,
            fields: fields,
            title: title,
            description: description,
            onCancel: onCancel,
            onCreated: onCreated,
            renderContent: nil
        )
    }
}
