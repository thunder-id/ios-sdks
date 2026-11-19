// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

/// The personal agent stories: the list and the details on sample agents in each state, the connected
/// components on the signed-in user's own agents, and a custom render of each drawn with plain SwiftUI.
extension ExplorerCatalog {
    static let personalAgents: [ComponentSpec] = [
        ComponentSpec(
            id: "personalAgentList",
            name: "PersonalAgentList",
            group: "User",
            defaults: ["source": "sample", "state": "data", "render": "built-in", "suspendable": "true"],
            controls: [
                StoryControl(name: "source", kind: .options(["sample", "live"])),
                StoryControl(name: "state", kind: .options(["data", "loading", "empty", "error"])),
                StoryControl(name: "render", kind: .options(["built-in", "custom"])),
                StoryControl(name: "suspendable", kind: .bool)
            ],
            stories: [
                Story(id: "sample", name: "Sample", preset: ["source": "sample", "state": "data"]),
                Story(id: "empty", name: "Empty", preset: ["source": "sample", "state": "empty"]),
                Story(id: "error", name: "Error", preset: ["source": "sample", "state": "error"]),
                Story(id: "live", name: "Signed-in user", preset: ["source": "live", "render": "built-in"]),
                Story(id: "custom", name: "Custom rendering", preset: ["source": "sample", "render": "custom"])
            ],
            isTall: true
        ) { values in
            let suspendable = values.flag("suspendable") ? ", suspendable: true" : ""
            guard values.text("render") == "custom" else {
                return "PersonalAgentList(onSelect: { agent in agentId = agent.id }\(suspendable))"
            }
            return """
            PersonalAgentList(onSelect: { agent in agentId = agent.id }\(suspendable)) { list in
                ForEach(list.agents, id: \\.id) { agent in
                    Button(agent.resolvedName) { list.onSelect?(agent) }
                }
            }
            """
        },
        ComponentSpec(
            id: "personalAgentDetails",
            name: "PersonalAgentDetails",
            group: "User",
            defaults: [
                "source": "sample",
                "state": "data",
                "suspension": "none",
                "render": "built-in",
                "editable": "true",
                "deletable": "true",
                "suspendable": "true",
                "agentId": ""
            ],
            controls: [
                StoryControl(name: "source", kind: .options(["sample", "live"])),
                StoryControl(name: "state", kind: .options(["data", "loading", "error"])),
                StoryControl(name: "suspension", kind: .options(["none", "owner", "organization", "cascade"])),
                StoryControl(name: "render", kind: .options(["built-in", "custom"])),
                StoryControl(name: "editable", kind: .bool),
                StoryControl(name: "deletable", kind: .bool),
                StoryControl(name: "suspendable", kind: .bool),
                StoryControl(name: "agentId", kind: .text)
            ],
            stories: [
                Story(id: "sample", name: "Sample", preset: ["source": "sample", "suspension": "none"]),
                Story(id: "owner", name: "Suspended by you", preset: ["source": "sample", "suspension": "owner"]),
                Story(
                    id: "organization",
                    name: "Suspended by the organization",
                    preset: ["source": "sample", "suspension": "organization"]
                ),
                Story(id: "live", name: "Signed-in user", preset: ["source": "live", "render": "built-in"]),
                Story(id: "custom", name: "Custom rendering", preset: ["source": "sample", "render": "custom"])
            ],
            isTall: true
        ) { values in
            let flags = ["editable", "deletable", "suspendable"]
                .filter { values.flag($0) }
                .map { "\($0): true" }
            let options = (["agentId: agentId"] + flags).joined(separator: ", ")
            guard values.text("render") == "custom" else { return "PersonalAgentDetails(\(options))" }
            return """
            PersonalAgentDetails(\(options)) { details in
                Text(details.agent?.resolvedName ?? "")
                if let onSuspend = details.onSuspend { Button("Suspend", action: onSuspend) }
                if let onUnsuspend = details.onUnsuspend { Button("Unsuspend", action: onUnsuspend) }
            }
            """
        }
    ]
}

/// Sample personal agents for the sample stories.
enum PersonalAgentSamples {
    static let agents: [BasicAgent] = decode("""
    [
      {"id": "pa-spend", "ouId": "ou-1", "type": "assistant", "kind": "personal-assistant",
       "attributes": {"name": "Spending assistant"}, "clientId": "spend-assistant", "status": {"value": "ACTIVE"}},
      {"id": "pa-mail", "ouId": "ou-1", "type": "assistant", "kind": "personal-assistant",
       "attributes": {"name": "Mail assistant"}, "clientId": "mail-assistant",
       "status": {"value": "SUSPENDED", "details": {"appliedBy": ["owner"]}}}
    ]
    """)

    static func agent(suspendedBy party: String) -> Agent {
        let status = party == "none"
            ? #"{"value": "ACTIVE"}"#
            : #"{"value": "SUSPENDED", "details": {"appliedBy": ["\#(party)"]}}"#
        return decode("""
        {"id": "pa-spend", "ouId": "ou-1", "type": "assistant", "kind": "personal-assistant",
         "description": "Pays recurring bills within a monthly limit", "clientId": "spend-assistant",
         "owner": {"id": "usr-liam"},
         "attributes": {"name": "Spending assistant", "model": "planner-v1"},
         "inboundAuthConfig": [{"type": "oauth2", "config": {
           "grantTypes": ["authorization_code", "refresh_token"],
           "redirectUris": ["https://assistant.example.com/callback"]}}],
         "status": \(status)}
        """)
    }

    private static func decode<Value: Decodable>(_ json: String) -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: Data(json.utf8))
        } catch {
            fatalError("Invalid personal agent sample for \(Value.self): \(error)")
        }
    }
}

struct PersonalAgentPreview: View {
    @EnvironmentObject private var state: ThunderIDState
    let id: String
    let values: PropValues
    let onEvent: (String) -> Void
    @State private var selected: String?

    var body: some View {
        if values.isLive && !state.isSignedIn {
            PreviewHint(text: "Sign in to show the signed-in user's own agents.")
        } else if id == "personalAgentList" {
            list
        } else {
            details
        }
    }

    private var isCustom: Bool { values.text("render") == "custom" }

    @ViewBuilder private var list: some View {
        let suspendAll: (() -> Void)? = values.flag("suspendable") ? { onEvent("onSuspendAll") } : nil
        if values.isLive && isCustom {
            PersonalAgentList(selectedAgentId: selected, onSelect: select, suspendable: values.flag("suspendable")) {
                CustomPersonalAgentList(list: $0)
            }
        } else if values.isLive {
            PersonalAgentList(selectedAgentId: selected, onSelect: select, suspendable: values.flag("suspendable"))
        } else {
            // The sample data and state flags are the same for both renders.
            let agents = values.isSampleEmpty ? [] : PersonalAgentSamples.agents
            let error = values.isSampleEmpty ? nil : values.sampleError.map { _ in "Could not load your agents." }
            if isCustom {
                BasePersonalAgentList(
                    agents: agents,
                    isLoading: values.isSampleLoading,
                    error: error,
                    selectedAgentId: selected,
                    onSelect: select,
                    onSuspendAll: suspendAll
                ) { CustomPersonalAgentList(list: $0) }
            } else {
                BasePersonalAgentList(
                    agents: agents,
                    isLoading: values.isSampleLoading,
                    error: error,
                    selectedAgentId: selected,
                    onPageChange: { onEvent("onPageChange: \($0)") },
                    onSelect: select,
                    onSuspendAll: suspendAll
                )
            }
        }
    }

    @ViewBuilder private var details: some View {
        if values.isLive && isCustom {
            PersonalAgentDetails(
                agentId: values.text("agentId"),
                editable: values.flag("editable"),
                deletable: values.flag("deletable"),
                suspendable: values.flag("suspendable"),
                onDeleted: { onEvent("onDeleted") },
                content: { CustomPersonalAgentDetails(details: $0) }
            )
        } else if values.isLive {
            PersonalAgentDetails(
                agentId: values.text("agentId"),
                editable: values.flag("editable"),
                deletable: values.flag("deletable"),
                suspendable: values.flag("suspendable")
            ) { onEvent("onDeleted") }
        } else {
            // The sample data and state flags are the same for both renders.
            let sample = PersonalAgentSamples.agent(suspendedBy: values.text("suspension"))
            let agent = values.isSampleLoading ? nil : sample
            let error = values["state"] == "error" ? "The action could not be completed. Please try again." : nil
            let onSuspend: (() -> Void)? = values.flag("suspendable") ? { onEvent("onSuspend") } : nil
            let onUnsuspend: (() -> Void)? = values.flag("suspendable") ? { onEvent("onUnsuspend") } : nil
            if isCustom {
                BasePersonalAgentDetails(
                    agent: agent,
                    isLoading: values.isSampleLoading,
                    error: error,
                    onSuspend: onSuspend,
                    onUnsuspend: onUnsuspend
                ) { CustomPersonalAgentDetails(details: $0) }
            } else {
                BasePersonalAgentDetails(
                    agent: agent,
                    isLoading: values.isSampleLoading,
                    error: error,
                    onUpdate: values.flag("editable")
                        ? { onEvent("onUpdate: \($0.grantTypes.count) grant types"); return true }
                        : nil,
                    onDelete: values.flag("deletable") ? { onEvent("onDelete") } : nil,
                    onSuspend: onSuspend,
                    onUnsuspend: onUnsuspend
                )
            }
        }
    }

    private func select(_ agent: BasicAgent) {
        selected = agent.id
        onEvent("onSelect: \(agent.resolvedName)")
    }
}

/// A custom render of the list: each agent as a row with a status dot, and the suspend-all action as a link.
private struct CustomPersonalAgentList: View {
    let list: PersonalAgentListState
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if list.isLoading {
                ProgressView()
            } else if let error = list.error {
                Text(error).foregroundColor(.red)
            } else if list.agents.isEmpty {
                Text("No assistants yet").foregroundColor(.secondary)
            }
            ForEach(list.agents, id: \.id) { agent in
                Button { list.onSelect?(agent) } label: {
                    HStack {
                        Circle()
                            .fill(agent.status?.value == .suspended ? Color.orange : Color.green)
                            .frame(width: 8, height: 8)
                        Text(agent.resolvedName)
                    }
                }
                .buttonStyle(.plain)
            }
            if let onSuspendAll = list.onSuspendAll {
                Button("Pause every assistant") { confirming = true }
                    .confirmationDialog("Pause every assistant?", isPresented: $confirming) {
                        Button("Pause all", role: .destructive, action: onSuspendAll)
                    }
            }
        }
    }
}

/// A custom render of the details: the name, the status, and the one suspension action that applies. A custom
/// render owns the confirmation, so pausing asks first.
private struct CustomPersonalAgentDetails: View {
    let details: PersonalAgentDetailsState
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if details.isLoading {
                ProgressView()
            } else if let error = details.error {
                Text(error).foregroundColor(.red)
            }
            Text(details.agent?.resolvedName ?? "").font(.title3)
            Text(details.agent?.status?.value.rawValue.capitalized ?? "").foregroundColor(.secondary)
            if let onUnsuspend = details.onUnsuspend {
                Button("Resume assistant", action: onUnsuspend)
            }
            if let onSuspend = details.onSuspend {
                Button("Pause assistant", role: .destructive) { confirming = true }
                    .confirmationDialog("Pause this assistant?", isPresented: $confirming) {
                        Button("Pause", role: .destructive, action: onSuspend)
                    }
            }
        }
    }
}

extension CapabilityCatalog {
    /// The signed-in user's own agents.
    static let personalAgentCapability = Capability(
        id: .personalAgents,
        name: "Personal agents",
        api: "getMeAgents(kind:limit:offset:) · getMeAgent(id:)",
        mode: .automatic
    )
}

extension CheckContext {
    static let personalAgentRunners: [CapabilityID: Runner] = [
        .personalAgents: { try await $0.personalAgents() }
    ]

    /// Lists the signed-in user's personal agents and reads the first, without changing anything.
    func personalAgents() async throws -> String {
        try await requireSignedIn()
        let page = try await client.getMeAgents(kind: .personal, limit: 20)
        log.record("me-agents:loaded", "count=\(page.totalResults)", kind: .success)
        guard let first = page.agents.first else { return "The user owns no personal agents" }
        let agent = try await client.getMeAgent(id: first.id)
        let suspension = MeAgentSuspensionAction.available(for: agent.status) == .unsuspend
            ? "suspended by the user"
            : agent.status?.value.rawValue.lowercased() ?? "no status"
        return "\(page.totalResults) personal agents; \(agent.resolvedName) is \(suspension)"
    }
}
