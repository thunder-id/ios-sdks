// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// An open edit form, and the agent it was opened for.
struct PersonalAgentDraft {
    let agentId: String
    var values: PersonalAgentFormValues
}

/// The pieces of ``BasePersonalAgentDetails`` that read the agent.
enum PersonalAgentParts {
    /// The parties whose suspension the details explain, in the order they are shown.
    private static let explainedParties: [SuspensionAppliedBy] = [.owner, .organization, .cascade]

    /// One translated notice per suspension in force, saying who placed it.
    static func suspensionNotices(_ agent: Agent, i18n: ThunderIDI18n) -> [String] {
        let parties = agent.status?.suspendedBy ?? []
        return explainedParties
            .filter(parties.contains)
            .map { i18n.resolve("user.agents.suspension.\($0.rawValue)") }
    }

    /// The translated label of a grant type, or the grant type itself when it has none.
    static func grantTypeLabel(_ grantType: String, i18n: ThunderIDI18n) -> String {
        PersonalAgentGrantTypes.labelKeys[grantType].map(i18n.resolve) ?? grantType
    }

    static func overview(_ agent: Agent, i18n: ThunderIDI18n) -> [(label: String, value: String)] {
        let none = i18n.resolve("user.agents.details.none")
        let oauth = agent.oauthConfig
        let grantTypes = (oauth?.grantTypes ?? []).map { grantTypeLabel($0, i18n: i18n) }
        let redirectUris = oauth?.redirectUris ?? []
        return [
            (
                i18n.resolve("user.agents.list.columns.status"),
                agent.status.map { i18n.accessStatusLabel($0.value) } ?? none
            ),
            (i18n.resolve("user.agents.details.client_id"), agent.clientId ?? none),
            (
                i18n.resolve("user.agents.details.grant_types"),
                grantTypes.isEmpty ? none : grantTypes.joined(separator: ", ")
            ),
            (
                i18n.resolve("user.agents.details.redirect_uris"),
                redirectUris.isEmpty ? none : redirectUris.joined(separator: "\n")
            )
        ]
    }

    @ViewBuilder
    static func attributes(_ agent: Agent, i18n: ThunderIDI18n) -> some View {
        let items = (agent.attributes ?? [:])
            .sorted { $0.key < $1.key }
            .map { (label: $0.key, value: text($0.value.value)) }
        if items.isEmpty {
            Text(i18n.resolve("user.agents.details.none"))
                .font(.subheadline)
                .foregroundColor(.secondary)
        } else {
            AdminDetailList(items: items)
        }
    }

    /// An attribute value as text: a string as it is, and any other value as JSON.
    static func text(_ value: Any) -> String {
        switch value {
        case let text as String: return text
        case let flag as Bool: return flag ? "true" : "false"
        case is NSNull: return ""
        default:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(AnyCodable(value)) else { return String(describing: value) }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }
}

/// The edit form of ``BasePersonalAgentDetails``: the name, the agent's other text attributes, the
/// description, the redirect URIs and the grant types.
struct PersonalAgentEditForm: View {
    let i18n: ThunderIDI18n
    @Binding var values: PersonalAgentFormValues
    let isUpdating: Bool
    let onCancel: () -> Void
    let onSave: (PersonalAgentFormValues) -> Void

    var body: some View {
        AdminPanel(title: i18n.resolve("user.agents.edit.title")) {
            VStack(alignment: .leading, spacing: 12) {
                AdminTextField(
                    label: i18n.resolve("user.agents.fields.name"),
                    name: "name",
                    isRequired: true,
                    text: $values.name
                )
                ForEach(values.attributes.keys.sorted(), id: \.self) { attribute in
                    AdminTextField(label: attribute, name: "attribute-\(attribute)", text: attributeBinding(attribute))
                }
                AdminTextField(
                    label: i18n.resolve("user.agents.fields.description"),
                    name: "description",
                    text: $values.description
                )
                VStack(alignment: .leading, spacing: 4) {
                    AdminTextField(
                        label: i18n.resolve("user.agents.details.redirect_uris"),
                        name: "redirectUris",
                        isMultiline: true,
                        text: $values.redirectUris
                    )
                    Text(i18n.resolve("user.agents.fields.redirect_uris_hint"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                grantTypes
                AdminFormActions(
                    i18n: i18n,
                    submitLabel: i18n.resolve("user.agents.edit.save"),
                    isSubmitting: isUpdating,
                    canSubmit: values.isValid,
                    onCancel: onCancel
                ) {
                    guard values.isValid else { return }
                    onSave(values)
                }
            }
        }
        .accessibilityIdentifier("personal-agent-details-edit-form")
    }

    private var grantTypes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(i18n.resolve("user.agents.details.grant_types"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(PersonalAgentGrantTypes.all, id: \.self) { grantType in
                Toggle(PersonalAgentParts.grantTypeLabel(grantType, i18n: i18n), isOn: grantTypeBinding(grantType))
                    .accessibilityIdentifier("admin-field-grantType-\(grantType)")
            }
        }
    }

    private func attributeBinding(_ attribute: String) -> Binding<String> {
        Binding(get: { values.attributes[attribute] ?? "" }, set: { values.attributes[attribute] = $0 })
    }

    private func grantTypeBinding(_ grantType: String) -> Binding<Bool> {
        Binding(
            get: { values.grantTypes.contains(grantType) },
            set: { isOn in
                values.grantTypes.removeAll { $0 == grantType }
                if isOn { values.grantTypes.append(grantType) }
            }
        )
    }
}
