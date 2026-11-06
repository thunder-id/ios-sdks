// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderIDSwiftUI

/// Read-only checks for groups by path, role and flow sharing with flow variables, projects, and
/// authorization details types. Nothing here changes the server.
extension CheckContext {
    static let sharingProjectRunners: [CapabilityID: Runner] = [
        .groupsByPath: { try await $0.groupsByPath() },
        .resourceSharing: { try await $0.resourceSharing() },
        .projects: { try await $0.projects() },
        .authorizationDetailTypes: { try await $0.authorizationDetailTypes() }
    ]

    /// Lists the groups of the first organization unit, addressed by its handle path.
    func groupsByPath() async throws -> String {
        try await requireSignedIn()
        let unit = try await firstOrganizationUnit()
        let page = try await client.groups.list(path: unit.handle, limit: 20)
        log.record("groups:byPath", "\(page.totalResults) in \(unit.handle)", kind: .success)
        return "\(page.totalResults) groups in \"\(unit.handle)\" via groups/tree/\(unit.handle)"
    }

    /// Reads the sharing policies of the first role and flow, how they look from the first organization
    /// unit, and that unit's values for the flow's variables.
    func resourceSharing() async throws -> String {
        try await requireSignedIn()
        let unit = try await firstOrganizationUnit()
        let roleId = try await firstRoleId()
        let rolePolicies = try await client.roles.sharingPolicies(id: roleId, limit: 20)
        let roleOverlay = try await client.roles.overlayRules(id: roleId, ouId: unit.id)
        guard let flow = try await client.flows.list(limit: 1).flows.first else {
            return "Role \(short(roleId)): \(rolePolicies.policies.count) policies; the server has no flows."
        }
        let flowPolicies = try await client.flows.sharingPolicies(id: flow.id, limit: 20)
        let flowOverlay = try await client.flows.overlayRules(id: flow.id, ouId: unit.id)
        let variables = try await client.flows.variables(id: flow.id, ouId: unit.id)
        let summary = "role: \(rolePolicies.policies.count) policies, "
            + "\(roleOverlay.visible == true ? "visible" : "not visible") in \(unit.handle); "
            + "flow \"\(flow.handle)\": \(flowPolicies.policies.count) policies, "
            + "\(flowOverlay.rules?.count ?? 0) variable rules, \(variables.values.count) values set"
        log.record("sharing:read", summary, kind: .success)
        return summary
    }

    /// Lists projects. Only the Control Plane serves them, so a 404 says this server is a Data Plane.
    func projects() async throws -> String {
        try await requireSignedIn()
        do {
            let page = try await client.projects.list(limit: 20)
            log.record("projects:listed", "\(page.totalResults ?? page.projects.count) total", kind: .success)
            guard let first = page.projects.first else { return "projects.list() works; there are no projects." }
            let project = try await client.projects.get(id: first.id)
            return "\(page.totalResults ?? page.projects.count) projects; fetched \"\(project.displayName)\""
        } catch let error as ThunderIDError where error.code == .notFound {
            return "This server does not serve /projects: only the Control Plane does."
        }
    }

    /// Lists the managed authorization details types, then the ones a client may request, which needs no
    /// sign-in.
    func authorizationDetailTypes() async throws -> String {
        let supported = try await client.getSupportedAuthorizationDetailsTypes()
        guard (try? await client.isSignedIn()) == true else {
            return "\(supported.types.count) types a client may request. Sign in to list the managed ones."
        }
        let managed = try await client.authorizationDetailTypes.list(limit: 20)
        let summary = "\(managed.totalResults ?? managed.types.count) managed, "
            + "\(supported.types.count) a client may request"
        log.record("authorizationDetailTypes:listed", summary, kind: .success)
        return summary
    }

    private func firstOrganizationUnit() async throws -> OrganizationUnitSummary {
        guard let unit = try await client.organizationUnits.list(limit: 1).organizationUnits.first else {
            throw CheckFailure("The server has no organization units.")
        }
        return unit
    }
}
