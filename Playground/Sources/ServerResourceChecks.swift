// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderIDSwiftUI

/// Read-only checks for applications and the server resources (organization units, resource servers,
/// flows, design, translations, server configuration). Nothing here changes the server.
extension CheckContext {
    static let serverResourceRunners: [CapabilityID: Runner] = [
        .applications: { try await $0.applications() },
        .serverResources: { try await $0.serverResources() }
    ]

    /// Lists applications and reads the first, so the application stories have one to point at.
    func applications() async throws -> String {
        try await requireSignedIn()
        let page = try await client.applications.list(limit: 20)
        log.record("applications:listed", "\(page.totalResults) total", kind: .success)
        guard let first = page.applications.first else {
            return "applications.list() works; the server has no applications yet."
        }
        let application = try await client.applications.get(id: first.id)
        ids.applicationId = application.id
        let grants = application.request.inboundAuthConfig?.first?.config.grantTypes ?? []
        return "\(page.totalResults) applications; \"\(application.name)\" has "
            + (grants.isEmpty ? "no OAuth client" : "grants \(grants.joined(separator: ", "))")
    }

    /// Reads one page of each server resource family the SDK manages.
    func serverResources() async throws -> String {
        try await requireSignedIn()
        let units = try await client.organizationUnits.list(limit: 5)
        let servers = try await client.resourceServers.list(limit: 5)
        let flows = try await client.flows.list(limit: 5)
        let themes = try await client.design.themes(limit: 5)
        let languages = try await client.translations.languages()
        let sections = try await client.serverConfig.names()
        let summary = "\(units.totalResults ?? units.organizationUnits.count) organization units, "
            + "\(servers.totalResults ?? servers.resourceServers.count) resource servers, "
            + "\(flows.totalResults ?? flows.flows.count) flows, \(themes.totalResults ?? themes.themes.count) themes, "
            + "\(languages.languages.count) languages, \(sections.count) config sections"
        log.record("server:resources", summary, kind: .success)
        return summary
    }

    /// Makes the SDK build a request for one of the server resource collections, for the endpoints check.
    func probeServerResource(_ path: String, fetcher: @escaping ThunderIDFetcher) async {
        _ = try? await Self.serverResourceProbes[path]?(client, fetcher)
    }

    private typealias Probe = (ThunderIDClient, @escaping ThunderIDFetcher) async throws -> Void

    private static let serverResourceProbes: [String: Probe] = [
        "organization-units": { _ = try await $0.organizationUnits.list(limit: 1, fetcher: $1) },
        "resource-servers": { _ = try await $0.resourceServers.list(limit: 1, fetcher: $1) },
        "connections": { _ = try await $0.connections.list(limit: 1, fetcher: $1) },
        "flows": { _ = try await $0.flows.list(limit: 1, fetcher: $1) },
        "notification-templates": { _ = try await $0.notificationTemplates.list(channel: .email, fetcher: $1) },
        "design": { _ = try await $0.design.themes(limit: 1, fetcher: $1) },
        "i18n": { _ = try await $0.translations.languages(fetcher: $1) },
        "server-config": { _ = try await $0.serverConfig.names(fetcher: $1) },
        "gateways": { _ = try await $0.gateways.list(fetcher: $1) },
        "variables": { _ = try await $0.variables.list(limit: 1, fetcher: $1) },
        "secrets": { _ = try await $0.secrets.list(limit: 1, fetcher: $1) },
        "configuration-versions": { _ = try await $0.configuration.versions(fetcher: $1) },
        "import": { _ = try await $0.configuration.importConfiguration(ImportRequest(dryRun: true), fetcher: $1) },
        "export": { _ = try await $0.configuration.exportConfiguration(ExportRequest(), fetcher: $1) },
        "openid4vci/credential-configurations": { _ = try await $0.credentialConfigurations.list(fetcher: $1) },
        "openid4vp/presentation-definitions": { _ = try await $0.presentationDefinitions.list(fetcher: $1) },
        "projects": { _ = try await $0.projects.list(limit: 1, fetcher: $1) },
        "authorization-detail-types": { _ = try await $0.authorizationDetailTypes.list(limit: 1, fetcher: $1) },
        // The probe fetcher stops the request, so this registers nothing.
        "oauth2/dcr/register": {
            _ = try await $0.clientRegistrations.register(ClientRegistrationRequest(redirectUris: []), fetcher: $1)
        }
    ]
}
