// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderIDSwiftUI

/// Sample management records for the admin components' Base stories. The server models have no
/// public memberwise initializers, so the samples are decoded from JSON shaped like the API's.
enum AdminSamples {
    static let groups: [ManagedGroup] = decode("""
    [
      {"id": "grp-eng", "name": "Engineering", "description": "Product engineers", "ouId": "ou-1",
       "ouHandle": "default"},
      {"id": "grp-sup", "name": "Support", "description": "Customer support", "ouId": "ou-1",
       "ouHandle": "default"},
      {"id": "grp-bots", "name": "Automation", "ouId": "ou-1", "ouHandle": "default"}
    ]
    """)

    static let members: [GroupMember] = [
        GroupMember(id: "usr-liam", type: .user, display: "Liam Chen"),
        GroupMember(id: "usr-ana", type: .user, display: "Ana Silva"),
        GroupMember(id: "agt-triage", type: .agent, display: "Ticket triage agent"),
        GroupMember(id: "grp-sup", type: .group, display: "Support")
    ]

    static let roles: [RoleSummary] = decode("""
    [
      {"id": "role-admin", "name": "Administrator", "description": "Full access", "ouId": "ou-1",
       "ouHandle": "default", "isReadOnly": true},
      {"id": "role-viewer", "name": "Viewer", "description": "Read-only access", "ouId": "ou-1",
       "ouHandle": "default"},
      {"id": "role-agent", "name": "Agent operator", "ouId": "ou-1", "ouHandle": "default"}
    ]
    """)

    static let assignments: [RoleAssignment] = [
        RoleAssignment(id: "usr-liam", type: .user, display: "Liam Chen"),
        RoleAssignment(id: "grp-eng", type: .group, display: "Engineering"),
        RoleAssignment(id: "app-console", type: .app, display: "Console"),
        RoleAssignment(id: "agt-triage", type: .agent, display: "Ticket triage agent")
    ]

    static let permissions: [RoleResourcePermissions] = [
        RoleResourcePermissions(
            resourceServerId: "rs-system",
            permissions: ["system:user:view", "system:group:view", "system:role:view"]
        ),
        RoleResourcePermissions(resourceServerId: "rs-orders", permissions: ["orders:read", "orders:write"])
    ]

    static let resourceServerNames = ["rs-system": "ThunderID system API", "rs-orders": "Orders API"]

    /// Candidates for the membership and assignment pickers.
    static let userCandidates = [
        IdentityCandidate(id: "usr-noah", label: "Noah Patel"),
        IdentityCandidate(id: "usr-mia", label: "Mia Rossi")
    ]
    static let agentCandidates = [IdentityCandidate(id: "agt-billing", label: "Billing assistant")]
    static let groupCandidates = [IdentityCandidate(id: "grp-bots", label: "Automation")]

    static let users: [ManagedUser] = decode("""
    [
      {"id": "usr-liam", "ouId": "ou-1", "ouHandle": "default", "type": "person", "display": "Liam Chen",
       "attributes": {"email": "liam@example.com", "given_name": "Liam", "family_name": "Chen",
                      "username": "liam"}},
      {"id": "usr-ana", "ouId": "ou-1", "ouHandle": "default", "type": "person",
       "attributes": {"email": "ana@example.com", "name": "Ana Silva", "username": "ana"}},
      {"id": "usr-svc", "ouId": "ou-1", "ouHandle": "default", "type": "service", "isReadOnly": true,
       "attributes": {"username": "svc-reporting"}}
    ]
    """)

    static let userGroups: [MembershipGroup] = decode("""
    [{"id": "grp-eng", "name": "Engineering", "ouId": "ou-1"}, {"id": "grp-sup", "name": "Support", "ouId": "ou-1"}]
    """)

    static let agents: [BasicAgent] = decode("""
    [
      {"id": "agt-triage", "ouId": "ou-1", "ouHandle": "default", "type": "assistant",
       "display": "Ticket triage agent", "attributes": {"name": "Ticket triage agent"},
       "description": "Labels and routes support tickets", "clientId": "triage"},
      {"id": "agt-billing", "ouId": "ou-1", "ouHandle": "default", "type": "assistant",
       "display": "Billing assistant", "attributes": {"name": "Billing assistant"},
       "description": "Answers invoice questions"},
      {"id": "agt-sync", "ouId": "ou-1", "type": "service", "display": "Directory sync",
       "attributes": {"name": "Directory sync"}, "isReadOnly": true}
    ]
    """)

    static let agent: Agent = decode("""
    {"id": "agt-triage", "ouId": "ou-1", "ouHandle": "default", "type": "assistant",
     "display": "Ticket triage agent", "description": "Labels and routes support tickets",
     "owner": "usr-liam", "clientId": "triage",
     "attributes": {"name": "Ticket triage agent", "model": "triage-v2"}}
    """)

    static let agentRoles = ["Agent operator", "Viewer"]

    static let userTypes = [
        AdminOption(label: "Person", value: "person"),
        AdminOption(label: "Service", value: "service")
    ]
    static let agentTypes = [
        AdminOption(label: "Assistant", value: "assistant"),
        AdminOption(label: "Service", value: "service")
    ]

    static let applications: [BasicApplication] = decode("""
    [
      {"id": "app-console", "name": "Console", "clientId": "console", "type": "browser",
       "template": "react", "status": {"value": "ACTIVE"}},
      {"id": "app-billing", "name": "Billing service", "clientId": "billing", "type": "m2m",
       "status": {"value": "SUSPENDED"}},
      {"id": "app-portal", "name": "Partner portal", "type": "fullstack", "isReadOnly": true}
    ]
    """)

    static let application: Application = decode("""
    {"id": "app-console", "name": "Console", "description": "The admin console", "type": "browser",
     "ouId": "ou-1", "url": "https://console.example.com", "status": {"value": "ACTIVE"},
     "inboundAuthConfig": [{"type": "oauth2", "config": {"clientId": "console", "publicClient": false,
       "redirectUris": ["https://console.example.com/callback"],
       "grantTypes": ["authorization_code", "refresh_token"], "responseTypes": ["code"]}}]}
    """)

    private static func decode<Value: Decodable>(_ json: String) -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: Data(json.utf8))
        } catch {
            fatalError("Invalid admin sample for \(Value.self): \(error)")
        }
    }
}
