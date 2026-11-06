// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A form for creating a role.
public struct BaseRoleCreate<Content: View>: View {
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
            identifier: "admin-role-create",
            keyPrefix: "admin.roles.create",
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

public extension BaseRoleCreate where Content == EmptyView {
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

/// Creates a role through the management API, in `ouId` or the signed-in user's own
/// organization unit when it is not given.
public struct RoleCreate<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let ouId: String?
    let title: String?
    let description: String?
    let onCancel: (() -> Void)?
    let onCreated: ((Role) -> Void)?
    let content: ((NamedResourceFormState) -> Content)?

    init(
        ouId: String? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((Role) -> Void)? = nil,
        renderContent: ((NamedResourceFormState) -> Content)?
    ) {
        self.ouId = ouId
        self.title = title
        self.description = description
        self.onCancel = onCancel
        self.onCreated = onCreated
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default form. See ``BaseRoleCreate``.
    public init(
        ouId: String? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((Role) -> Void)? = nil,
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
        AdminCreateHost(state: state, ouId: ouId, mutation: state.createRoleMutation()) { host in
            BaseRoleCreate(
                error: host.errorMessage(fallbackKey: "admin.roles.create.error"),
                isSubmitting: host.isSubmitting,
                title: title,
                description: description,
                onCancel: onCancel,
                onSubmit: { submission in
                    host.submit { ouId in
                        CreateRoleRequest(name: submission.name, ouId: ouId, description: submission.description)
                    } onCreated: { onCreated?($0) }
                },
                renderContent: content
            )
        }
    }
}

public extension RoleCreate where Content == EmptyView {
    init(
        ouId: String? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((Role) -> Void)? = nil
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
