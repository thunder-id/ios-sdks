// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

/// Renders an admin component: the `Base*` view with sample records, or the connected view
/// against the management API.
struct AdminPreview: View {
    @EnvironmentObject private var state: ThunderIDState
    let id: String
    let values: PropValues
    let onEvent: (String) -> Void

    var body: some View {
        if values.isLive && !state.isSignedIn {
            PreviewHint(text: "Sign in to load live data. The management API uses the signed-in user's token.")
        } else if values.isLive, let missing = missingId {
            PreviewHint(text: "Set \(missing), or run the Management checks to find one on the server.")
        } else if id.hasPrefix("user") || id.hasPrefix("agent") {
            IdentityAdminPreview(id: id, values: values, onEvent: onEvent)
        } else {
            AccessAdminPreview(id: id, values: values, onEvent: onEvent)
        }
    }

    private var missingId: String? {
        ["userId", "groupId", "roleId", "agentId"].first { values[$0] != nil && values.text($0).isEmpty }
    }
}

extension PropValues {
    var sampleError: String? { self["state"] == "error" ? text("error") : nil }
    var isSampleLoading: Bool { self["state"] == "loading" }
    var isSampleEmpty: Bool { self["state"] == "empty" }
    var isSubmitting: Bool { self["state"] == "submitting" }
    var limit: Int { Int(text("limit")) ?? 20 }
}

// MARK: - Users and agents

private struct IdentityAdminPreview: View {
    let id: String
    let values: PropValues
    let onEvent: (String) -> Void
    @State private var selected: String?

    var body: some View {
        switch id {
        case "userList": userList
        case "userDetails": userDetails
        case "userCreate": userCreate
        case "agentList": agentList
        case "agentDetails": agentDetails
        default: agentCreate
        }
    }

    @ViewBuilder private var userList: some View {
        if values.isLive {
            UserList(
                limit: values.limit,
                title: values.optional("title"),
                description: values.optional("description"),
                selectedUserId: selected
            ) { select($0.id, $0.resolvedName) }
        } else {
            BaseUserList(
                users: values.isSampleEmpty ? [] : AdminSamples.users,
                isLoading: values.isSampleLoading,
                error: values.sampleError,
                title: values.optional("title"),
                description: values.optional("description"),
                limit: values.limit,
                totalResults: values.isSampleEmpty ? 0 : AdminSamples.users.count,
                selectedUserId: selected,
                onPageChange: { onEvent("onPageChange: \($0)") },
                onSelect: { select($0.id, $0.resolvedName) }
            )
        }
    }

    @ViewBuilder private var userDetails: some View {
        let deletable = values.flag("deletable")
        if values.isLive {
            UserDetails(userId: values.text("userId"), editable: true, deletable: deletable) { onEvent("onDeleted") }
        } else {
            BaseUserDetails(
                user: values.isSampleLoading ? nil : AdminSamples.users.first,
                groups: AdminSamples.userGroups,
                isLoading: values.isSampleLoading,
                error: values.sampleError,
                onDelete: deletable ? { onEvent("onDelete") } : nil
            ) { attributes in
                onEvent("onUpdate: \(attributes.keys.sorted().joined(separator: ", "))")
            }
        }
    }

    @ViewBuilder private var userCreate: some View {
        if values.isLive {
            UserCreate(
                ouId: values.optional("ouId"),
                title: values.optional("title"),
                description: values.optional("description"),
                onCancel: { onEvent("onCancel") },
                onCreated: { user in onEvent("onCreated: \(user.id)") }
            )
        } else {
            BaseUserCreate(
                userTypes: AdminSamples.userTypes,
                error: values.sampleError,
                isSubmitting: values.isSubmitting,
                title: values.optional("title"),
                description: values.optional("description"),
                onCancel: { onEvent("onCancel") },
                onSubmit: { onEvent("onSubmit: \($0.type), \($0.attributes.count) fields") }
            )
        }
    }

    @ViewBuilder private var agentList: some View {
        if values.isLive {
            AgentList(
                limit: values.limit,
                title: values.optional("title"),
                description: values.optional("description"),
                selectedAgentId: selected
            ) { select($0.id, $0.name) }
        } else {
            BaseAgentList(
                agents: values.isSampleEmpty ? [] : AdminSamples.agents,
                isLoading: values.isSampleLoading,
                error: values.sampleError,
                title: values.optional("title"),
                description: values.optional("description"),
                limit: values.limit,
                totalResults: values.isSampleEmpty ? 0 : AdminSamples.agents.count,
                selectedAgentId: selected,
                onPageChange: { onEvent("onPageChange: \($0)") },
                onSelect: { select($0.id, $0.name) }
            )
        }
    }

    @ViewBuilder private var agentDetails: some View {
        let deletable = values.flag("deletable")
        if values.isLive {
            AgentDetails(agentId: values.text("agentId"), deletable: deletable) { onEvent("onDeleted") }
        } else {
            BaseAgentDetails(
                agent: values.isSampleLoading ? nil : AdminSamples.agent,
                groups: AdminSamples.userGroups,
                roles: AdminSamples.agentRoles,
                isLoading: values.isSampleLoading,
                error: values.sampleError,
                onDelete: deletable ? { onEvent("onDelete") } : nil
            )
        }
    }

    @ViewBuilder private var agentCreate: some View {
        if values.isLive {
            AgentCreate(
                ouId: values.optional("ouId"),
                title: values.optional("title"),
                description: values.optional("description"),
                onCancel: { onEvent("onCancel") },
                onCreated: { agent in onEvent("onCreated: \(agent.id)") }
            )
        } else {
            BaseAgentCreate(
                agentTypes: AdminSamples.agentTypes,
                error: values.sampleError,
                isSubmitting: values.isSubmitting,
                title: values.optional("title"),
                description: values.optional("description"),
                onCancel: { onEvent("onCancel") },
                onSubmit: { submission in onEvent("onSubmit: \(submission.name) (\(submission.type))") }
            )
        }
    }

    private func select(_ id: String, _ name: String) {
        selected = id
        onEvent("onSelect: \(name)")
    }
}
