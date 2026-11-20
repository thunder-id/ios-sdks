// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// English default strings for the personal agent components (`user.agents.*`) and the personal agent
/// additions to the admin agent components. The keys and text match the JavaScript SDK's translations.
enum PersonalAgentDefaultStrings {
    static let all: [String: String] = [
        "user.agents.title": "Personal agents",
        "user.agents.description": "Agents that act only on your behalf.",
        "user.agents.list.columns.name": "Name",
        "user.agents.list.columns.status": "Status",
        "user.agents.list.empty": "You don't have any personal agents.",
        "user.agents.list.error": "Could not load your agents. Please try again.",
        "user.agents.suspend_all.action": "Suspend all",
        "user.agents.suspend_all.confirm":
            "Suspend all your personal agents? They lose access until you unsuspend them.",
        "user.agents.suspend_all.done": "Agents suspended: {count}",
        "user.agents.details.overview": "Overview",
        "user.agents.details.attributes": "Attributes",
        "user.agents.details.client_id": "Client ID",
        "user.agents.details.grant_types": "Grant types",
        "user.agents.details.redirect_uris": "Redirect URIs",
        "user.agents.details.none": "None",
        "user.agents.details.error": "Could not load this agent. Please try again.",
        "user.agents.suspension.owner": "You suspended this agent.",
        "user.agents.suspension.organization":
            "Your organization suspended this agent. Only an administrator can lift that suspension.",
        "user.agents.suspension.cascade": "This agent stays suspended while your account is suspended.",
        "user.agents.suspend.action": "Suspend",
        "user.agents.suspend.confirm": "Suspend {name}? It loses access until you unsuspend it.",
        "user.agents.unsuspend.action": "Unsuspend",
        "user.agents.action.error": "The action could not be completed. Please try again.",
        "user.agents.edit.action": "Edit",
        "user.agents.actions.menu": "Agent actions",
        "user.agents.edit.title": "Edit agent",
        "user.agents.edit.save": "Save changes",
        "user.agents.fields.name": "Name",
        "user.agents.fields.description": "Description",
        "user.agents.fields.redirect_uris_hint": "Needed for the authorization code grant. Enter one URI per line.",
        "user.agents.grant_types.authorization_code": "Authorization code",
        "user.agents.grant_types.ciba": "Backchannel authentication (CIBA)",
        "user.agents.grant_types.refresh_token": "Refresh token",
        "user.agents.delete.action": "Delete agent",
        "user.agents.delete.confirm": "Delete {name}? This cannot be undone.",
        "admin.agents.kind.personal": "Personal",
        "admin.agents.details.kind": "Kind",
        "admin.agents.details.suspension.title": "Suspended by",
        "admin.agents.details.suspension.organization": "Organization",
        "admin.agents.details.suspension.owner": "Owner",
        "admin.agents.details.suspension.cascade": "Owner's account suspension"
    ]
}
