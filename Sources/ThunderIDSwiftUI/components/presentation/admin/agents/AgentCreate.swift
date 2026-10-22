// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// What ``BaseAgentCreate`` submits.
public struct AgentCreateSubmission: Equatable {
    public let name: String
    public let type: String
    /// `nil` when left blank.
    public let description: String?
}

/// A form for registering an agent, rendered from the agent types it is given.
public struct BaseAgentCreate<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let agentTypes: [AdminOption]
    let error: String?
    let isSubmitting: Bool
    let title: String?
    let description: String?
    let onCancel: (() -> Void)?
    let onSubmit: (AgentCreateSubmission) -> Void

    @State private var name = ""
    @State private var chosenType = ""
    @State private var agentDescription = ""

    let content: ((AgentCreateFormState) -> Content)?

    init(
        agentTypes: [AdminOption],
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (AgentCreateSubmission) -> Void,
        renderContent: ((AgentCreateFormState) -> Content)?
    ) {
        self.agentTypes = agentTypes
        self.error = error
        self.isSubmitting = isSubmitting
        self.title = title
        self.description = description
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default form, from the agent types, bindings to the
    ///   name, type and description, the submit action and the submission state.
    public init(
        agentTypes: [AdminOption],
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (AgentCreateSubmission) -> Void,
        @ViewBuilder content: @escaping (AgentCreateFormState) -> Content
    ) {
        self.init(
            agentTypes: agentTypes,
            error: error,
            isSubmitting: isSubmitting,
            title: title,
            description: description,
            onCancel: onCancel,
            onSubmit: onSubmit,
            renderContent: content
        )
    }

    private var type: String { chosenType.isEmpty ? (agentTypes.first?.value ?? "") : chosenType }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var body: some View {
        if let content {
            content(renderState)
        } else {
            defaultBody
        }
    }

    private var renderState: AgentCreateFormState {
        AgentCreateFormState(
            agentTypes: agentTypes,
            name: $name,
            type: Binding(get: { type }, set: { chosenType = $0 }),
            description: $agentDescription,
            isValid: isValid,
            isSubmitting: isSubmitting,
            error: error,
            submit: submit,
            onCancel: onCancel
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        AdminSection(
            identifier: "admin-agent-create",
            title: title ?? i18n.resolve("admin.agents.create.title"),
            description: description
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let error {
                    AdminErrorBanner(message: error)
                }
                AdminTextField(
                    label: i18n.resolve("admin.agents.create.fields.name"),
                    name: "name",
                    isRequired: true,
                    text: $name
                )
                AdminPicker(
                    label: i18n.resolve("admin.agents.create.fields.type"),
                    name: "type",
                    options: agentTypes,
                    selection: Binding(get: { type }, set: { chosenType = $0 })
                )
                AdminTextField(
                    label: i18n.resolve("admin.agents.create.fields.description"),
                    name: "description",
                    text: $agentDescription
                )
                AdminFormActions(
                    i18n: i18n,
                    submitLabel: i18n.resolve("admin.agents.create.submit"),
                    isSubmitting: isSubmitting,
                    canSubmit: isValid,
                    onCancel: onCancel,
                    onSubmit: submit
                )
            }
        }
    }

    private var isValid: Bool { !trimmedName.isEmpty && !type.isEmpty }

    private func submit() {
        guard isValid, !isSubmitting else { return }
        let text = agentDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        onSubmit(AgentCreateSubmission(name: trimmedName, type: type, description: text.isEmpty ? nil : text))
    }
}

public extension BaseAgentCreate where Content == EmptyView {
    init(
        agentTypes: [AdminOption],
        error: String? = nil,
        isSubmitting: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (AgentCreateSubmission) -> Void
    ) {
        self.init(
            agentTypes: agentTypes,
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

/// Registers an agent through the management API, in `ouId` or the signed-in user's own
/// organization unit when it is not given.
public struct AgentCreate<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let ouId: String?
    let owner: String?
    let title: String?
    let description: String?
    let onCancel: (() -> Void)?
    let onCreated: ((Agent) -> Void)?
    let content: ((AgentCreateFormState) -> Content)?

    init(
        ouId: String? = nil,
        owner: String? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((Agent) -> Void)? = nil,
        renderContent: ((AgentCreateFormState) -> Content)?
    ) {
        self.ouId = ouId
        self.owner = owner
        self.title = title
        self.description = description
        self.onCancel = onCancel
        self.onCreated = onCreated
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default form. See ``BaseAgentCreate``.
    public init(
        ouId: String? = nil,
        owner: String? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((Agent) -> Void)? = nil,
        @ViewBuilder content: @escaping (AgentCreateFormState) -> Content
    ) {
        self.init(
            ouId: ouId,
            owner: owner,
            title: title,
            description: description,
            onCancel: onCancel,
            onCreated: onCreated,
            renderContent: content
        )
    }

    public var body: some View {
        let state = thunderState
        AdminQueryReader(state.agentTypesQuery(limit: 100)) { types in
            AdminCreateHost(state: state, ouId: ouId, mutation: state.createAgentMutation()) { host in
                BaseAgentCreate(
                    agentTypes: (types.data?.types ?? []).map { AdminOption(label: $0.displayName, value: $0.handle) },
                    error: host.errorMessage(fallbackKey: "admin.agents.create.error"),
                    isSubmitting: host.isSubmitting,
                    title: title,
                    description: description,
                    onCancel: onCancel,
                    onSubmit: { submission in
                        host.submit { ouId in
                            var request = CreateAgentRequest(ouId: ouId, type: submission.type, name: submission.name)
                            request.description = submission.description
                            request.owner = owner
                            return request
                        } onCreated: { onCreated?($0) }
                    },
                    renderContent: content
                )
            }
        }
    }
}

public extension AgentCreate where Content == EmptyView {
    init(
        ouId: String? = nil,
        owner: String? = nil,
        title: String? = nil,
        description: String? = nil,
        onCancel: (() -> Void)? = nil,
        onCreated: ((Agent) -> Void)? = nil
    ) {
        self.init(
            ouId: ouId,
            owner: owner,
            title: title,
            description: description,
            onCancel: onCancel,
            onCreated: onCreated,
            renderContent: nil
        )
    }
}
