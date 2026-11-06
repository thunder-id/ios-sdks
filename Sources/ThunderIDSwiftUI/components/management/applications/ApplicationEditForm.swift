// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// The general fields and OAuth basics of an application that ``BaseApplicationDetails`` edits.
public struct ApplicationEdit: Equatable {
    public var name: String
    public var description: String?
    public var url: String?
    public var logoUrl: String?
    public var redirectUris: [String]
    public var grantTypes: [String]

    public init(
        name: String,
        description: String? = nil,
        url: String? = nil,
        logoUrl: String? = nil,
        redirectUris: [String] = [],
        grantTypes: [String] = []
    ) {
        self.name = name
        self.description = description
        self.url = url
        self.logoUrl = logoUrl
        self.redirectUris = redirectUris
        self.grantTypes = grantTypes
    }

    /// The editable values of `application`.
    public init(_ application: Application) {
        self.init(
            name: application.name,
            description: application.description,
            url: application.url,
            logoUrl: application.logoUrl,
            redirectUris: application.oauthConfig?.redirectUris ?? [],
            grantTypes: application.oauthConfig?.grantTypes ?? []
        )
    }
}

extension ApplicationRequest {
    /// `self` with `edit` applied: the general fields, and the redirect URIs and grant types of the
    /// OAuth configuration, whose response types follow the grant types. Everything else is kept.
    func applying(_ edit: ApplicationEdit) -> ApplicationRequest {
        var request = self
        request.name = edit.name
        request.description = edit.description
        request.url = edit.url
        request.logoUrl = edit.logoUrl
        request.inboundAuthConfig = request.inboundAuthConfig?.map { entry in
            guard entry.type == "oauth2" else { return entry }
            var updated = entry
            updated.config.redirectUris = edit.redirectUris
            updated.config.grantTypes = edit.grantTypes
            updated.config.responseTypes = edit.grantTypes.contains(ApplicationGrantType.authorizationCode.rawValue)
                ? ["code"]
                : []
            return updated
        }
        return request
    }
}

/// The edit form of ``BaseApplicationDetails``.
struct ApplicationEditForm: View {
    let i18n: ThunderIDI18n
    let hasOAuth: Bool
    let publicClient: Bool
    let isUpdating: Bool
    let onCancel: () -> Void
    let onSave: (ApplicationEdit) -> Void
    /// Grant types the form does not offer, such as token exchange. They are kept as they are.
    let otherGrantTypes: [String]

    @State private var name: String
    @State private var appDescription: String
    @State private var url: String
    @State private var logoUrl: String
    @State private var redirectUris: String
    @State private var grantTypes: Set<String>

    init(
        i18n: ThunderIDI18n,
        edit: ApplicationEdit,
        hasOAuth: Bool,
        publicClient: Bool,
        isUpdating: Bool,
        onCancel: @escaping () -> Void,
        onSave: @escaping (ApplicationEdit) -> Void
    ) {
        self.i18n = i18n
        self.hasOAuth = hasOAuth
        self.publicClient = publicClient
        self.isUpdating = isUpdating
        self.onCancel = onCancel
        self.onSave = onSave
        let offered = Set(ApplicationGrantType.allCases.map(\.rawValue))
        otherGrantTypes = edit.grantTypes.filter { !offered.contains($0) }
        _name = State(initialValue: edit.name)
        _appDescription = State(initialValue: edit.description ?? "")
        _url = State(initialValue: edit.url ?? "")
        _logoUrl = State(initialValue: edit.logoUrl ?? "")
        _redirectUris = State(initialValue: edit.redirectUris.joined(separator: ", "))
        _grantTypes = State(initialValue: Set(edit.grantTypes))
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        guard !trimmedName.isEmpty else { return false }
        return !hasOAuth || applicationOAuthIsValid(
            grantTypes: grantTypes.union(otherGrantTypes),
            redirectUris: applicationURIList(redirectUris),
            publicClient: publicClient
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            if hasOAuth {
                ApplicationGrantTypePicker(i18n: i18n, selection: $grantTypes)
                AdminTextField(
                    label: i18n.resolve("admin.applications.fields.redirect_uris"),
                    name: "redirectUris",
                    text: $redirectUris
                )
                Text(i18n.resolve("admin.applications.fields.redirect_uris_hint"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            AdminFormActions(
                i18n: i18n,
                submitLabel: i18n.resolve("admin.applications.details.edit.save"),
                isSubmitting: isUpdating,
                canSubmit: isValid,
                onCancel: onCancel,
                onSubmit: save
            )
        }
    }

    private func save() {
        guard isValid else { return }
        func optional(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        onSave(
            ApplicationEdit(
                name: trimmedName,
                description: optional(appDescription),
                url: optional(url),
                logoUrl: optional(logoUrl),
                redirectUris: applicationURIList(redirectUris),
                grantTypes: ApplicationGrantType.allCases.map(\.rawValue).filter { grantTypes.contains($0) }
                    + otherGrantTypes
            )
        )
    }
}
