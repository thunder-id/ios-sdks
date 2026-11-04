// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// What ``BaseApplicationCreate`` submits.
public struct ApplicationCreateSubmission: Equatable {
    public let name: String
    /// `nil` when left blank, as are `url` and `logoUrl`.
    public let description: String?
    public let url: String?
    public let logoUrl: String?
    public let redirectUris: [String]
    /// In the order of ``ApplicationGrantType``.
    public let grantTypes: [String]
    public let publicClient: Bool
}

/// What ``BaseApplicationCreate`` hands its `content` closure.
public struct ApplicationCreateFormState {
    public let name: Binding<String>
    public let description: Binding<String>
    public let url: Binding<String>
    public let logoUrl: Binding<String>
    /// The redirect URIs as typed, separated by commas.
    public let redirectUris: Binding<String>
    /// The chosen grant type values, such as `authorization_code`.
    public let grantTypes: Binding<Set<String>>
    public let publicClient: Binding<Bool>
    /// Whether the values can be submitted: a name, at least one grant type, redirect URIs for the
    /// authorization code grant, and no client credentials grant on a public client.
    public let isValid: Bool
    public let isSubmitting: Bool
    public let error: String?
    /// The client secret of the application just created. Show it once, then call `onSecretDone`.
    public let clientSecret: String?
    public let onSecretDone: (() -> Void)?
    /// Submits the current values. Does nothing while they are not valid or a submission is in flight.
    public let submit: () -> Void
    public let onCancel: (() -> Void)?
}

/// A form for creating an application: its name, description and links, and the OAuth basics with
/// sensible defaults (authorization code and refresh token, a confidential client). When
/// `clientSecret` is set, the secret is shown once in place of the form.
public struct BaseApplicationCreate<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let error: String?
    let isSubmitting: Bool
    let clientSecret: String?
    let onSecretDone: (() -> Void)?
    let title: String?
    let description: String?
    let onCancel: (() -> Void)?
    let onSubmit: (ApplicationCreateSubmission) -> Void
    let content: ((ApplicationCreateFormState) -> Content)?

    @State private var name = ""
    @State private var appDescription = ""
    @State private var url = ""
    @State private var logoUrl = ""
    @State private var redirectUris = ""
    @State private var grantTypes: Set<String> = [
        ApplicationGrantType.authorizationCode.rawValue,
        ApplicationGrantType.refreshToken.rawValue
    ]
    @State private var publicClient = false

    init(
        error: String? = nil,
        isSubmitting: Bool = false,
        clientSecret: String? = nil,
        onSecretDone: (() -> Void)? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (ApplicationCreateSubmission) -> Void,
        renderContent: ((ApplicationCreateFormState) -> Content)?
    ) {
        self.error = error
        self.isSubmitting = isSubmitting
        self.clientSecret = clientSecret
        self.onSecretDone = onSecretDone
        self.title = title
        self.description = description
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default form, from bindings to every field,
    ///   the submit action, the submission state and the created client secret.
    public init(
        error: String? = nil,
        isSubmitting: Bool = false,
        clientSecret: String? = nil,
        onSecretDone: (() -> Void)? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (ApplicationCreateSubmission) -> Void,
        @ViewBuilder content: @escaping (ApplicationCreateFormState) -> Content
    ) {
        self.init(
            error: error,
            isSubmitting: isSubmitting,
            clientSecret: clientSecret,
            onSecretDone: onSecretDone,
            title: title,
            description: description,
            onCancel: onCancel,
            onSubmit: onSubmit,
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

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        !trimmedName.isEmpty && applicationOAuthIsValid(
            grantTypes: grantTypes,
            redirectUris: applicationURIList(redirectUris),
            publicClient: publicClient
        )
    }

    private var renderState: ApplicationCreateFormState {
        ApplicationCreateFormState(
            name: $name,
            description: $appDescription,
            url: $url,
            logoUrl: $logoUrl,
            redirectUris: $redirectUris,
            grantTypes: $grantTypes,
            publicClient: $publicClient,
            isValid: isValid,
            isSubmitting: isSubmitting,
            error: error,
            clientSecret: clientSecret,
            onSecretDone: onSecretDone,
            submit: submit,
            onCancel: onCancel
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        AdminSection(
            identifier: "admin-application-create",
            title: title ?? i18n.resolve("admin.applications.create.title"),
            description: description
        ) {
            if let clientSecret {
                ApplicationSecretNotice(i18n: i18n, secret: clientSecret) { onSecretDone?() }
            } else {
                form
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error {
                AdminErrorBanner(message: error)
            }
            AdminTextField(
                label: i18n.resolve("admin.applications.fields.name"),
                name: "name",
                isRequired: true,
                text: $name
            )
            AdminTextField(
                label: i18n.resolve("admin.applications.fields.description"),
                name: "description",
                text: $appDescription
            )
            AdminTextField(label: i18n.resolve("admin.applications.fields.url"), name: "url", text: $url)
            AdminTextField(label: i18n.resolve("admin.applications.fields.logo_url"), name: "logoUrl", text: $logoUrl)
            ApplicationGrantTypePicker(i18n: i18n, selection: $grantTypes)
            AdminTextField(
                label: i18n.resolve("admin.applications.fields.redirect_uris"),
                name: "redirectUris",
                text: $redirectUris
            )
            Text(i18n.resolve("admin.applications.fields.redirect_uris_hint"))
                .font(.footnote)
                .foregroundColor(.secondary)
            Toggle(i18n.resolve("admin.applications.fields.public_client"), isOn: $publicClient)
                .accessibilityIdentifier("admin-field-publicClient")
            AdminFormActions(
                i18n: i18n,
                submitLabel: i18n.resolve("admin.applications.create.submit"),
                isSubmitting: isSubmitting,
                canSubmit: isValid,
                onCancel: onCancel,
                onSubmit: submit
            )
        }
    }

    private func submit() {
        guard isValid, !isSubmitting else { return }
        func optional(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        onSubmit(
            ApplicationCreateSubmission(
                name: trimmedName,
                description: optional(appDescription),
                url: optional(url),
                logoUrl: optional(logoUrl),
                redirectUris: applicationURIList(redirectUris),
                grantTypes: ApplicationGrantType.allCases.map(\.rawValue).filter { grantTypes.contains($0) },
                publicClient: publicClient
            )
        )
    }
}

public extension BaseApplicationCreate where Content == EmptyView {
    init(
        error: String? = nil,
        isSubmitting: Bool = false,
        clientSecret: String? = nil,
        onSecretDone: (() -> Void)? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (ApplicationCreateSubmission) -> Void
    ) {
        self.init(
            error: error,
            isSubmitting: isSubmitting,
            clientSecret: clientSecret,
            onSecretDone: onSecretDone,
            title: title,
            description: description,
            onCancel: onCancel,
            onSubmit: onSubmit,
            renderContent: nil
        )
    }
}

extension ApplicationRequest {
    /// The request for a new application from what ``BaseApplicationCreate`` submitted.
    init(submission: ApplicationCreateSubmission, ouId: String?, projectId: String? = nil, type: String) {
        self.init(name: submission.name)
        description = submission.description
        url = submission.url
        logoUrl = submission.logoUrl
        self.ouId = ouId
        self.projectId = projectId
        self.type = type
        inboundAuthConfig = [
            InboundAuthConfig(
                config: .basics(
                    grantTypes: submission.grantTypes,
                    redirectUris: submission.redirectUris,
                    publicClient: submission.publicClient
                )
            )
        ]
    }
}

/// Creates an application through the management API, in `ouId`. Without `ouId`, it goes in the current
/// project (``ThunderIDState/currentProject``), which the server resolves to the project's root
/// organization unit, or, when no project is current, in the signed-in user's own organization unit.
/// When the server issues a client secret, it is shown once before `onCreated` runs. Applications are
/// guarded by the root `system` permission; the server defines no application-specific one.
public struct ApplicationCreate<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let ouId: String?
    let type: String
    let title: String?
    let description: String?
    let onCancel: (() -> Void)?
    let onCreated: ((Application) -> Void)?
    let content: ((ApplicationCreateFormState) -> Content)?
    @State private var pending: Application?

    init(
        ouId: String? = nil,
        type: String = "custom",
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((Application) -> Void)? = nil,
        renderContent: ((ApplicationCreateFormState) -> Content)?
    ) {
        self.ouId = ouId
        self.type = type
        self.title = title
        self.description = description
        self.onCancel = onCancel
        self.onCreated = onCreated
        self.content = renderContent
    }

    /// - Parameters:
    ///   - type: The application type: `browser`, `fullstack`, `mobile`, `m2m`, `mcp` or `custom`.
    ///   - content: Renders custom UI in place of the default form. See ``BaseApplicationCreate``.
    public init(
        ouId: String? = nil,
        type: String = "custom",
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((Application) -> Void)? = nil,
        @ViewBuilder content: @escaping (ApplicationCreateFormState) -> Content
    ) {
        self.init(
            ouId: ouId,
            type: type,
            title: title,
            description: description,
            onCancel: onCancel,
            onCreated: onCreated,
            renderContent: content
        )
    }

    public var body: some View {
        let state = thunderState
        AdminCreateHost(
            state: state,
            ouId: ouId,
            projectScoped: true,
            mutation: state.createApplicationMutation()
        ) { host in
            let error = host.errorMessage(fallbackKey: "admin.applications.create.error")
            form(error: error, host.isSubmitting) { submission in
                host.submit(
                    placement: { placement in
                        ApplicationRequest(
                            submission: submission,
                            ouId: placement.ouId,
                            projectId: placement.projectId,
                            type: type
                        )
                    },
                    onCreated: { created in
                        if created.oauthConfig?.clientSecret?.isEmpty == false {
                            pending = created
                        } else {
                            onCreated?(created)
                        }
                    }
                )
            }
        }
    }

    private func form(
        error: String?,
        _ isSubmitting: Bool,
        onSubmit: @escaping (ApplicationCreateSubmission) -> Void
    ) -> BaseApplicationCreate<Content> {
        BaseApplicationCreate(
            error: error,
            isSubmitting: isSubmitting,
            clientSecret: pending?.oauthConfig?.clientSecret,
            onSecretDone: {
                if let created = pending {
                    pending = nil
                    onCreated?(created)
                }
            },
            title: title,
            description: description,
            onCancel: onCancel,
            onSubmit: onSubmit,
            renderContent: content
        )
    }
}

public extension ApplicationCreate where Content == EmptyView {
    init(
        ouId: String? = nil,
        type: String = "custom",
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((Application) -> Void)? = nil
    ) {
        self.init(
            ouId: ouId,
            type: type,
            title: title,
            description: description,
            onCancel: onCancel,
            onCreated: onCreated,
            renderContent: nil
        )
    }
}
